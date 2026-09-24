// Runs sim/joystick/adc.s on the whole machine.  Each batch reads the joystick
// with shipped software's methods; this harness sets a new joystick position
// between batches and checks what every method returned.
#include "Vcore_tb.h"
#include "verilated.h"
#include <algorithm>
#include <cstdio>
#include <cstdint>
#include <cstdlib>
#include <utility>

namespace {

constexpr unsigned kSeq = 0x0300, kSos = 0x0301, kSosScreen = 0x0305, kSos1MHz = 0x0306;
constexpr unsigned kPread = 0x0307, kAtomic = 0x0309, kSwitches = 0x030a, kFlags = 0x030b;
constexpr unsigned kSelfTest = 0x0310, kFixed = 0x0311, kRaw = 0x0320;

struct Stick {
	unsigned bx, by, ax, ay;
	bool a_button, a_switch, b_button, b_switch;
};

// Batch n: port B X sweeps every position, the other axes follow other
// sequences, and the four switches count in binary.
Stick stick(unsigned n) {
	return {n & 255, 255 - (n & 255), (n * 97 + 13) & 255, (n * 53 + 200) & 255,
		(n & 1) != 0, (n & 2) != 0, (n & 4) != 0, (n & 8) != 0};
}

// Logical $0000-$1FFF is the system bank; RAM holds sister bytes in one word.
std::pair<unsigned, unsigned> probe_of(unsigned logical) {
	const unsigned b = 0x38000 + logical;
	return {((b >> 12) << 11) | ((((b >> 10) ^ (b >> 11)) & 1) << 10) | (b & 0x3ff), (b >> 11) & 1};
}

// The ramp for position p lasts 354 + 8p D VIA ticks.  Atomic Defense samples
// $C066 17 cycles apart from 173 cycles after the start, one tick per cycle.
int atomic_expect(unsigned p) {
	const int ramp = 354 + 8 * int(p);
	const int k = (ramp - 173 + 16) / 17 + 1;
	return std::min(k, 128);
}

}  // namespace

