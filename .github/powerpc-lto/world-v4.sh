#!/bin/bash
# LTO v4 build checks, run inside ubppc:trixie (Debian powerpc-linux-gnu GCC 14.2):
#   BN = u-boot/next e6fa1282975 (V4_0), no LTO, all PowerPC boards (MPC85xx, MPC83xx, MPC8xx defconfigs)
#   LN = lto-v4 (V4_17), no LTO, all PowerPC boards
#   LL = lto-v4 (V4_17), CONFIG_LTO=y forced, all MPC85xx boards: link result, fixup table entries and
#        zero entries of u-boot, spl and tpl, and whether any .discard* section is left
#   L10 = lto-v4 with patch 10 reverted (V4N10), LTO, all MPC85xx boards (size claim of patch 10)
#   N10 = V4N10, no LTO, all PowerPC boards (patch 10 changes no build without LTO)
# LL and L10 force CONFIG_LTO=y (LN, despite its L, is the tip WITHOUT LTO).
# docker run --rm --tmpfs /tmp:rw,exec,size=4g -v <u-boot-master>:/src:ro -v <this dir>:/out ubppc:trixie bash /out/world.sh
set -uo pipefail
lto() { case $1 in LL|L10) true ;; *) false ;; esac; }
. /out/env.sh
git config --global --add safe.directory '*'
export CROSS_COMPILE=powerpc-linux-gnu- SOURCE_DATE_EPOCH=1790000000 KBUILD_BUILD_TIMESTAMP=2026-11-19
P=powerpc-linux-gnu-
declare -A REV=([BN]=$V4_0 [LN]=$V4_17 [LL]=$V4_17 [L10]=$V4N10 [N10]=$V4N10)
passes=${PASSES:-BN LN LL}
OUT=/out/world-${TAG:-v4}; mkdir -p $OUT
echo "### $(date +%T) $(${P}gcc --version | head -1); $(${P}ld --version | head -1)"

zeros() { # elf -> "entries=N zeros=Z"
	python3 - "$1" <<'EOF'
import sys, subprocess, struct
elf = sys.argv[1]
nm = subprocess.check_output(["powerpc-linux-gnu-nm", elf]).decode().split("\n")
sym = {l.split()[2]: int(l.split()[0], 16) for l in nm if len(l.split()) == 3}
if "_FIXUP_TABLE_" not in sym:
    print("no-fixup-table"); sys.exit()
tbl, n = sym["_FIXUP_TABLE_"], sym["__fixup_entries"]
hdr = subprocess.check_output(["powerpc-linux-gnu-readelf", "-SW", elf]).decode()
addr = None
for l in hdr.splitlines():
    p = l.replace("[ ", "[").split()
    if len(p) > 3 and p[1] == ".reloc":
        addr = int(p[3], 16)
subprocess.check_call(["powerpc-linux-gnu-objcopy", "-O", "binary", "-j", ".reloc", elf, "/tmp/reloc.bin"])
data = open("/tmp/reloc.bin", "rb").read()
off = tbl - addr
words = [struct.unpack(">I", data[off + 4 * i: off + 4 * i + 4])[0] for i in range(n)]
print(f"entries={n} zeros={sum(1 for w in words if w == 0)}")
EOF
}

build() { # pass board
	local p=$1 b=$2 o=/tmp/b-w-$2 log=$OUT/$1/$2.log r
	mkdir -p $OUT/$p; rm -rf $o
	make -s -C /tmp/src-w O=$o ${b}_defconfig > $log 2>&1 || { echo "defconfig failed"; return; }
	if lto $p; then
		/tmp/src-w/scripts/config --file $o/.config -e LTO
		make -s -C /tmp/src-w O=$o olddefconfig >> $log 2>&1
		grep -q '^CONFIG_LTO=y' $o/.config || { echo "LTO not selectable"; rm -rf $o; return; }
	fi
	if ! make -s -C /tmp/src-w O=$o -j${J:-8} >> $log 2>&1; then
		echo "FAILED: $(grep -m2 -E 'error|overlap|exceed|undefined' $log | cut -c1-160 | tr '\n' '|')"; rm -rf $o; return
	fi
	r="ok"; grep -qi warning $log && r="ok (warnings: $(grep -ci warning $log))"; r="$r priv=$(grep -c "^CONFIG_USE_PRIVATE_LIBGCC=y" $o/.config)"
	for img in u-boot spl/u-boot-spl tpl/u-boot-tpl; do
		[ -f $o/$img ] || continue
		r="$r | $(basename $img): $(${P}size $o/$img | tail -1 | awk '{print "text="$1" data="$2" bss="$3}') md5=$(md5sum < $o/$img.bin 2>/dev/null | cut -c1-8)"
		lto $p && r="$r $(zeros $o/$img) discard-secs=$(${P}readelf -SW $o/$img | grep -c '\.discard')"
	done
	echo "$r"
	rm -rf $o
}

for p in $passes; do
	rm -rf /tmp/src-w; mkdir -p /tmp/src-w
	git -C /src archive ${REV[$p]} | tar -x -C /tmp/src-w
	if lto $p; then list=$(cd /tmp/src-w && grep -l '^CONFIG_MPC85xx=y' configs/*_defconfig | sed 's#configs/##; s#_defconfig##' | sort)
	else list=$(cd /tmp/src-w && grep -lE '^CONFIG_(MPC85xx|MPC83xx|MPC8xx)=y' configs/*_defconfig | sed 's#configs/##; s#_defconfig##' | sort); fi
	[ -n "${BOARDS:-}" ] && list="$BOARDS"
	# SHARD of SHARDS: every SHARDS-th board, starting at SHARD (0-based), so that a matrix can split a pass
	[ -n "${SHARDS:-}" ] && list=$(echo $list | tr ' ' '\n' | awk -v s=${SHARD:-0} -v n=$SHARDS '(NR - 1) % n == s')
	echo "### $(date +%T) pass $p tree $(git -C /src rev-parse --short ${REV[$p]}) boards $(echo $list | wc -w)"
	for b in $list; do printf "### %s %s %-32s %s\n" "$(date +%T)" $p $b "$(build $p $b)"; done
	rm -rf /tmp/src-w
done
echo "### $(date +%T) DONE"
