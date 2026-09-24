#include "Vcore_tb.h"
#include "verilated.h"
#include <cstdio>
#include <fstream>
#include <iterator>
#include <vector>

int main(int argc, char **argv) {
    Verilated::commandArgs(argc, argv);
    Vcore_tb top;
    top.clk=0; top.reset=1; top.serial_rx=1;
    top.serial_cts_n=0; top.serial_dsr_n=0; top.serial_dcd_n=0;
    top.image_change=0; top.image_size=0; top.image_readonly=1;
    top.ps2_key=0; top.probe_addr=(7<<14)|2;
    std::ifstream romfile("sim/serial/obj_dir/echo.rom",std::ios::binary);
    std::vector<unsigned char> rom((std::istreambuf_iterator<char>(romfile)),{});
    if(rom.size()!=4096) return 2;
    const unsigned irq_pc=rom[4094]|(rom[4095]<<8);
    const double bit_period=14318182.0/19200.0;
    const unsigned start_cycle=20000;
    const unsigned stall_start=2300000;
    const unsigned stall_end=2900000;
    unsigned irq_count=0, tx_index=0;
    int tx_bit=-1;
    double next_sample=0;
    unsigned char tx_byte=0;
    bool last_tx=true;
    std::vector<unsigned char> received;
    for(unsigned cycle=0;cycle<4000000;cycle++) {
        top.reset=cycle<128;
        if(cycle>=start_cycle) {
            // 256 bytes, all values; 11 bit cells/frame leave one idle bit.
            unsigned cell=unsigned((cycle-start_cycle)/bit_period);
            unsigned frame=cell/11, bit=cell%11;
            top.serial_rx=frame>=256 || bit>=9 ? 1 : bit==0 ? 0 : (frame>>(bit-1))&1;
        }
        top.serial_cts_n=cycle>=stall_start && cycle<stall_end;
        if(cycle>=stall_start) {
            // Buffer another 64 back-to-back bytes while CTS prevents TX.
            unsigned cell=unsigned((cycle-stall_start)/bit_period);
            unsigned frame=cell/10, bit=cell%10;
            top.serial_rx=frame>=64 || bit==9 ? 1 : bit==0 ? 0 : (frame>>(bit-1))&1;
        }
        top.clk=0;top.eval();top.clk=1;top.eval();
        if(top.serial_cts_n && !top.serial_tx) {
            std::fprintf(stderr,"FAIL TX while CTS deasserted\n");return 1;
        }
        if(top.cpu_enable && top.cpu_sync && top.cpu_addr==irq_pc) ++irq_count;
        if(tx_bit<0 && last_tx && !top.serial_tx) {
            tx_bit=0; next_sample=cycle+bit_period*1.5; tx_byte=0;
        }
        if(tx_bit>=0 && cycle>=next_sample) {
            if(tx_bit<8) {
                tx_byte|=top.serial_tx<<tx_bit;
                ++tx_bit;next_sample+=bit_period;
            } else {
                if(!top.serial_tx) {std::fprintf(stderr,"FAIL framing at byte %u\n",tx_index);return 1;}
                if(tx_byte!=(tx_index&255)) {std::fprintf(stderr,"FAIL echo byte %u got %02X PC=%04X\n",tx_index,tx_byte,top.pc);return 1;}
                received.push_back(tx_byte); ++tx_index; tx_bit=-1;
                if(received.size()==320) break;
            }
        }
        last_tx=top.serial_tx;
    }
    if(received.size()!=320 || irq_count<320 || (top.probe_word&255)!=0) {
        std::fprintf(stderr,"FAIL echo count=%zu IRQs=%u errors=%02X PC=%04X env=%02X zp=%02X\n",received.size(),irq_count,top.probe_word&255,top.pc,top.environment,top.zero_page);return 1;
    }
    std::printf("PASS real T65 IRQ-driven serial echo: 256/256 byte values plus 64 queued across CTS stall, %u IRQ entries, zero receive errors\n",irq_count);
    return 0;
}