int main(int argc, char **argv) {
	Verilated::commandArgs(argc, argv);
	Vcore_tb top;
	const unsigned batches = argc > 1 ? std::strtoul(argv[1], nullptr, 0) : 256;
	top.clk = 0;
	top.reset = 1;
	top.serial_rx = 1;
	top.serial_cts_n = 0;
	top.serial_dsr_n = 0;
	top.serial_dcd_n = 0;
	top.image_change = 0;
	top.image_size = 0;
	top.image_readonly = 1;
	top.ps2_key = 0;
	top.plus_keymap = 0;
	top.ram_128k = 0;
	top.probe_font_addr = 0;
	auto apply = [&](const Stick &s) {
		top.joy_b_x = s.bx;
		top.joy_b_y = s.by;
		top.joy_a_x = s.ax;
		top.joy_a_y = s.ay;
		top.joy_a_button = s.a_button;
		top.joy_a_switch = s.a_switch;
		top.joy_b_button = s.b_button;
		top.joy_b_switch = s.b_switch;
	};
	auto read_byte = [&](unsigned logical) {
		const auto [word, lane] = probe_of(logical);
		top.probe_addr = word;
		top.eval();
		return lane ? (top.probe_word >> 8) & 0xffu : top.probe_word & 0xffu;
	};
	auto tick = [&]() {
		top.clk = 0;
		top.eval();
		top.clk = 1;
		top.eval();
	};

	apply(stick(0));
	for (int i = 0; i < 128; ++i) tick();
	top.reset = 0;

	unsigned failures = 0;
	auto check = [&](bool ok, const char *what, unsigned n, int got, int want) {
		if (ok) return;
		if (++failures <= 40) std::printf("FAIL batch %3u %s: got %d, expected %d\n", n, what, got, want);
	};
	int worst_screen = 0, worst_slow = 0, worst_pread = 0, worst_atomic = 0;
	// Where each GET_ANALOG ramp ended inside SOS's rounding window: it returns
	// (ticks - 357) / 8, so a reading of p means 0-7 ticks past 357 + 8p.
	static const char *const window_names[] = {"2 MHz", "2 MHz screen on", "1 MHz"};
	int window_min[3] = {99, 99, 99}, window_max[3] = {-99, -99, -99};
	int window_count[3][32] = {};
	const auto [seq_word, seq_lane] = probe_of(kSeq);
	top.probe_addr = seq_word;
	unsigned done = 0;
	const unsigned long long limit = 14318181ULL * (2 + batches / 20);
	for (unsigned long long cycle = 0; cycle < limit && done < batches; ++cycle) {
		tick();
		const unsigned seq = seq_lane ? (top.probe_word >> 8) & 0xffu : top.probe_word & 0xffu;
		if (seq != ((done + 1) & 0xff)) continue;
		const unsigned n = done;
		const Stick s = stick(n);
		if (n == 0) {
			const unsigned count = read_byte(kSelfTest);
			std::printf("boot ROM self-test: ground counted %u (the ROM fails 32 or more)\n", count);
			check(count > 0 && count < 32, "self-test count", n, count, 16);
			static const char *const names[] = {"ground", "reference", "clock battery", "no connection"};
			static const int want[] = {0, 255, 255, 255};
			for (int i = 0; i < 4; ++i) {
				const int got = read_byte(kFixed + i);
				std::printf("GET_ANALOG %-13s %3d\n", names[i], got);
				check(got == want[i], names[i], n, got, want[i]);
			}
		}
		const int want_axis[4] = {int(s.bx), int(s.by), int(s.ax), int(s.ay)};
		static const char *const axes[] = {"GET_ANALOG port B X", "GET_ANALOG port B Y", "GET_ANALOG port A X",
			"GET_ANALOG port A Y"};
		for (int i = 0; i < 4; ++i) {
			const int got = read_byte(kSos + i);
			check(got == want_axis[i], axes[i], n, got, want_axis[i]);
		}
		const int screen = read_byte(kSosScreen), slow = read_byte(kSos1MHz);
		check(screen == int(s.bx), "GET_ANALOG screen on", n, screen, s.bx);
		// SOS always reads at 2 MHz.  At 1 MHz ANALOG's 11-cycle loop adds up to 11 ticks.
		check(slow >= int(s.bx) && slow <= int(s.bx) + 2, "GET_ANALOG at 1 MHz", n, slow, s.bx);
		worst_screen = std::max(worst_screen, std::abs(screen - int(s.bx)));
		worst_slow = std::max(worst_slow, std::abs(slow - int(s.bx)));
		for (int i = 0; i < 2; ++i) {
			const int want = i ? int(s.by) : int(s.bx), got = read_byte(kPread + i);
			check(got <= want && got >= want - 3, i ? "PREAD port B Y" : "PREAD port B X", n, got, want);
			worst_pread = std::max(worst_pread, want - got);
		}
		for (int i = 0; i < 6; ++i) {
			const int timer = int(read_byte(kRaw + 2 * i) | read_byte(kRaw + 2 * i + 1) << 8);
			const int ticks = 360 - int(int16_t(timer));
			const int axis = i < 4 ? want_axis[i] : int(s.bx);
			if (axis == 0 || axis == 255) continue;  // clamped by SOS
			const int group = i < 4 ? 0 : i - 3;
			window_min[group] = std::min(window_min[group], ticks - 357 - 8 * axis);
			window_max[group] = std::max(window_max[group], ticks - 357 - 8 * axis);
			const int bin = ticks - 357 - 8 * axis + 8;
			if (bin >= 0 && bin < 32) ++window_count[group][bin];
		}
		const int atomic = read_byte(kAtomic), atomic_want = atomic_expect(s.bx);
		check(std::abs(atomic - atomic_want) <= 1, "Atomic Defense count", n, atomic, atomic_want);
		worst_atomic = std::max(worst_atomic, std::abs(atomic - atomic_want));
		const int switches = read_byte(kSwitches);
		const int want_switches = s.b_switch | s.a_button << 1 | s.b_button << 2 | s.a_switch << 3;
		check(switches == want_switches, "switches $C060-$C063", n, switches, want_switches);
		// The D VIA's CA2 and CB1 flag falling edges of port A's button and switch.
		const Stick previous = stick(n ? n - 1 : 0);
		const int flags = read_byte(kFlags);
		const int want_flags = (previous.a_button && !s.a_button) | (previous.a_switch && !s.a_switch) << 4;
		check(flags == want_flags, "D VIA CA2/CB1 flags", n, flags, want_flags);
		if (n % 32 == 0 || n == 255)
			std::printf("position %3u: GET_ANALOG %3d (screen on %3d, 1 MHz %3d)  PREAD %3d  Atomic Defense %3d\n",
				s.bx, read_byte(kSos), screen, slow, read_byte(kPread), atomic);
		++done;
		apply(stick(done));
		top.probe_addr = seq_word;
		top.eval();
	}
	if (done < batches) {
		std::printf("FAIL only %u of %u batches finished (pc=%04X)\n", done, batches, top.pc);
		return 1;
	}
	for (int group = 0; group < 3; ++group) {
		std::printf("GET_ANALOG %-15s ramp ends %d to %d ticks into the step (0 to 7 reads correctly)\n",
			window_names[group], window_min[group], window_max[group]);
		if (std::getenv("JOY_HISTOGRAM")) {
			for (int bin = 0; bin < 32; ++bin)
				if (window_count[group][bin]) std::printf("  %3d: %d\n", bin - 8, window_count[group][bin]);
		}
	}
	std::printf("largest differences from the position: screen on %d, 1 MHz %d, PREAD %d below; "
				"Atomic Defense %d from its loop's count\n",
		worst_screen, worst_slow, worst_pread, worst_atomic);
	if (failures) {
		std::printf("FAIL joystick methods: %u checks\n", failures);
		return 1;
	}
	std::printf("PASS joystick methods over %u positions\n", batches);
	return 0;
}
