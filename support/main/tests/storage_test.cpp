#include "file_io.h"
#include "user_io.h"
#include "support/a2/iigs_fmt.h"
#include "support/a2/iigs_disk.h"
#include "support/apple3/apple3_woz.h"
#include "support/apple3/apple3_disk.h"
#include <cassert>
#include <cstring>
#include <string>
#include <vector>
#include <fstream>
#include <algorithm>

static std::string core = "Apple-III";
static bool can_write = true;
static std::vector<uint8_t> to_fpga, from_fpga;
static unsigned command;
static std::string message;
fileTYPE::fileTYPE() : filp(nullptr), mode(0), type(1), zip(nullptr), size(0), offset(0) {}
fileTYPE::~fileTYPE() { if (filp) fclose(filp); }
int fileTYPE::opened() { return filp || zip; }
char *user_io_get_core_name(int) { return &core[0]; }
char user_io_a2_woz_enabled() { return 1; }
int user_io_get_width() { return 0; }
int FileCanWrite(const char *) { return can_write; }
int FileClose(fileTYPE *f) { if (f->filp) fclose(f->filp); f->filp = nullptr; return 1; }
int FileSeek(fileTYPE *f, __off64_t off, int whence) { if (fseeko(f->filp, off, whence)) return 0; f->offset = ftello(f->filp); return 1; }
int FileReadAdv(fileTYPE *f, void *buf, int len, int) { return fread(buf, 1, len, f->filp); }
int FileWriteAdv(fileTYPE *f, void *buf, int len, int) { int n = fwrite(buf, 1, len, f->filp); fflush(f->filp); return n; }
void InfoMessage(const char *msg, int, const char *) { message = msg; }
void EnableIO() {}
void DisableIO() {}
uint16_t fpga_spi(uint16_t v) { command = v; return 0; }
void spi_block_write(const uint8_t *p, int, int n) { to_fpga.assign(p, p+n); }
void spi_block_read(uint8_t *p, int, int n) { assert(from_fpga.size() == unsigned(n)); memcpy(p, from_fpga.data(), n); }
static void put32(uint8_t *p, uint32_t v) { for(int i=0;i<4;i++) p[i]=v>>(i*8); }
static uint32_t get32(const uint8_t *p) { return p[0] | p[1]<<8 | p[2]<<16 | uint32_t(p[3])<<24; }
// Whole-file WOZ check for images the code builds or rewrites: signature, CRC when
// set, chunk bounds and every track allocation. Main itself reads only what it needs.
static bool valid_woz(const std::vector<uint8_t> &w) {
  const uint8_t *b=w.data(); size_t size=w.size();
  if(size<12 || memcmp(b,"WOZ",3) || (b[3]!='1' && b[3]!='2') || memcmp(b+4,"\xff\x0a\x0d\x0a",4)) return false;
  if(get32(b+8) && get32(b+8)!=woz_crc32(b+12,size-12)) return false;
  const uint8_t *inf=nullptr, *map=nullptr, *tracks=nullptr; size_t track_size=0; bool flux=false;
  for(size_t pos=12;pos<size;) {
    if(size-pos<8) return false;
    uint32_t n=get32(b+pos+4); if(n>size-pos-8) return false;
    const uint8_t *data=b+pos+8;
    if(!memcmp(b+pos,"INFO",4)) { if(inf || n!=60) return false; inf=data; }
    if(!memcmp(b+pos,"TMAP",4)) { if(map || n!=160) return false; map=data; }
    if(!memcmp(b+pos,"TRKS",4)) { if(tracks) return false; tracks=data; track_size=n; }
    if(!memcmp(b+pos,"FLUX",4)) flux=true;
    pos+=8+n;
  }
  if(!inf || !map || !tracks) return false;
  const bool v1=b[3]=='1';
  if((!v1 && track_size<1280) || (v1 && track_size%6656)) return false;
  for(int i=0;i<160;i++) {
    if(map[i]!=255 && (map[i]>=160 || (v1 && size_t(map[i])>=track_size/6656))) return false;
    if(v1) continue;
    const uint8_t *e=tracks+i*8; uint32_t block=e[0]|e[1]<<8, count=e[2]|e[3]<<8, bits=get32(e+4);
    if(!count) { if(bits || block) return false; continue; }
    uint64_t begin=uint64_t(block)*512, end=begin+uint64_t(count)*512;
    if(begin<size_t(tracks-b)+1280 || end>size || end>size_t(tracks-b)+track_size || !bits || (!flux && bits>count*4096)) return false;
  }
  if(v1) for(size_t pos=0;pos<track_size;pos+=6656) {
    uint32_t n=tracks[pos+6646]|tracks[pos+6647]<<8, bits=tracks[pos+6648]|tracks[pos+6649]<<8;
    if(n>6646 || bits>n*8 || !bits) return false;
  }
  return true;
}
static std::vector<uint8_t> bytes(fileTYPE &f) {
  fseeko(f.filp,0,SEEK_END); size_t n=ftello(f.filp); rewind(f.filp);
  std::vector<uint8_t> b(n); assert(fread(b.data(),1,n,f.filp)==n); return b;
}
static void source(fileTYPE &f, const std::vector<uint8_t> &b) {
  if(f.filp) fclose(f.filp); f.filp=tmpfile(); assert(f.filp);
  assert(fwrite(b.data(),1,b.size(),f.filp)==b.size()); fflush(f.filp);
  f.size=b.size(); f.zip=nullptr; rewind(f.filp);
}
static int ack(int slot) { return 0x100*(slot+1); }
static bool mount(int slot, const char *name, fileTYPE &f, int &writable) { return apple3_mount_hook(slot,name,&f,&writable)==1; }
static void write(int slot, fileTYPE &f, uint64_t lba, int sz=512) { assert(apple3_sd_service(slot,&f,2,lba,sz,ack(slot))==1); }
static std::vector<uint8_t> serve(int slot, fileTYPE &f) {
  std::vector<uint8_t> result;
  for(uint64_t lba=0;lba*512<uint64_t(f.size);lba+=32) {
    assert(apple3_sd_service(slot,&f,1,lba,16384,ack(slot))==1);
    assert(to_fpga.size()==16384); assert(command==unsigned(UIO_SECTOR_RD|ack(slot)));
    result.insert(result.end(),to_fpga.begin(),to_fpga.end());
  }
  result.resize(f.size); return result;
}
static std::vector<uint8_t> mount_serve(fileTYPE &f, const std::vector<uint8_t> &b, const char *name, int slot=0, bool rw=false) {
  source(f,b); int writable=!rw; assert(mount(slot,name,f,writable));
  assert(!!writable==rw); return serve(slot,f);
}
// Every track of an Apple III WOZ decodes completely into a DOS-order image.
static bool decode_all(const std::vector<uint8_t> &woz, std::vector<uint8_t> &dsk) {
  for(int t=0;t<35;t++) if(apple3_verify_track(woz.data(),woz.size(),t,dsk.data()+t*4096,nullptr)!=0xffff) return false;
  return true;
}
// The nibbles of track t over two revolutions, each with the bit index of its last bit.
static std::vector<std::pair<uint8_t,unsigned>> nibbles(const std::vector<uint8_t> &woz, int t) {
  unsigned start=(woz[256+t*8]|woz[257+t*8]<<8)*512, bits=get32(&woz[260+t*8]);
  std::vector<std::pair<uint8_t,unsigned>> out; uint8_t shift=0;
  for(unsigned i=0;i<2*bits;i++) {
    unsigned pos=i%bits; shift=shift<<1|(woz[start+pos/8]>>(7-pos%8)&1);
    if(shift&0x80) { out.push_back({shift,pos}); shift=0; }
  }
  return out;
}
// Flip the low bit of the nibble `after` positions past sector s's address prologue on track t.
// Address field: D5 AA 96 (0-2) vol trk sec chk (3-10) DE AA EB, 7 sync, D5 AA AD (21-23), data (24+).
static void flip(std::vector<uint8_t> &woz, int t, int s, int after) {
  auto n=nibbles(woz,t); unsigned start=(woz[256+t*8]|woz[257+t*8]<<8)*512;
  for(size_t i=0;i+after<n.size();i++)
    if(n[i].first==0xd5&&n[i+1].first==0xaa&&n[i+2].first==0x96&&n[i+7].first==((s>>1)|0xaa)&&n[i+8].first==(s|0xaa)) {
      unsigned bit=n[i+after].second; woz[start+bit/8]^=0x80>>(bit%8); return;
    }
  assert(false);
}
// The drive saves track `from` of woz over track `to` as consecutive 512-byte blocks,
// exactly as the FPGA controller does; each() inspects the source after every block.
template<class F> static void save_track(int slot, fileTYPE &f, const std::vector<uint8_t> &woz, int from, int to, F each) {
  for(int b=0;b<13;b++) {
    from_fpga.assign(woz.begin()+(3+from*13+b)*512,woz.begin()+(4+from*13+b)*512);
    write(slot,f,3+to*13+b); each();
  }
}
// Each sector slot of a source track holds its old or its new contents, never anything
// else (zeros, a torn sector or a neighbour's data). Returns how many slots are new.
static int fresh(const std::vector<uint8_t> &now, const std::vector<uint8_t> &old, const std::vector<uint8_t> &next, int track, size_t off=0) {
  int n=0;
  for(int s=0;s<16;s++) {
    size_t p=off+track*4096+s*256; bool is_new=!memcmp(&now[p],&next[p],256);
    assert(is_new || !memcmp(&now[p],&old[p],256)); n+=is_new;
  }
  return n;
}
int main(int argc,char **argv) {
  fileTYPE f;
  if(argc==4 && !strcmp(argv[1],"--convert")) {
    std::ifstream input(argv[2],std::ios::binary);
    std::vector<uint8_t> b((std::istreambuf_iterator<char>(input)),{});
    source(f,b); int writable; assert(mount(0,argv[2],f,writable));
    auto w=serve(0,f); std::ofstream out(argv[3],std::ios::binary); out.write((char*)w.data(),w.size());
    apple3_unmount(0); return !out;
  }
  std::vector<uint8_t> dsk(A2_525_IMAGE_SIZE), po(dsk.size()), back(dsk.size());
  uint32_t rng=1; for(auto &b:dsk) { rng=rng*1664525+1013904223; b=rng>>24; }
  int writable=0;
  auto w=mount_serve(f,dsk,"disk.DSK",0,true);
  assert(valid_woz(w)); assert(w[23]==1);
  assert(decode_all(w,back)); assert(back==dsk);
  // Apple /// tracks hold 51,424 cells read at 3.875 us, so the machine's own formatter
  // closes them at its nominal 22 sync nibbles; the bare 50,304 reads as a fast drive.
  assert(get32(w.data()+260)==51424 && w[20+39]==31);
  // A burst that decodes to nothing valid never reaches the source image.
  from_fpga.assign(1024,0x31); auto original=bytes(f); write(0,f,3,1024);
  assert(bytes(f)==original);
  a2_dos_to_prodos(po.data(),dsk.data()); assert(mount_serve(f,po,"disk.PO",0,true)==w);
  // ProDOS order is blocks in sequence. Block n of a track is physical sectors 2n and
  // 2n+2 (the second half of block 7 is sector 15), which a DOS-order file stores at
  // {0,7,14,6,13,5,12,4,11,3,10,2,9,1,8,15}[sector]: block 2 is DOS sectors 11 and 10.
  const int dos_pos[16]={0,7,14,6,13,5,12,4,11,3,10,2,9,1,8,15};
  for(int t=0;t<35;t++) for(int half=0;half<16;half++) {
    int sector=half<8?half*2:half*2-15;
    assert(!memcmp(&po[t*4096+half*256],&dsk[t*4096+dos_pos[sector]*256],256));
  }
  assert(!memcmp(&po[2*512],&dsk[11*256],256) && !memcmp(&po[2*512+256],&dsk[10*256],256));
  auto do_w=mount_serve(f,dsk,"disk.do",1,true); assert(do_w==w);
  std::vector<uint8_t> mg(128+dsk.size()+73); twomg_build(mg.data(),mg.size(),po.data(),po.size(),1);
  memmove(mg.data()+128,mg.data()+64,po.size()); put32(mg.data()+24,128); put32(mg.data()+16,0);
  assert(mount_serve(f,mg,"disk.2mg",0,true)==w);
  std::vector<uint8_t> nib(A2_NIB_IMAGE_SIZE); a2_dsk_to_nib(nib.data(),dsk.data());
  auto nw=mount_serve(f,nib,"disk.nib",0,true); assert(decode_all(nw,back)); assert(back==dsk);
  // NIB address volume bytes survive direct packing (never sector decode/rebuild).
  nib[51]=0xaau; nib[52]=0xab; auto modified=mount_serve(f,nib,"disk.nib",0,true); assert(modified!=nw);
  // A raw SOS volume with 12 directory entries per block is recognised in either order.
  {
    auto sos_do=dsk; uint8_t *d=&sos_do[11*256]; d[4]=0xf4; memcpy(d+5,"BOOT",4); d[0x23]=39; d[0x24]=12;
    std::vector<uint8_t> sos_po(sos_do.size()); a2_dos_to_prodos(sos_po.data(),sos_do.data());
    auto expect=mount_serve(f,sos_do,"sos.dsk",0,true);
    assert(mount_serve(f,sos_po,"sos.dsk",0,true)==expect);
    assert(mount_serve(f,sos_po,"sos.po",0,true)==expect);
  }
  puts("PASS Apple III 5.25 conversion: DOS/PO/2MG equivalence, sync bits, round-trip and NIB preservation");
  // A DOS 3.3 disk's address fields carry the volume in its VTOC (the /// Plus dealer
  // diagnostics are volume 1 and stop at VOLUME MISMATCH under 254). A 2MG header's own
  // volume wins, and an image without a VTOC, or with volume 0, keeps 254.
  {
    auto dos=dsk; uint8_t *vtoc=dos.data()+17*4096; memset(vtoc,0,256);
    vtoc[1]=17; vtoc[2]=15; vtoc[3]=3; vtoc[6]=1; vtoc[0x34]=35; vtoc[0x35]=16; vtoc[0x37]=1;
    auto all=[&](const std::vector<uint8_t> &woz,uint8_t want) {
      uint8_t got[16], sectors[4096];
      for(int t:{0,9,17,34}) {
        assert(apple3_verify_track(woz.data(),woz.size(),t,sectors,got)==0xffff);
        for(int s=0;s<16;s++) assert(got[s]==want);
      }
    };
    assert(apple3_dos33_volume(dos.data())==1 && !apple3_dos33_volume(dsk.data()));
    all(w,254); all(mount_serve(f,dos,"dos.dsk",0,true),1);
    a2_dos_to_prodos(po.data(),dos.data()); all(mount_serve(f,po,"dos.po",0,true),1);
    std::vector<uint8_t> vmg(64+dos.size()); twomg_build(vmg.data(),vmg.size(),po.data(),po.size(),1);
    put32(vmg.data()+16,0x100|77); all(mount_serve(f,vmg,"dos.2mg",0,true),77);
    vtoc[6]=0; all(mount_serve(f,dos,"dos.dsk",0,true),254);
    a2_dos_to_prodos(po.data(),dsk.data());
    puts("PASS DOS 3.3 volume: VTOC volume in the address fields, 2MG volume first, 254 otherwise");
  }
  // Apple /// NIB write-back. The drive saves a track as seventeen blocks; the source
  // changes only when the last one arrives and all sixteen sectors verify. The track
  // is re-nibblized whole and keeps its address-field volume bytes, where SOS's
  // protection key lives. A track with a damaged sector is not stored.
  {
    uint8_t volumes[16]; memset(volumes,254,16);
    std::vector<uint8_t> keyed(A2_NIB_IMAGE_SIZE); a2_dsk_to_nib(keyed.data(),dsk.data());
    // With volume 254 throughout, the Apple /// track is the shared nibblizer's byte for byte.
    for(int t=0;t<35;t++) {
      uint8_t track[A2_NIB_TRACK_SIZE]; apple3_nib_track(track,dsk.data()+t*4096,t,volumes);
      assert(!memcmp(track,keyed.data()+t*A2_NIB_TRACK_SIZE,A2_NIB_TRACK_SIZE));
    }
    volumes[2]=0xb4; volumes[14]=0xc1;
    apple3_nib_track(keyed.data()+9*A2_NIB_TRACK_SIZE,dsk.data()+9*4096,9,volumes);
    auto next_dsk=dsk; for(int i=0;i<4096;i++) next_dsk[9*4096+i]^=0x5a;
    auto next_nib=keyed; apple3_nib_track(next_nib.data()+9*A2_NIB_TRACK_SIZE,next_dsk.data()+9*4096,9,volumes);
    assert(next_nib!=keyed);
    std::vector<uint8_t> next_woz(512*1024); next_woz.resize(apple3_nib_to_woz(next_woz.data(),next_woz.size(),next_nib.data()));
    auto save_nib_track=[&](const std::vector<uint8_t> &woz,int t,const std::vector<uint8_t> &until_last,size_t off) {
      for(int b=0;b<17;b++) {
        from_fpga.assign(woz.begin()+(3+t*17+b)*512,woz.begin()+(4+t*17+b)*512); write(0,f,3+t*17+b);
        if(b<16) { auto now=bytes(f); assert(!memcmp(now.data()+off,until_last.data(),until_last.size())); }
      }
    };
    auto served=mount_serve(f,keyed,"keyed.nib",0,true);
    save_nib_track(next_woz,9,keyed,0); assert(bytes(f)==next_nib);
    // The served copy holds the new track; only the unmaintained header CRC differs.
    { auto now=serve(0,f); assert(now.size()==next_woz.size() && std::equal(now.begin()+12,now.end(),next_woz.begin()+12)); }
    // The saved image remounts to the new sector data with the same volume bytes.
    auto saved=bytes(f); auto again=mount_serve(f,saved,"keyed.nib",0,true); assert(again==next_woz);
    assert(decode_all(again,back) && back==next_dsk);
    uint8_t got_volumes[16], track9[4096];
    assert(apple3_verify_track(again.data(),again.size(),9,track9,got_volumes)==0xffff && !memcmp(got_volumes,volumes,16));
    // One bad data checksum keeps the whole track out of the source.
    auto damaged=served; size_t data=(3+9*17+6)*512+100; damaged[data]^=0x01;
    message.clear(); save_nib_track(damaged,9,next_nib,0); assert(bytes(f)==next_nib); assert(message.find("not saved")!=std::string::npos);
    // A NIB payload inside a 2MG is stored behind its header.
    std::vector<uint8_t> mgn(64+keyed.size()); twomg_build(mgn.data(),mgn.size(),keyed.data(),keyed.size(),2);
    mount_serve(f,mgn,"keyed.2mg",0,true); save_nib_track(next_woz,9,keyed,64);
    auto stored=bytes(f); assert(!memcmp(stored.data(),mgn.data(),64) && !memcmp(stored.data()+64,next_nib.data(),next_nib.size()));
    // A read-only host file keeps the NIB read-only.
    can_write=false; mount_serve(f,keyed,"keyed.nib",0,false); save_nib_track(next_woz,9,keyed,0); assert(bytes(f)==keyed); can_write=true;
    puts("PASS Apple III NIB write-back: whole verified tracks, volume bytes kept, damaged tracks and read-only files untouched");
  }
  // Apple /// sector images persist writes. Tracks 0, 9 (SOS key field) and 34 (largest
  // synchronized rotation) change in every sector and are saved block by block.
  const int tracks[]={0,9,34};
  auto next=dsk; for(int t:tracks) for(int i=0;i<4096;i++) next[t*4096+i]^=0x5a+i%7;
  std::vector<uint8_t> next_po(next.size()), next_woz(512*1024);
  a2_dos_to_prodos(next_po.data(),next.data());
  next_woz.resize(apple3_dsk_to_woz(next_woz.data(),next_woz.size(),next.data(),0,254));
  mount_serve(f,dsk,"disk.dsk",0,true); message.clear();
  for(int t:tracks) save_track(0,f,next_woz,t,t,[&]{ fresh(bytes(f),dsk,next,t); });
  assert(bytes(f)==next); assert(message.empty());
  assert(mount_serve(f,bytes(f),"disk.dsk",0,true)==next_woz);
  mount_serve(f,po,"disk.po",1,true);
  for(int t:tracks) save_track(1,f,next_woz,t,t,[&]{ fresh(bytes(f),po,next_po,t); });
  assert(bytes(f)==next_po); assert(message.empty());
  // 2MG keeps its header, offset and trailing comment; only payload sectors change.
  auto next_mg=mg; memcpy(next_mg.data()+128,next_po.data(),next_po.size());
  mount_serve(f,mg,"disk.2mg",0,true);
  for(int t:tracks) save_track(0,f,next_woz,t,t,[&]{ fresh(bytes(f),mg,next_mg,t,128); });
  assert(bytes(f)==next_mg); assert(message.empty());
  // Damage is never written to the source: a bad bit in sector 5's data on track 0.
  auto bad_data=next_woz; flip(bad_data,0,5,24+100);
  mount_serve(f,dsk,"disk.dsk",0,true); message.clear();
  save_track(0,f,bad_data,0,0,[&]{ fresh(bytes(f),dsk,next,0); });
  assert(fresh(bytes(f),dsk,next,0)==15); assert(message.find("1 unreadable")!=std::string::npos);
  // A lost data prologue must not pair that address field with the next sector's data.
  auto bad_prologue=next_woz; flip(bad_prologue,9,7,23);
  mount_serve(f,dsk,"disk.dsk",0,true); message.clear();
  save_track(0,f,bad_prologue,9,9,[&]{ fresh(bytes(f),dsk,next,9); });
  assert(fresh(bytes(f),dsk,next,9)==15); assert(message.find("1 unreadable")!=std::string::npos);
  // Address fields for another track (a mis-stepped head) leave the source untouched.
  mount_serve(f,dsk,"disk.dsk",0,true); message.clear();
  save_track(0,f,next_woz,34,0,[&]{ assert(bytes(f)==dsk); });
  assert(message.find("16 unreadable")!=std::string::npos);
  // Host permissions and archives keep a sector image read-only and unmodified.
  can_write=false; mount_serve(f,dsk,"disk.dsk"); save_track(0,f,next_woz,0,0,[&]{ assert(bytes(f)==dsk); });
  assert(serve(0,f)==w); can_write=true; source(f,dsk); f.zip=reinterpret_cast<fileZipArchive*>(1);
  assert(mount(0,"disk.dsk",f,writable) && !writable); f.zip=nullptr;
  puts("PASS Apple /// sector write-back: DSK/PO/2MG persistence, torn saves, damaged fields and protection");
  // SOS copy protection: the key is rebuilt only for a boot volume whose SOS.INTERP is
  // encrypted. A plain interpreter must never get it, or SOS decodes working code into
  // garbage (SYSTEM FAILURE $06). Fixture: volume directory in block 2, a sapling file
  // with its index in block 10 and data from block 11, holding code-like plaintext.
  std::vector<uint8_t> sos_po(A2_525_IMAGE_SIZE), sos(sos_po.size());
  uint8_t *vd=&sos_po[2*512]; vd[4]=0xf4; memcpy(vd+5,"BOOT",4); vd[0x23]=39; vd[0x24]=13;
  uint8_t *fe=vd+4+39; fe[0]=0x2a; memcpy(fe+1,"SOS.INTERP",10); fe[0x11]=10; fe[0x15]=0x00; fe[0x16]=0x10;
  for(int i=0;i<8;i++) sos_po[10*512+i]=11+i;
  std::vector<uint8_t> interp(4096); memcpy(interp.data(),"SOS NTRP",8); interp[10]=0x0e; interp[11]=0x83; interp[12]=0xf2; interp[13]=0x0f;
  const uint8_t code_like[]={0x4c,0x00,0x84,0xa9,0x00,0x8d,0x00,0x19,0x20,0x40,0x84,0xd0,0x03,0x4c,0x80,0x85,0xa5,0x10,0x85,0x12,0x60};
  for(unsigned i=14;i<interp.size();i++) interp[i]=code_like[(i*7+i/64)%sizeof(code_like)];
  const auto plain_interp=interp;
  memcpy(&sos_po[11*512],interp.data(),interp.size()); a2_prodos_to_dos(sos.data(),sos_po.data());
  assert(!apple3_sos_interp_encrypted(sos.data())); assert(!apple3_sos_interp_encrypted(dsk.data()));
  std::vector<uint8_t> plain_woz(512*1024), keyed_woz(512*1024);
  plain_woz.resize(apple3_dsk_to_woz(plain_woz.data(),plain_woz.size(),sos.data(),0,254));
  assert(mount_serve(f,sos,"boot.dsk",0,true)==plain_woz);
  apple3_sos_crypt(&interp[14],interp.size()-14,0x830e);
  memcpy(&sos_po[11*512],interp.data(),interp.size()); a2_prodos_to_dos(sos.data(),sos_po.data());
  assert(apple3_sos_interp_encrypted(sos.data()));
  keyed_woz.resize(apple3_dsk_to_woz(keyed_woz.data(),keyed_woz.size(),sos.data(),1,254));
  assert(mount_serve(f,sos,"boot.dsk",0,true)==keyed_woz);
  plain_woz.resize(512*1024); plain_woz.resize(apple3_dsk_to_woz(plain_woz.data(),plain_woz.size(),sos.data(),0,254));
  assert(keyed_woz!=plain_woz && decode_all(keyed_woz,back) && back==sos);
  // The key sectors carry the key bytes; every other address field keeps volume 254.
  { uint8_t vols[16], trk[4096]; const uint8_t key[8]={0xb4,0xc1,0xe4,0xf3,0x9b,0xbd,0xbd,0x7c}, sec[8]={2,14,10,6,2,14,10,6};
    for(int t=0;t<35;t++) { assert(apple3_verify_track(keyed_woz.data(),keyed_woz.size(),t,trk,vols)==0xffff);
      for(int s=0;s<16;s++) assert(vols[s]==(t>=9&&t<=16&&s==sec[t-9]?key[t-9]:254)); } }
  assert(interp!=plain_interp && !memcmp(&interp[14],&plain_interp[14],3));
  apple3_sos_crypt(&interp[14],interp.size()-14,0x830e); assert(interp==plain_interp);
  puts("PASS SOS protection: key only for an encrypted SOS.INTERP, cipher round-trip, plain volumes untouched");
  // Native WOZ: unknown chunks, raw bits and all metadata remain byte-for-byte.
  w.insert(w.end(),{'M','E','T','A',3,0,0,0,'x','y','z'}); put32(w.data()+8,woz_crc32(w.data()+12,w.size()-12));
  source(f,w); assert(mount(1,"native.woz",f,writable) && writable);
  assert(serve(1,f)==w); from_fpga.assign(w.begin()+1536,w.begin()+2560); from_fpga[345]^=0x20;
  write(1,f,3,1024); auto expected=w; expected[1536+345]^=0x20; memset(expected.data()+8,0,4);
  assert(bytes(f)==expected); assert(serve(1,f)==expected); assert(valid_woz(expected));
  from_fpga.assign(512,0); write(1,f,0); assert(bytes(f)==expected);
  from_fpga.assign(1024,0); write(1,f,f.size/512,1024); assert(bytes(f)==expected);
  source(f,expected); assert(mount(1,"native.woz",f,writable) && writable); assert(serve(1,f)==expected);
  expected[22]=1; source(f,expected); assert(mount(1,"native.woz",f,writable) && !writable);
  from_fpga.assign(512,0x55); write(1,f,3); assert(bytes(f)==expected); assert(serve(1,f)==expected);
  auto bad=w; put32(bad.data()+8,0); put32(bad.data()+16,0x7fffffff); source(f,bad); assert(!mount(0,"broken.woz",f,writable));
  puts("PASS native WOZ: full bursts, CRC, partial EOF, metadata guards, persistence and write protection");
  // Four simultaneous Disk III mounts use separate buffers, permissions and
  // write-back state, including when another drive is replaced or ejected.
  fileTYPE drives[4];
  std::vector<uint8_t> originals[4], mounted[4];
  for (int drive=0; drive<4; ++drive) {
    originals[drive]=dsk;
    for (auto &b:originals[drive]) b ^= uint8_t(drive*57);
    can_write=drive!=2;
    mounted[drive]=mount_serve(drives[drive],originals[drive],"disk.dsk",drive,can_write);
  }
  can_write=true;
  for (int drive=0; drive<4; ++drive) {
    assert(serve(drive,drives[drive])==mounted[drive]);
    save_track(drive,drives[drive],mounted[drive],1,1,[]{});
    assert(bytes(drives[drive])==originals[drive]);
  }
  // Writable D4 persists a whole new track; protected D3 rejects the same data.
  auto new_d4=originals[3];
  std::copy(originals[3].begin()+4096,originals[3].begin()+8192,new_d4.begin());
  std::vector<uint8_t> encoded(512*1024);
  encoded.resize(apple3_dsk_to_woz(encoded.data(),encoded.size(),new_d4.data(),0,254));
  save_track(3,drives[3],encoded,0,0,[]{});
  assert(bytes(drives[3])==new_d4);
  save_track(2,drives[2],encoded,0,0,[]{});
  assert(bytes(drives[2])==originals[2]);
  apple3_unmount(1);
  auto replacement=mount_serve(drives[1],w,"replacement.woz",1,true);
  assert(replacement==w);
  assert(serve(2,drives[2])==mounted[2]);
  assert(bytes(drives[3])==new_d4);
  assert(serve(0,drives[0])==mounted[0]);
  // Remount the saved source: data must survive losing the in-memory cache.
  assert(mount_serve(drives[3],new_d4,"disk.dsk",3,true)==encoded);
  puts("PASS four simultaneous Disk III mounts: independent buffers, protection, writes and remounts");
  // Block slots use the header's payload length, not trailing comments/tags,
  // and the block card's writes land in place behind the header.
  std::vector<uint8_t> block(2048); for(unsigned i=0;i<block.size();i++) block[i]=i;
  std::vector<uint8_t> bm(128+block.size()+99); twomg_build(bm.data(),bm.size(),block.data(),block.size(),1);
  memmove(bm.data()+128,bm.data()+64,block.size()); put32(bm.data()+24,128);
  assert(mount_serve(f,bm,"block.2mg",4,true)==block); assert(f.size==2048);
  from_fpga.assign(512,0xa5); auto before=bytes(f); write(4,f,1);
  { auto after=bytes(f); auto want=before; std::fill(want.begin()+128+512,want.begin()+128+1024,0xa5);
    assert(after==want); assert(serve(4,f)==std::vector<uint8_t>(want.begin()+128,want.begin()+128+2048)); }
  // Out-of-range and oversized writes are acknowledged and ignored.
  write(4,f,4); from_fpga.assign(1024,0x11); write(4,f,3,1024);
  { auto after=bytes(f); auto want=before; std::fill(want.begin()+128+512,want.begin()+128+1024,0xa5); assert(after==want); }
  from_fpga.assign(512,0x5a); assert(mount_serve(f,block,"block.hdv",5,true)==block);
  write(5,f,3); { auto want=block; std::fill(want.begin()+1536,want.end(),0x5a); assert(bytes(f)==want); assert(serve(5,f)==want); }
  // A write-protected 2MG, a DC42 container, a read-only host file and an
  // archive member stay read-only, and their writes change nothing.
  auto wp=bm; put32(wp.data()+16,get32(bm.data()+16)|0x80000000u);
  assert(mount_serve(f,wp,"protected.2mg",4)==block); before=bytes(f); write(4,f,0); assert(bytes(f)==before);
  std::vector<uint8_t> dc(84+block.size()); dc42_build(dc.data(),dc.size(),block.data(),block.size(),0x24,"HD");
  assert(mount_serve(f,dc,"block.image",4)==block); before=bytes(f); write(4,f,0); assert(bytes(f)==before);
  can_write=false; assert(mount_serve(f,block,"readonly.hdv",5)==block); before=bytes(f); write(5,f,0); assert(bytes(f)==before);
  can_write=true; source(f,block); f.zip=reinterpret_cast<fileZipArchive*>(1);
  assert(mount(5,"zipped.po",f,writable) && !writable); f.zip=nullptr;
  source(f,w); assert(!mount(4,"floppy.woz",f,writable));
  source(f,block); assert(!mount(0,"hard.hdv",f,writable));
  source(f,dsk); assert(!mount(4,"disk.dsk",f,writable));
  source(f,bm); bm[12]=3; source(f,bm); assert(!mount(4,"bad.2mg",f,writable));
  // Slots 6 and up, and every slot under another core, are left to the generic path.
  source(f,block); assert(mount(6,"other.hdv",f,writable)); assert(apple3_sd_service(6,&f,1,0,512,0)==0);
  core="Apple-II"; source(f,dsk); assert(mount(0,"disk.dsk",f,writable)); assert(apple3_sd_service(0,&f,1,0,512,0)==0);
  // The //e and IIgs paths in support/a2 are unchanged upstream code.
  assert(iigs_mount(2,"disk.dsk",&f,&writable)==IIGS_HANDLED && writable);
  auto iigs_serve=[&](int slot) { std::vector<uint8_t> r; for(uint64_t lba=0;lba*512<uint64_t(f.size);lba++) { iigs_read(slot,&f,lba,0); r.insert(r.end(),to_fpga.begin(),to_fpga.end()); } r.resize(f.size); return r; };
  auto a2w=iigs_serve(2); assert(a2_woz525_to_dsk(back.data(),a2w.data(),a2w.size()) && back==dsk);
  source(f,block); assert(iigs_mount(1,"disk.po",&f,&writable)==IIGS_PASSTHRU);
  auto changed_dsk=dsk; changed_dsk[512]^=0x73;
  std::vector<uint8_t> changed_woz(512*1024);
  changed_woz.resize(a2_dsk_to_woz525(changed_woz.data(),changed_woz.size(),changed_dsk.data()));
  source(f,dsk); assert(iigs_mount(0,"disk.dsk",&f,&writable)==IIGS_HANDLED && writable);
  for(int b=0;b<13;b++) { from_fpga.assign(changed_woz.begin()+(3+b)*512,changed_woz.begin()+(4+b)*512); iigs_write(0,&f,3+b,0); }
  assert(bytes(f)==changed_dsk);
  core="Apple-IIgs"; std::vector<uint8_t> po35(A2_35_IMAGE_SIZE), back35(po35.size());
  for(auto &b:po35) { rng=rng*1664525+1013904223; b=rng>>24; }
  source(f,po35); assert(iigs_mount(2,"disk.po",&f,&writable)==IIGS_HANDLED && writable);
  auto gs=iigs_serve(2); assert(a2_woz35_to_po(back35.data(),gs.data(),gs.size()) && back35==po35);
  for(int i=0;i<16;i++) iigs_unmount(i);
  // Archives and host permissions force native WOZ read-only without changing it.
  core="Apple-III"; can_write=false; source(f,w);
  assert(mount(0,"native.woz",f,writable) && !writable);
  assert(serve(0,f)==w); can_write=true; source(f,w); f.zip=reinterpret_cast<fileZipArchive*>(1);
  assert(mount(0,"native.woz",f,writable) && !writable);
  assert(serve(0,f)==w); f.zip=nullptr;
  // A supported FLUX container is read-only and is never converted.
  auto flux=w; flux.insert(flux.end(),{'F','L','U','X',160,0,0,0}); flux.resize(flux.size()+160,255);
  flux[20]=3; put32(flux.data()+8,woz_crc32(flux.data()+12,flux.size()-12));
  source(f,flux); assert(mount(0,"flux.woz",f,writable) && !writable); assert(serve(0,f)==flux);
  // A recognizable malformed container must not fall back to a raw block image.
  auto overflow=bm; put32(overflow.data()+12,1); put32(overflow.data()+20,0xffffffff); put32(overflow.data()+28,0);
  source(f,overflow); assert(!mount(4,"bad.2mg",f,writable));
  puts("PASS slot assignments, block images, invalid containers, other cores untouched");
  for(int i=0;i<16;i++) apple3_unmount(i);
}
