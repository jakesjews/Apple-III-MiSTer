// Simulation model of the MiSTer hps_io block-device (SD) interface used by floppy_track.
// One instance per virtual drive.  Call step() once per rising clk edge with the
// core's request signals; it drives sd_ack / sd_buff_* like hps_io does.
#pragma once
#include <cstdio>
#include <cstdint>
#include <vector>
#include <string>

struct SdSim {
    std::vector<uint8_t> img;
    bool mounted = false;
    bool readonly = false;
    std::string path;
    // state machine
    int state = 0;      // 0 idle, 1 read transfer, 2 write transfer, 3 finishing
    int idx = 0;
    int wait = 0;
    uint32_t lba = 0;
    bool dirty = false;

    bool load(const std::string& p, bool ro = false) {
        path = p; FILE* f = fopen(p.c_str(), "rb"); if (!f) return false;
        fseek(f, 0, SEEK_END); long n = ftell(f); fseek(f, 0, SEEK_SET);
        img.resize(n); fread(img.data(), 1, n, f); fclose(f); mounted = true; readonly = ro; return true;
    }
    void save() { if (!dirty || readonly || path.empty()) return; FILE* f = fopen(path.c_str(), "wb"); if (f) { fwrite(img.data(), 1, img.size(), f); fclose(f);} dirty = false; }

    // Inputs from core: rd, wr, lba, buff_din (byte from core for writes)
    // Outputs to core: ack, buff_addr, buff_dout, buff_wr
    void step(bool rd, bool wr, uint32_t req_lba, uint8_t buff_din,
              bool& ack, uint16_t& buff_addr, uint8_t& buff_dout, bool& buff_wr) {
        buff_wr = false;
        switch (state) {
        case 0:
            ack = false; buff_addr = 0; buff_dout = 0;
            if ((rd || wr) && mounted) { lba = req_lba; state = rd ? 1 : 2; idx = 0; wait = 8; ack = true; }
            break;
        case 1: // read: present bytes with buff_wr pulses
            ack = true;
            if (wait) { wait--; break; }
            if (idx < 512) {
                size_t off = (size_t)lba * 512 + idx;
                buff_addr = idx; buff_dout = off < img.size() ? img[off] : 0; buff_wr = true; idx++; wait = 1;
            } else { state = 3; wait = 8; }
            break;
        case 2: // write: core presents buff_din for buff_addr; we sample one clock after address set
            ack = true;
            if (wait) { wait--; break; }
            if (idx > 0 && idx <= 512) { size_t off = (size_t)lba * 512 + (idx - 1); if (off < img.size()) { if (img[off] != buff_din) dirty = true; img[off] = buff_din; } }
            if (idx < 512) { buff_addr = idx; idx++; wait = 1; }
            else { state = 3; wait = 8; }
            break;
        case 3:
            if (wait) { wait--; ack = true; break; }
            ack = false; state = 0; buff_addr = 0;
            break;
        }
    }
};
