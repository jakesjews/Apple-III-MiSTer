#include "Vcore_tb.h"
#include "verilated.h"
#include <array>
#include <cstdlib>
#include <cstring>
#include <cstdio>
#include <fstream>
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
	std::vector<uint8_t> disk_image[4];
	std::string drive_path[4];
	if (argc > 2) drive_path[0] = argv[2];
	const bool disk_test = argc > 2;
	bool key_test = false, warm_reset = false, to_menu = false, disk_trace = false, trace_all = false;
	bool plus_keymap = false;  // Apple /// Plus keyboard: separate DELETE key
	// --check-font: after --to-menu, the character generator must hold the set
	// the console driver keeps at $0C00, loaded through the screen holes.
	bool check_font = false;
	// --font-dump=01,02: print these codes' character generator rows at the end.
	std::vector<unsigned> font_dump;
	// --keys=down,down,enter,wait5,enter typed once --keys-after=TEXT is on screen.
	std::string keys, keys_after;
	bool writable = false;  // mount images read-write, as Main does for writable sources
	unsigned sd_delay = 0;
	// MGL-style sequencing: seconds of machine time before each mount, and
	// between the last mount and the reset that MiSTer issues afterwards.
	double mount_delay = 0, reset_delay = -1;
	// --to-menu waits for this text; --expect=TEXT substitutes another title's screen.
	std::string expect = "Device handling";
	// Host clocks per transferred byte. 4 is far quicker than the HPS link.
	unsigned sd_byte_clocks = 4;
	// Extra host clocks before each write request is served (slow image saves).
	unsigned sd_write_delay = 0;
	// Host clock as MiSTer sends it: --rtc=YYMMDDWhhmmss, W = weekday with Sunday = 0.
	std::string rtc;
	for (int i = 3; i < argc; ++i) {
		std::string option = argv[i];
		if (option.rfind("--sd-delay=", 0) == 0) sd_delay = std::strtoul(argv[i] + 11, nullptr, 10);
		for (unsigned drive = 1; drive < 4; ++drive)
			if (option.rfind("--drive" + std::to_string(drive + 1) + "=", 0) == 0) drive_path[drive] = option.substr(9);
		if (option == "--keytest") key_test = true;
		if (option == "--plus-keymap") plus_keymap = true;
		if (option == "--check-font") check_font = to_menu = true;
		if (option.rfind("--font-dump=", 0) == 0)
			for (std::size_t at = 12; at < option.size(); at = option.find(',', at) + 1) {
				font_dump.push_back(std::strtoul(option.c_str() + at, nullptr, 16) & 0x7f);
				if (option.find(',', at) == std::string::npos) break;
			}
		if (option == "--warm-reset") warm_reset = true;
		if (option == "--to-menu") to_menu = true;
		if (option == "--disk-trace") disk_trace = true;
		if (option == "--disk-trace-all") disk_trace = trace_all = true;
		if (option == "--writable") writable = true;
		if (option.rfind("--keys=", 0) == 0) keys = option.substr(7);
		if (option.rfind("--keys-after=", 0) == 0) keys_after = option.substr(13);
		if (option.rfind("--rtc=", 0) == 0) rtc = option.substr(6);
		if (option.rfind("--expect=", 0) == 0) { expect = option.substr(9); to_menu = true; }
		if (option.rfind("--sd-write-delay=", 0) == 0) sd_write_delay = std::strtoul(argv[i] + 17, nullptr, 10);
		if (option.rfind("--sd-byte-clocks=", 0) == 0) sd_byte_clocks = std::strtoul(argv[i] + 17, nullptr, 10);
		if (option.rfind("--mount-delay=", 0) == 0) mount_delay = std::strtod(argv[i] + 14, nullptr);
		if (option.rfind("--reset-delay=", 0) == 0) reset_delay = std::strtod(argv[i] + 14, nullptr);
	}
	for (unsigned drive = 0; drive < 4; ++drive) {
		if (!disk_test || drive_path[drive].empty()) continue;
		const char *path = drive_path[drive].c_str();
		std::ifstream input(path, std::ios::binary);
		disk_image[drive].assign(std::istreambuf_iterator<char>(input), {});
		if (disk_image[drive].size() < 12 || std::string(disk_image[drive].begin(),disk_image[drive].begin()+3) != "WOZ") {
			std::fprintf(stderr,"FAIL: supply native WOZ or an image converted by Main: %s\n", path); return 1;
		}
	}
	top.serial_rx = 1;
	top.serial_cts_n = 0;
	top.serial_dsr_n = 0;
	top.clk = 0;
	top.reset = 1;
	top.image_change = 0;
	top.image_readonly = !writable;
	top.image_size = 0;
	top.sd_ack = 0;
	top.sd_buff_addr = 0;
	top.sd_buff_dout = 0;
	top.sd_buff_wr = 0;
	top.ps2_key = 0;
	top.plus_keymap = plus_keymap;
	top.probe_addr = 0;
	top.probe_font_addr = 0;
	top.joy_a_x = top.joy_a_y = top.joy_b_x = top.joy_b_y = 0x80;
	top.joy_a_button = top.joy_a_switch = top.joy_b_button = top.joy_b_switch = 0;
	top.host_rtc[0] = top.host_rtc[1] = top.host_rtc[2] = 0;
	if (rtc.size() == 13) {
		auto bcd = [&](std::size_t at) { return unsigned(rtc[at] - '0') << 4 | unsigned(rtc[at + 1] - '0'); };
		top.host_rtc[0] = bcd(11) | bcd(9) << 8 | bcd(7) << 16 | bcd(4) << 24;
		top.host_rtc[1] = bcd(2) | bcd(0) << 8 | unsigned(rtc[6] - '0') << 16 | 0x40u << 24;
		top.host_rtc[2] = 1;  // toggle bit: a new time has arrived
	}
	std::size_t sd_byte = 0, sd_transfer_bytes = 512, sd_start = 0;
	unsigned sd_disk = 0, sd_tick = 0, sd_wait_cycles = 0, sd_block_reads = 0;
	bool sd_finishing = false, sd_transfer_read = false;
	auto prepare_storage = [&]() {
		if (top.clk) return;
		top.sd_buff_wr = 0;
		if (sd_finishing) { top.sd_ack = 0; sd_finishing = false; return; }
		if (!top.sd_ack && (top.sd_rd || top.sd_wr)) {
			if (sd_wait_cycles++ < sd_delay + (top.sd_wr ? sd_write_delay : 0)) return;
			sd_wait_cycles = 0;
			unsigned requests = top.sd_rd | top.sd_wr;
			for (sd_disk = 0; !(requests & (1 << sd_disk)); ++sd_disk) {}
			top.sd_ack = 1 << sd_disk;
			sd_transfer_read = top.sd_rd & (1 << sd_disk);
			sd_byte = 0; sd_tick = 0;
			sd_transfer_bytes = (top.sd_blk_cnt[sd_disk] + 1) * 512;
			sd_start = static_cast<std::size_t>(top.sd_lba[sd_disk]) * 512;
			if (sd_transfer_read) ++sd_block_reads;
		}
		if (top.sd_ack) {
			const auto &data = disk_image[sd_disk];
			top.sd_buff_addr = sd_byte;
			top.sd_buff_dout = sd_start + sd_byte < data.size() ? data[sd_start+sd_byte] : 0;
			top.sd_buff_wr = sd_transfer_read && sd_tick == sd_byte_clocks - 1;
		}
	};
	auto finish_storage = [&]() {
		if (!top.clk || !top.sd_ack) return;
		if (++sd_tick < sd_byte_clocks) return;
		sd_tick = 0;
		if (!sd_transfer_read && sd_start + sd_byte < disk_image[sd_disk].size())
			disk_image[sd_disk][sd_start+sd_byte] = top.sd_buff_din[sd_disk];
		if (++sd_byte == sd_transfer_bytes) sd_finishing = true;
	};

	for (int i = 0; i < 128; ++i) {
		prepare_storage();
		top.clk ^= 1;
		top.eval();
		finish_storage();
	}
	top.reset = 0;
	auto run_seconds = [&](double seconds) {
		const unsigned long long steps = static_cast<unsigned long long>(seconds * 2 * 14318181.0);
		for (unsigned long long i = 0; i < steps; ++i) { prepare_storage(); top.clk ^= 1; top.eval(); finish_storage(); }
	};
	for (unsigned drive = 0; drive < 4; ++drive) {
		if (disk_image[drive].empty()) continue;
		run_seconds(mount_delay);
		top.image_size = disk_image[drive].size(); top.image_change = 1 << drive;
		for (int i = 0; i < 8; ++i) { prepare_storage(); top.clk ^= 1; top.eval(); finish_storage(); }
		top.image_change = 0;
		for (int i = 0; i < 8; ++i) { prepare_storage(); top.clk ^= 1; top.eval(); finish_storage(); }
	}

	if (reset_delay >= 0) {
		run_seconds(reset_delay);
		std::printf("MGL reset at pc=%04X env=%02X zp=%02X after %.2f s\n", top.pc, top.environment, top.zero_page, reset_delay);
		top.reset = 1; run_seconds(0.05); top.reset = 0;
	}
	if (warm_reset) {
		// MGL-style reset after both mounts, including an in-flight transfer.
		for (unsigned i = 0; i < 8000000; ++i) { prepare_storage(); top.clk ^= 1; top.eval(); finish_storage(); }
		top.reset = 1;
		for (unsigned i = 0; i < 2863640; ++i) { prepare_storage(); top.clk ^= 1; top.eval(); finish_storage(); }
		top.reset = 0;
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
	bool reached_menu = false;
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
	// Keyboard script: PS/2 events are injected at machine times after SOS has
	// drawn its first menu, and the text page is decoded afterwards so the
	// response can be compared with hardware screenshots.
	struct KeyEvent { unsigned long long cycle; uint8_t code; bool ext; bool pressed; };
	struct ScreenDump { unsigned long long cycle; const char *label; };
	std::vector<KeyEvent> key_script;
	std::vector<ScreenDump> dump_script;
	const unsigned long long second = 14318181ULL;
	auto tap = [&](double at, uint8_t code, bool ext, int only = -1) {
		const unsigned long long start = static_cast<unsigned long long>(at * second);
		if (only != 0) key_script.push_back({start, code, ext, true});
		if (only != 1) key_script.push_back({start + second / 20, code, ext, false});
	};
	// The script is armed once the System Utilities menu text is on screen;
	// times are then relative to that moment (t0), matching the hardware test.
	bool script_armed = false, keys_armed = false;
	auto schedule_script = [&](unsigned long long t0) {
		const double base = static_cast<double>(t0) / second;
		dump_script.push_back({t0, "before keys"});
		tap(base + 0.0, 0x23, false);                        // D
		dump_script.push_back({t0 + 1 * second, "after D"});
		tap(base + 1.0, 0x76, false);                        // Escape
		dump_script.push_back({t0 + 2 * second, "after Escape"});
		tap(base + 2.0, 0x23, false);                        // D
		tap(base + 3.0, 0x5a, false);                        // Return
		dump_script.push_back({t0 + 4 * second, "after D, Return"});
		tap(base + 4.0, 0x76, false);                        // Escape
		dump_script.push_back({t0 + 5 * second, "after Escape (2)"});
		tap(base + 5.0, 0x72, true);                         // Down arrow
		dump_script.push_back({t0 + 6 * second, "after Down"});
		tap(base + 6.0, 0x12, false, true);                  // hold Shift ...
		tap(base + 6.2, 0x23, false);                        // ... D (shifted)
		tap(base + 6.4, 0x12, false, false);                 // release Shift
		dump_script.push_back({t0 + 7 * second, "after Shift+D"});
	};
	std::size_t key_index = 0;
	std::size_t dump_index = 0;
	unsigned keyboard_trace_count = 0;
	bool key_toggle = false;
	auto read_screen = [&]() {
		const bool wide = (top.video_mode & 0x2) != 0;
		const bool page2 = (top.video_mode & 0x4) != 0;
		static const unsigned group[3] = {0, 40, 80};
		std::vector<std::string> rows;
		for (unsigned row = 0; row < 24; ++row) {
			const unsigned base = 0x38000 + 0x400 + ((row & 7) << 7) + group[row >> 3];
			const unsigned columns = wide ? 80 : 40;
			std::string text;
			for (unsigned col = 0; col < columns; ++col) {
				const unsigned byte_addr = base + (wide ? (col >> 1) : col);
				const unsigned word = ((byte_addr >> 12) << 11) |
				                      ((((byte_addr >> 10) ^ (byte_addr >> 11)) & 1) << 10) |
				                      (byte_addr & 0x3ff);
				const bool lane = wide ? (((col & 1) != 0) != page2) : page2;
				top.probe_addr = word;
				top.eval();
				const unsigned value = lane ? (top.probe_word >> 8) : (top.probe_word & 0xff);
				const char ch = static_cast<char>(value & 0x7f);
				text.push_back((ch >= 0x20 && ch < 0x7f) ? ch : '.');
			}
			while (!text.empty() && text.back() == ' ') text.pop_back();
			rows.push_back(text);
		}
		return rows;
	};
	// One byte of the system bank, through the sister-byte word layout.
	auto read_system_byte = [&](unsigned offset) {
		const unsigned byte_addr = 0x38000 + offset;
		top.probe_addr = ((byte_addr >> 12) << 11) | ((((byte_addr >> 10) ^ (byte_addr >> 11)) & 1) << 10) |
		                 (byte_addr & 0x3ff);
		top.eval();
		return ((byte_addr >> 11) & 1) ? (top.probe_word >> 8) & 0xff : top.probe_word & 0xff;
	};
	auto dump_screen = [&](const char *label) {
		std::printf("screen (%s) vm=%X:\n", label, top.video_mode);
		const std::vector<std::string> rows = read_screen();
		for (unsigned row = 0; row < rows.size(); ++row)
			if (!rows[row].empty()) std::printf("%2u|%s\n", row, rows[row].c_str());
	};

	const unsigned long long half_cycles = argc > 1
		? std::strtoull(argv[1], nullptr, 0) : 30000000ULL;
	for (unsigned long long half_cycle = 0; half_cycle < half_cycles; ++half_cycle) {
		if (!top.clk) {
			// Inputs change on the low phase so the next rising edge samples them.
			const unsigned long long clock_cycles = half_cycle / 2;
			if (!keys.empty() && !keys_armed && clock_cycles > 0 && clock_cycles % (second / 4) == 0) {
				for (const std::string &row : read_screen()) {
					if (row.find(keys_after) == std::string::npos) continue;
					keys_armed = true;
					double at = static_cast<double>(clock_cycles) / second + 1.0;
					std::size_t pos = 0;
					while (pos <= keys.size()) {
						std::size_t comma = keys.find(',', pos);
						std::string k = keys.substr(pos, comma == std::string::npos ? std::string::npos : comma - pos);
						pos = comma == std::string::npos ? keys.size() + 1 : comma + 1;
						if (k.rfind("wait", 0) == 0) { at += std::strtod(k.c_str() + 4, nullptr); continue; }
						if (k.rfind("dump", 0) == 0) { dump_script.push_back({static_cast<unsigned long long>(at * second), "scripted"}); continue; }
						if (k.rfind("text:", 0) == 0) {
							// PS/2 set 2 make codes for a-z, 0-9, '.', '/' and '-'.
							static const char *chars = "abcdefghijklmnopqrstuvwxyz0123456789./-";
							static const uint8_t codes[] = {0x1c,0x32,0x21,0x23,0x24,0x2b,0x34,0x33,0x43,0x3b,0x42,0x4b,0x3a,
								0x31,0x44,0x4d,0x15,0x2d,0x1b,0x2c,0x3c,0x2a,0x1d,0x22,0x35,0x1a,
								0x45,0x16,0x1e,0x26,0x25,0x2e,0x36,0x3d,0x3e,0x46,0x49,0x4a,0x4e};
							for (char ch : k.substr(5)) {
								const char *hit = std::strchr(chars, ch);
								if (hit) { tap(at, codes[hit - chars], false); at += 0.35; }
							}
							continue;
						}
						uint8_t code = 0; bool ext = false;
						if (k == "enter") code = 0x5a; else if (k == "esc") code = 0x76;
						else if (k == "down") { code = 0x72; ext = true; } else if (k == "up") { code = 0x75; ext = true; }
						else if (k == "left") { code = 0x6b; ext = true; } else if (k == "right") { code = 0x74; ext = true; }
						else if (k == "del") { code = 0x71; ext = true; } else if (k == "bs") code = 0x66;
						else if (k == "space") code = 0x29;
						if (code) { tap(at, code, ext); at += 0.6; }
					}
					std::printf("key script armed at %.2f s\n", static_cast<double>(clock_cycles) / second);
					break;
				}
			}
			if (to_menu && clock_cycles > 0 && clock_cycles % (second / 4) == 0) {
				for (const std::string &row : read_screen())
					if (row.find(expect) != std::string::npos) reached_menu = true;
			}
			if (key_test && !script_armed && clock_cycles > 0 &&
			    clock_cycles % (second / 4) == 0) {
				for (const std::string &row : read_screen()) {
					if (row.find("Device handling") != std::string::npos) {
						script_armed = true;
						schedule_script(clock_cycles + second);
						std::printf("menu detected at %.2f s\n",
						            static_cast<double>(clock_cycles) / second);
						break;
					}
				}
			}
			if (key_index < key_script.size() &&
			    clock_cycles >= key_script[key_index].cycle) {
				const KeyEvent &event = key_script[key_index++];
				key_toggle = !key_toggle;
				top.ps2_key = (key_toggle ? 0x400 : 0) | (event.pressed ? 0x200 : 0) |
				              (event.ext ? 0x100 : 0) | event.code;
			}
			if (dump_index < dump_script.size() &&
			    clock_cycles >= dump_script[dump_index].cycle)
				dump_screen(dump_script[dump_index++].label);
		}
		prepare_storage();
		top.clk ^= 1;
		top.eval();
		finish_storage();
		if (top.clk && top.cpu_enable) {
			++enable_count;
			if (script_armed && keyboard_trace_count < 120 && top.cpu_rwn &&
			    (top.cpu_addr == 0xc000 || top.cpu_addr == 0xc008 ||
			     top.cpu_addr == 0xc010)) {
				std::printf("kbd read t=%.3f pc=%04X addr=%04X data=%02X\n",
				            static_cast<double>(half_cycle / 2) / second, top.pc,
				            top.cpu_addr, top.cpu_din);
				++keyboard_trace_count;
			}
			// A --keys script instead traces only the strobed encoder bytes the
			// guest reads, which is what distinguishes one key code from another.
			else if (keys_armed && keyboard_trace_count < 120 && top.cpu_rwn &&
			         top.cpu_addr == 0xc000 && (top.cpu_din & 0x80)) {
				std::printf("key byte t=%.3f data=%02X\n",
				            static_cast<double>(half_cycle / 2) / second, top.cpu_din);
				++keyboard_trace_count;
			}
			// --disk-trace: seeks, ROM address-field reads (stock ROM addresses), head
			// movement and cache validity on tracks 8-17, where SOS reads its key.
			if (disk_trace && (trace_all || (top.track1 >= 8 && top.track1 <= 17))) {
				static unsigned last_write = 9;
				if (top.write_mode1 != last_write) {
					std::printf("tl %10.2f ms  write mode %s (q=%u, track byte %u)\n", static_cast<double>(half_cycle / 2) / 14318.181,
					            top.write_mode1 ? "ON" : "off", top.qtrack1, top.track1_addr);
					last_write = top.write_mode1;
				}
				static unsigned last_q = 999, last_valid = 9;
				const double ms = static_cast<double>(half_cycle / 2) / 14318.181;
				if (top.qtrack1 != last_q) { std::printf("tl %10.2f ms  head q=%u\n", ms, top.qtrack1); last_q = top.qtrack1; }
				if (top.valid1 != last_valid) { std::printf("tl %10.2f ms  flux %s  (track byte %u)\n", ms, top.valid1 ? "ON" : "off", top.track1_addr); last_valid = top.valid1; }
				static unsigned last_byte = 0;
				if (top.track1_addr != last_byte && top.track1_addr != last_byte + 1 &&
				    !(top.track1_addr == 0 && last_byte >= 6280))
					std::printf("tl %10.2f ms  POSITION JUMP track byte %u -> %u (flux %s)\n", ms, last_byte, top.track1_addr, top.valid1 ? "ON" : "off");
				last_byte = top.track1_addr;
				if (top.cpu_sync && top.cpu_addr == 0xF400) std::printf("tl %10.2f ms  SEEK to halftrack %u\n", ms, top.a);
				if (top.cpu_sync && top.cpu_addr == 0xF1B9) std::printf("tl %10.2f ms  RDADR start\n", ms);
				if (top.cpu_sync && top.cpu_addr == 0xF1B7) std::printf("tl %10.2f ms  RDADR ERROR\n", ms);
				if (top.cpu_sync && top.cpu_addr == 0xF214) std::printf("tl %10.2f ms  RDADR ok  trk=%u sec=%u vol=%02X\n", ms,
				    zero_page_values[0x99], zero_page_values[0x98], zero_page_values[0x9a]);
			}
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
		if (reached_menu) break;
		// The SOS milestone addresses mean nothing to a scripted non-SOS disk.
		if (keys.empty() && (reached_system_failure || (reached_interpreter && !key_test && !to_menu) ||
		    loader_io_error || boot_block_error || disk_hard_error)) break;
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
	if (to_menu) {
		std::printf("to-menu: menu=%u sysfail=%u code=%02X\n", reached_menu,
		            reached_system_failure, system_failure_code);
		dump_screen("final");
	}
	for (unsigned code : font_dump) {
		std::printf("glyph $%02X:\n", code);
		for (unsigned row = 0; row < 8; ++row) {
			top.probe_font_addr = code * 8 + row;
			top.eval();
			std::printf("  row %u  %02X  ", row, top.probe_font);
			for (unsigned dot = 0; dot < 7; ++dot) std::putchar((top.probe_font >> dot) & 1 ? '#' : '.');
			std::putchar('\n');
		}
	}
	unsigned font_mismatches = 0;
	if (check_font) {
		for (unsigned entry = 0; entry < 1024; ++entry) {
			top.probe_font_addr = entry;
			top.eval();
			const unsigned loaded = top.probe_font;
			const unsigned expected = read_system_byte(0xc00 + entry);
			if (loaded != expected && ++font_mismatches <= 8)
				std::printf("font $%02X row %u: character RAM %02X, $0C00 set %02X\n", entry >> 3, entry & 7,
				            loaded, expected);
		}
		std::printf("font: %u of 1024 character RAM bytes differ from the set at $0C00\n", font_mismatches);
	}
	if (disk_test)
		std::printf("disk image=%s buffered=%u sd_reads=%u bootstrap_A000=%u boot_block_error=%u ext_fetch_ok=%u loader_return=%u "
		            "loader_jump=%u interpreter=%u final_track=%u loader_io_error=%04X "
		            "sysfail=%u code=%02X\n",
		            argv[2], 1u, sd_block_reads, reached_disk_bootstrap,
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
	if (key_test && (!script_armed || dump_index < dump_script.size())) {
		std::fprintf(stderr, "FAIL: keyboard script did not complete (%zu/%zu dumps)\n",
		             dump_index, dump_script.size());
		return 1;
	}
	if (to_menu && !reached_menu && !reached_system_failure) {
		std::fprintf(stderr, "FAIL: \"%s\" did not appear on screen\n", expect.c_str());
		return 1;
	}
	if (check_font && font_mismatches) {
		std::fprintf(stderr, "FAIL: the character generator does not hold the SOS character set\n");
		return 1;
	}
	if (disk_test && reached_system_failure) {
		std::fprintf(stderr, "FAIL: SOS entered SYSDEATH with code $%02X\n",
		             system_failure_code);
		return 1;
	}
	return 0;
}
