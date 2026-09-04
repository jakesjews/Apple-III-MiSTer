#include "Vcore_tb.h"
#include "dsk2nib.h"
#include "verilated.h"
#include <array>
#include <cstdlib>
#include <cstdio>
#include <string>
#include <vector>

struct TraceEntry {
	unsigned pc;
	unsigned opcode;
	unsigned a;
	unsigned x;
	unsigned y;
	unsigned sp;
	unsigned p;
	unsigned environment;
	unsigned zero_page;
	unsigned bank;
	unsigned track;
};

struct DiskReadEntry {
	unsigned pc;
	unsigned data;
	unsigned track;
	unsigned address;
};

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	Vcore_tb top;
	std::vector<uint8_t> disk_image;
	const bool disk_test = argc > 2;
	const bool buffered_disk = disk_test && argc > 3 &&
	                           std::string(argv[3]) == "--buffered";
	if (disk_test) {
		std::string error;
		if (!apple3_disk_image::load(argv[2], disk_image, error)) {
			std::fprintf(stderr, "FAIL: %s\n", error.c_str());
			return 1;
		}
	}
	top.clk = 0;
	top.reset = 1;
	top.disk_present = disk_test;
	top.buffered_disk = buffered_disk;
	top.direct_track1_dout = 0;
	top.image_change = 0;
	top.image_mount = disk_test;
	top.sd_ack = 0;
	top.sd_buff_addr = 0;
	top.sd_buff_dout = 0;
	top.sd_buff_wr = 0;
	uint8_t track_q = 0;
	uint8_t next_track_q = 0;
	std::size_t sd_byte = 0;
	bool sd_finishing = false;
	bool sd_transfer_read = false;
	unsigned sd_block_reads = 0;

	auto prepare_storage = [&]() {
		if (top.clk) return;
		top.sd_buff_wr = 0;
		if (buffered_disk) {
			if (sd_finishing) {
				top.sd_ack = 0;
				sd_finishing = false;
				sd_transfer_read = false;
			}
			if (!top.sd_ack && (top.sd_rd || top.sd_wr)) {
				top.sd_ack = 1;
				sd_transfer_read = top.sd_rd;
				sd_byte = 0;
				if (top.sd_rd) ++sd_block_reads;
			}
			if (top.sd_ack) {
				const std::size_t offset = static_cast<std::size_t>(top.sd_lba) * 512 +
				                           sd_byte;
				top.sd_buff_addr = sd_byte;
				top.sd_buff_dout = offset < disk_image.size() ? disk_image[offset] : 0xff;
				top.sd_buff_wr = sd_transfer_read;
			}
		}
		else if (disk_test) {
			const std::size_t offset = static_cast<std::size_t>(top.track1) *
			                           apple3_disk_image::kTrackBytes + top.track1_addr;
			next_track_q = offset < disk_image.size() ? disk_image[offset] : 0xff;
			top.direct_track1_dout = track_q;
		}
	};

	auto finish_storage = [&]() {
		if (!top.clk) return;
		if (buffered_disk && top.sd_ack && top.sd_buff_wr) {
			if (sd_byte == 511) sd_finishing = true;
			else ++sd_byte;
		}
		else if (!buffered_disk) {
			track_q = next_track_q;
		}
	};

	for (int i = 0; i < 128; ++i) {
		prepare_storage();
		top.clk ^= 1;
		top.eval();
		finish_storage();
	}
	top.reset = 0;
	if (buffered_disk) {
		// Match an image-mounted notification followed by the stable toggle
		// used by the MiSTer track cache.
		top.image_change = 1;
		for (int i = 0; i < 4; ++i) {
			prepare_storage();
			top.clk ^= 1;
			top.eval();
			finish_storage();
		}
		top.image_change = 0;
	}

	std::array<unsigned, 16> first_pcs{};
	unsigned sync_count = 0;
	unsigned enable_count = 0;
	unsigned last_pc = 0;
	bool reached_bank_loop_exit = false;
	bool reached_reconfigure = false;
	bool reached_disk_boot = false;
	bool reached_disk_bootstrap = false;
	bool boot_block_error = false;
	bool passed_extended_fetch_regression = false;
	bool reached_loader_return = false;
	bool reached_loader_jump = false;
	bool reached_interpreter = false;
	unsigned loader_io_error = 0;
	bool disk_hard_error = false;
	unsigned find_good_count = 0;
	unsigned find_error_count = 0;
	unsigned read_error_count = 0;
	unsigned retry_count = 0;
	unsigned recalibrate_count = 0;
	bool reached_system_failure = false;
	uint8_t system_failure_code = 0;
	unsigned bank_changes = 0;
	unsigned previous_bank_output = top.e_pa_o;
	std::array<TraceEntry, 256> trace{};
	std::size_t trace_next = 0;
	std::size_t trace_count = 0;
	std::array<unsigned, 32> target_writes{};
	std::array<unsigned, 32> target_values{};
	std::array<uint8_t, 256> zero_page_values{};
	std::array<DiskReadEntry, 256> disk_reads{};
	std::size_t disk_read_next = 0;
	std::size_t disk_read_count = 0;
	const unsigned long long half_cycles = argc > 1
		? std::strtoull(argv[1], nullptr, 0) : 30000000ULL;
	for (unsigned long long half_cycle = 0; half_cycle < half_cycles; ++half_cycle) {
		prepare_storage();
		top.clk ^= 1;
		top.eval();
		finish_storage();
		if (top.clk && top.cpu_enable) {
			++enable_count;
			if (!top.cpu_rwn && top.cpu_addr < 0x100)
				zero_page_values[top.cpu_addr] = top.cpu_dout;
			if (top.cpu_rwn && top.cpu_addr == 0xc0ec) {
				disk_reads[disk_read_next] = {
					top.pc, top.cpu_din, top.track1, top.track1_addr
				};
				disk_read_next = (disk_read_next + 1) % disk_reads.size();
				if (disk_read_count < disk_reads.size()) ++disk_read_count;
			}
			if (top.ram_write && top.ram_byte_addr >= 0x3bea0 &&
			    top.ram_byte_addr < 0x3bec0) {
				const unsigned index = top.ram_byte_addr - 0x3bea0;
				++target_writes[index];
				target_values[index] = top.cpu_dout;
			}
			if (top.e_pa_o != previous_bank_output) {
				previous_bank_output = top.e_pa_o;
				++bank_changes;
			}
			if (top.cpu_sync) {
				trace[trace_next] = {top.cpu_addr, top.cpu_din, top.a, top.x, top.y,
				                     top.sp, top.p, top.environment, top.zero_page,
				                     top.bank, top.track1};
				trace_next = (trace_next + 1) % trace.size();
				if (trace_count < trace.size()) ++trace_count;
				if (sync_count < first_pcs.size()) first_pcs[sync_count] = top.cpu_addr;
				last_pc = top.cpu_addr;
				if (top.cpu_addr == 0xF575) reached_bank_loop_exit = true;
				if (top.cpu_addr == 0xF686) reached_reconfigure = true;
				if (top.cpu_addr == 0xF697) reached_disk_boot = true;
				if (top.cpu_addr == 0xF6B5) boot_block_error = true;
				if (top.cpu_addr == 0xA000) reached_disk_bootstrap = true;
				// SOS 1.3 executes this instruction immediately after the fetch
				// that exposed a stale enhanced-address latch in early core builds.
				if (top.cpu_addr == 0xBEB1) passed_extended_fetch_regression = true;
				// $1E98 is reached only after SOSLDR1 has loaded and initialized the
				// interpreter, kernel, and driver files.  Earlier $2xxx execution is
				// the loader itself and must not be mistaken for a successful boot.
				if (top.cpu_addr == 0x1E98) reached_loader_return = true;
				if (top.cpu_addr == 0x1EB0) reached_loader_jump = true;
				if (reached_loader_jump && top.cpu_addr != 0x1EB0 &&
				    top.zero_page == 0x1a)
					reached_interpreter = true;
				if (top.cpu_addr == 0x20A0) loader_io_error = 0x20A0;
				if (top.cpu_addr == 0x2124) loader_io_error = 0x2124;
				if (top.cpu_addr == 0x22B3) loader_io_error = 0x22B3;
				if (top.cpu_addr == 0xEC0E) ++find_good_count;
				if (top.cpu_addr == 0xEC14) ++find_error_count;
				if (top.cpu_addr == 0xEBA0) ++read_error_count;
				if (top.cpu_addr == 0xEBA2) ++retry_count;
				if (top.cpu_addr == 0xEBA6) ++recalibrate_count;
				if (top.cpu_addr == 0xEBC2) disk_hard_error = true;
				if (top.cpu_addr == 0xEE2A) {
					reached_system_failure = true;
					system_failure_code = top.a;
				}
				++sync_count;
			}
		}
		if (reached_system_failure || reached_interpreter || loader_io_error ||
		    boot_block_error ||
		    disk_hard_error) break;
	}

	std::printf("boot syncs=%u cycles=%u last=%04X env=%02X zp=%02X bank=%02X vm=%X disk=%u\n",
	            sync_count, enable_count, last_pc, top.environment, top.zero_page,
	            top.bank, top.video_mode, top.disk_activity);
	std::printf("first PCs:");
	for (unsigned value : first_pcs) std::printf(" %04X", value);
	std::printf("\n");
	std::printf("milestones bank_exit=%u reconfigure=%u disk_boot=%u bank_changes=%u\n",
	            reached_bank_loop_exit, reached_reconfigure, reached_disk_boot,
	            bank_changes);
	if (disk_test)
		std::printf("disk image=%s buffered=%u sd_reads=%u bootstrap_A000=%u boot_block_error=%u ext_fetch_ok=%u loader_return=%u "
		            "loader_jump=%u interpreter=%u final_track=%u loader_io_error=%04X "
		            "sysfail=%u code=%02X\n",
		            argv[2], buffered_disk, sd_block_reads, reached_disk_bootstrap,
		            boot_block_error,
		            passed_extended_fetch_regression,
		            reached_loader_return, reached_loader_jump, reached_interpreter,
		            top.track1, loader_io_error, reached_system_failure,
		            system_failure_code);
	if (disk_test)
		std::printf("disk paths find_good=%u find_error=%u read_error=%u retry=%u "
		            "recalibrate=%u hard_error=%u zp98=%02X zp99=%02X zp9A=%02X "
		            "zpD4=%02X zpD5=%02X zpD6=%02X zpD7=%02X zpD8=%02X\n",
		            find_good_count, find_error_count, read_error_count, retry_count,
		            recalibrate_count, disk_hard_error, zero_page_values[0x98],
		            zero_page_values[0x99], zero_page_values[0x9a],
		            zero_page_values[0xd4], zero_page_values[0xd5],
		            zero_page_values[0xd6], zero_page_values[0xd7],
		            zero_page_values[0xd8]);
	if (reached_system_failure || loader_io_error || disk_hard_error ||
	    boot_block_error) {
		std::printf("writes to physical $3BEA0-$3BEBF:\n");
		for (unsigned index = 0; index < target_writes.size(); ++index)
			std::printf("%05X=%02X(%u)%c", 0x3bea0 + index, target_values[index],
			            target_writes[index], (index & 7) == 7 ? '\n' : ' ');
		std::printf("last %zu instructions:\n", trace_count);
		const std::size_t trace_start = (trace_next + trace.size() - trace_count) % trace.size();
		for (std::size_t index = 0; index < trace_count; ++index) {
			const auto &entry = trace[(trace_start + index) % trace.size()];
			std::printf("%04X  %02X  A=%02X X=%02X Y=%02X S=%02X P=%02X "
			            "E=%02X Z=%02X B=%02X T=%02X\n",
			            entry.pc, entry.opcode, entry.a, entry.x, entry.y,
			            entry.sp, entry.p, entry.environment, entry.zero_page,
			            entry.bank, entry.track);
		}
		std::printf("last %zu disk-latch reads:\n", disk_read_count);
		const std::size_t disk_start =
			(disk_read_next + disk_reads.size() - disk_read_count) % disk_reads.size();
		for (std::size_t index = 0; index < disk_read_count; ++index) {
			const auto &entry = disk_reads[(disk_start + index) % disk_reads.size()];
			std::printf("PC=%04X D=%02X T=%02X TA=%04X%c", entry.pc, entry.data,
			            entry.track, entry.address, (index & 3) == 3 ? '\n' : ' ');
		}
		if (disk_read_count & 3) std::printf("\n");
	}

	if (sync_count < 100) {
		std::fprintf(stderr, "FAIL: boot ROM did not execute enough instructions\n");
		return 1;
	}
	if (first_pcs[0] != 0xF4EE) {
		std::fprintf(stderr, "FAIL: reset vector started at %04X, expected F4EE\n", first_pcs[0]);
		return 1;
	}
	if (!reached_bank_loop_exit || bank_changes < 4) {
		std::fprintf(stderr, "FAIL: ROM did not discover the 256 KiB RAM banks\n");
		return 1;
	}
	if (!reached_reconfigure || !reached_disk_boot) {
		std::fprintf(stderr, "FAIL: ROM did not pass diagnostics and enter disk boot\n");
		return 1;
	}
	if (disk_test && !reached_disk_bootstrap) {
		std::fprintf(stderr, "FAIL: ROM did not read block 0 and jump to $A000\n");
		return 1;
	}
	if (disk_test && !reached_interpreter) {
		if (loader_io_error)
			std::fprintf(stderr, "FAIL: SOS loader entered I/O ERROR path at $%04X\n",
			             loader_io_error);
		else
			std::fprintf(stderr,
			             "FAIL: SOS did not finish loading and enter the interpreter\n");
		return 1;
	}
	if (disk_test && reached_system_failure) {
		std::fprintf(stderr, "FAIL: SOS entered SYSDEATH with code $%02X\n",
		             system_failure_code);
		return 1;
	}
	return 0;
}
