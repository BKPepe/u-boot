#!/bin/bash
# LTO v3: Turris 1.x builds at every state of lto-v3 (V3_0 = u-boot/next e6fa1282975 .. V3_14), Debian GCC 14.2;
# the kernel.org GCC 14.2.0 that CI uses at V3_0 and V3_14; router images (LOCALVERSION) at V3_14.
# Every state is extracted to the same path (/tmp/t-cur), so that md5 sums of two states can be compared.
# docker run --rm --tmpfs /tmp:rw,exec,size=8g -v <u-boot-master>:/src:ro -v <this dir>:/out ubppc:trixie bash /out/turris-v3.sh
set -uo pipefail
. /out/env.sh
git config --global --add safe.directory '*'
export SOURCE_DATE_EPOCH=1790000000 KBUILD_BUILD_TIMESTAMP=2026-11-19
D=powerpc-linux-gnu-; OUT=/out/turris; mkdir -p $OUT/logs $OUT/img
say() { echo "### $(date +%T) $*" | tee -a $OUT/summary.log; }
cur=
tree() { [ "$cur" = "$1" ] && return; rm -rf /tmp/t-cur; mkdir -p /tmp/t-cur; git -C /src archive ${!1} | tar -x -C /tmp/t-cur; cur=$1; }
b() { # label treevar board cross [localversion keepdir]
	local l=$1 tv=$2 c=$3 cc=$4 lv=${5:-} keep=${6:-} o=/tmp/o-cur log=$OUT/logs/$1-$3.log
	tree $tv; rm -rf $o
	if ! { make -s -C /tmp/t-cur O=$o ${c}_defconfig CROSS_COMPILE=$cc > $log 2>&1 && make -s -C /tmp/t-cur O=$o -j${J:-4} CROSS_COMPILE=$cc LOCALVERSION=$lv >> $log 2>&1; }; then
		echo "### $l $c FAILED: $(grep -m3 -iE 'error|overlap|exceed|undefined|BUG' $log | cut -c1-200 | tr '\n' '|')"; rm -rf $o; return
	fi
	local nd=$(stat -c %s $o/u-boot-nodtb.bin) ub=$(stat -c %s $o/u-boot.bin) lim=$(grep '^CONFIG_BOARD_SIZE_LIMIT=' $o/.config | cut -d= -f2)
	local end=$(${cc}nm $o/u-boot | awk '$3=="_end"{print $1}') tb=$(grep '^CONFIG_TEXT_BASE=' $o/.config | cut -d= -f2)
	local fdt=$(python3 -c "b=open('$o/u-boot.bin','rb').read(); i=b.find(b'\xd0\x0d\xfe\xed', $nd - 16); print(hex(i))")
	local bp=$(${cc}objdump -h $o/u-boot | python3 -c '
import sys,re
L=sys.stdin.read().splitlines(); s=[]; bp=None
for i,l in enumerate(L):
    f=l.split()
    if len(f)>=6 and re.match(r"^[0-9]+$",f[0]):
        if "CONTENTS" not in (L[i+1] if i+1<len(L) else ""): continue
        sz=int(f[2],16); lma=int(f[4],16)
        if f[1]==".bootpg": bp=lma
        else: s.append((lma,sz))
print(bp-max(a+b for a,b in s if a<bp) if bp else "-")')
	local x=""; [ -f $o/spl/u-boot-spl.bin ] && x=" spl=$(stat -c %s $o/spl/u-boot-spl.bin) with-spl=$(stat -c %s $o/u-boot-with-spl.bin 2>/dev/null) spl-md5=$(md5sum < $o/spl/u-boot-spl.bin | cut -c1-8)"
	[ "$(grep -c '^CONFIG_LTO=y' $o/.config)" = 1 ] && x="$x u-boot:$(python3 /out/fixz.py $o/u-boot) discard=$(${cc}readelf -SW $o/u-boot | grep -c '\.discard')$([ -f $o/spl/u-boot-spl ] && echo " spl:$(python3 /out/fixz.py $o/spl/u-boot-spl) spl-discard=$(${cc}readelf -SW $o/spl/u-boot-spl | grep -c '\.discard')")"
	echo "### $l $c ok LTO=$(grep -c '^CONFIG_LTO=y' $o/.config) BCH=$(grep -c '^CONFIG_NAND_ECC_BCH=y' $o/.config) UBI=$(grep -c '^CONFIG_CMD_UBI=y' $o/.config) NVME=$(grep -c '^CONFIG_NVME=y' $o/.config) SCSI=$(grep -c '^CONFIG_SCSI=y' $o/.config) PRIV=$(grep -c '^CONFIG_USE_PRIVATE_LIBGCC=y' $o/.config) nodtb=$nd u-boot.bin=$ub limit=$lim end-off=$(printf 0x%x $((0x$end - tb))) fdt-at=$fdt bootpg-margin=$bp$x md5=$(md5sum < $o/u-boot.bin | cut -c1-8)"
	[ -n "$keep" ] && { mkdir -p $OUT/img/$keep; cp $o/u-boot $o/u-boot.bin $o/.config $OUT/img/$keep/; [ -f $o/u-boot-with-spl.bin ] && cp $o/u-boot-with-spl.bin $o/spl/u-boot-spl $OUT/img/$keep/; md5sum $OUT/img/$keep/u-boot*.bin > $OUT/img/$keep/md5.txt; }
	rm -rf $o
}
say "start; $(${D}gcc --version | head -1); $(${D}ld --version | head -1)"
for i in ${STATES:-$(seq 0 14)}; do for c in turris_1x_nor turris_1x_sdcard; do b v3-$i V3_$i $c $D; done; done 2>&1 | tee -a $OUT/summary.log
# router images: the same tree with LOCALVERSION, so that the banner names the build
b rtr-v3 V3_14 turris_1x_nor $D -v3-nor v3-nor 2>&1 | tee -a $OUT/summary.log
b rtr-v3 V3_14 turris_1x_sdcard $D -v3-sd v3-sd 2>&1 | tee -a $OUT/summary.log
KA=$(uname -m); [ $KA = aarch64 ] && KA=arm64
mkdir -p /opt/kt; URL=https://mirrors.edge.kernel.org/pub/tools/crosstool/files/bin/$KA/14.2.0/$KA-gcc-14.2.0-nolibc-powerpc-linux.tar.xz
for try in 1 2 3; do
	python3 -c "import urllib.request,shutil,sys; shutil.copyfileobj(urllib.request.urlopen('$URL', timeout=120), sys.stdout.buffer)" > /tmp/kt.tar.xz 2> $OUT/ktdl-$try.log && tar -xJf /tmp/kt.tar.xz -C /opt/kt && break
	sleep 20
done
rm -f /tmp/kt.tar.xz
if ls -d /opt/kt/*/powerpc-linux/bin >/dev/null 2>&1; then
	K=$(ls -d /opt/kt/*/powerpc-linux/bin)/powerpc-linux-
	say "kernel.org: $(${K}gcc --version | head -1)"
	for tv in ${KT_TREES:-V3_0 V3_14}; do for c in turris_1x_nor turris_1x_sdcard; do b ci-$tv $tv $c $K; done; done 2>&1 | tee -a $OUT/summary.log
else say "kernel.org toolchain download FAILED: $(tail -2 $OUT/ktdl-3.log 2>/dev/null)"; fi
say DONE
