#include "Vcore_tb.h"
#include "verilated.h"
#include <array>
#include <cstdlib>
#include <cstdio>

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	Vcore_tb top;
	top.clk = 0;
	top.reset = 1;
	for (int i = 0; i < 128; ++i) {
		top.clk ^= 1;
		top.eval();
	}
	top.reset = 0;

	std::array<unsigned, 16> first_pcs{};
	unsigned sync_count = 0;
	unsigned enable_count = 0;
	unsigned last_pc = 0;
	bool reached_bank_loop_exit = false;
	bool reached_reconfigure = false;
	bool reached_disk_boot = false;
	unsigned bank_changes = 0;
	unsigned previous_bank_output = top.e_pa_o;
	const unsigned long long half_cycles = argc > 1
		? std::strtoull(argv[1], nullptr, 0) : 30000000ULL;
	for (unsigned long long half_cycle = 0; half_cycle < half_cycles; ++half_cycle) {
		top.clk ^= 1;
		top.eval();
		if (top.clk && top.cpu_enable) {
			++enable_count;
			if (top.e_pa_o != previous_bank_output) {
				previous_bank_output = top.e_pa_o;
				++bank_changes;
			}
			if (top.cpu_sync) {
				if (sync_count < first_pcs.size()) first_pcs[sync_count] = top.cpu_addr;
				last_pc = top.cpu_addr;
				if (top.cpu_addr == 0xF575) reached_bank_loop_exit = true;
				if (top.cpu_addr == 0xF686) reached_reconfigure = true;
				if (top.cpu_addr == 0xF697) reached_disk_boot = true;
				++sync_count;
			}
		}
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

	if (sync_count < 100) {
		std::fprintf(stderr, "FAIL: boot ROM did not execute enough instructions\n");
		return 1;
	}
	if (first_pcs[0] != 0xF4EE) {
		std::fprintf(stderr, "FAIL: reset vector started at %04X, expected F4EE\n", first_pcs[0]);
		return 1;
	}
	if (!reached_bank_loop_exit || bank_changes < 4) {
		std::fprintf(stderr, "FAIL: ROM did not discover the 512 KiB RAM banks\n");
		return 1;
	}
	if (!reached_reconfigure || !reached_disk_boot) {
		std::fprintf(stderr, "FAIL: ROM did not pass diagnostics and enter disk boot\n");
		return 1;
	}
	return 0;
}
