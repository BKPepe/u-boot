import sys, subprocess, struct
elf = sys.argv[1]
nm = subprocess.check_output(["powerpc-linux-gnu-nm", elf]).decode().split("\n")
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm if len(l.split()) == 3}
tbl, n = sym["_FIXUP_TABLE_"], sym["__fixup_entries"]
addr = [int(l.replace("[ ", "[").split()[3], 16) for l in subprocess.check_output(["powerpc-linux-gnu-readelf", "-SW", elf]).decode().splitlines() if len(l.replace("[ ", "[").split()) > 3 and l.replace("[ ", "[").split()[1] == ".reloc"][0]
subprocess.check_call(["powerpc-linux-gnu-objcopy", "-O", "binary", "-j", ".reloc", elf, "/tmp/reloc.bin"])
d = open("/tmp/reloc.bin", "rb").read()[tbl - addr:]
print(f"fixup={n}/zero={sum(1 for i in range(n) if struct.unpack('>I', d[4*i:4*i+4])[0] == 0)}")
