"""Write the Quartus memory file for a byte-per-line hex image.

Simulation loads the hex with $readmemh; Quartus's altsyncram wants a MIF.
  hex2mif.py rtl/apple3_rom.hex rtl/apple3_rom.mif
"""
import sys

data = [int(line, 16) for line in open(sys.argv[1]).read().split()]
with open(sys.argv[2], "w") as out:
    out.write(f"DEPTH = {len(data)};\nWIDTH = 8;\nADDRESS_RADIX = HEX;\nDATA_RADIX = HEX;\nCONTENT BEGIN\n")
    for address, value in enumerate(data):
        out.write(f"{address:04X} : {value:02X};\n")
    out.write("END;\n")
