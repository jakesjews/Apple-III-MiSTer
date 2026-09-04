#include "Vtb.h"
#include "verilated.h"
#include <cstdio>
int main(int argc, char** argv){ Verilated::commandArgs(argc, argv); Vtb* t=new Vtb; t->clk=0; t->rst_n=0;
 for(int i=0;i<20;i++){ t->clk^=1; t->eval(); } t->rst_n=1; int syncs=0; unsigned lastpc=0;
 for(int i=0;i<12000;i++){ t->clk^=1; t->eval(); if(t->clk && t->sync_o) {syncs++; lastpc=t->pc_out;} }
 printf("syncs=%d lastpc=%04X m10=%02X m11=%02X m12=%02X m13=%02X\n", syncs, lastpc, t->m10, t->m11, t->m12, t->m13); delete t; return 0; }
