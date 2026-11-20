#!/bin/bash
# LTO v4 claim checks on u-boot/next e6fa1282975 (Debian powerpc-linux-gnu GCC 14.2), trees in env.sh.
#   P02  no PowerPC defconfig builds common/spl/spl.c (no SPL/TPL_FRAMEWORK), and no MPC83xx/MPC8xx defconfig can
#        enable LTO at V4_17
#   P12  three LTO builds at V4_17 at -j8 with and without the '+' of patch 12: link result and image md5
#   P14  every defconfig evaluated with kconfiglib before (V4_13) and after (V4_14) patch 14 (p14.py): the boards
#        whose configuration changes, with the changed lines
#   SAV  savedefconfig at V4_17 of the three defconfigs the series touches equals the committed file
# docker run --rm --tmpfs /tmp:rw,exec,size=8g -v <u-boot-master>:/src:ro -v <this dir>:/out ubppc:trixie bash /out/claims-v4.sh
set -uo pipefail
. /out/env.sh
git config --global --add safe.directory '*'
export CROSS_COMPILE=powerpc-linux-gnu- SOURCE_DATE_EPOCH=1790000000 KBUILD_BUILD_TIMESTAMP=2026-11-19
D=powerpc-linux-gnu-; OUT=/out/claims; mkdir -p $OUT/logs
say() { echo "### $(date +%T) $*"; }
cur=
tree() { [ "$cur" = "$1" ] && return; rm -rf /tmp/t-cur; mkdir -p /tmp/t-cur; git -C /src archive ${!1} | tar -x -C /tmp/t-cur; cur=$1; }
cfg() { make -s -C /tmp/t-cur O=$2 $1_defconfig > /dev/null 2>&1; }
say "start; $(${D}gcc --version | head -1)"

say "P02"
tree V4_17
ppc=$(cd /tmp/t-cur && grep -lE '^CONFIG_(MPC85xx|MPC83xx|MPC8xx)=y' configs/*_defconfig | sed 's#configs/##; s#_defconfig##' | sort)
small=$(cd /tmp/t-cur && grep -lE '^CONFIG_(MPC83xx|MPC8xx)=y' configs/*_defconfig | sed 's#configs/##; s#_defconfig##' | sort)
n=0; fw=0
for b in $ppc; do
	o=/tmp/c-$b; rm -rf $o; cfg $b $o || { echo "P02 $b defconfig FAILED"; continue; }; n=$((n + 1))
	f=$(grep -E '^CONFIG_(SPL|TPL|VPL)_FRAMEWORK=y' $o/.config | tr '\n' ' ')
	[ -n "$f" ] && { fw=$((fw + 1)); echo "P02 FRAMEWORK $b: $f"; }
	rm -rf $o
done
say "P02 $n PowerPC defconfigs, $fw with an SPL/TPL/VPL framework"
for b in $small; do
	o=/tmp/c-$b; rm -rf $o; cfg $b $o; /tmp/t-cur/scripts/config --file $o/.config -e LTO
	make -s -C /tmp/t-cur O=$o olddefconfig > /dev/null 2>&1
	echo "P02 LTO-try $b: CONFIG_LTO=$(grep -c '^CONFIG_LTO=y' $o/.config) ARCH_SUPPORTS_LTO=$(grep -c '^CONFIG_ARCH_SUPPORTS_LTO=y' $o/.config)"
	rm -rf $o
done

say "P12"
for v in plus noplus; do
	cur=; tree V4_17
	[ $v = noplus ] && sed -i 's|^\t+$(call if_changed,u-boot-spl)$|\t$(call if_changed,u-boot-spl)|' /tmp/t-cur/scripts/Makefile.xpl
	echo "P12 $v rule: $(grep -E '^\s\+?\$\(call if_changed,u-boot-spl\)' /tmp/t-cur/scripts/Makefile.xpl | cat -A)"
	for b in turris_1x_sdcard P2020RDB-PC_NAND T2080RDB_NAND; do
		o=/tmp/p12; rm -rf $o; cfg $b $o; /tmp/t-cur/scripts/config --file $o/.config -e LTO
		make -s -C /tmp/t-cur O=$o olddefconfig > /dev/null 2>&1
		if make -s -C /tmp/t-cur O=$o -j8 > $OUT/logs/p12-$v-$b.log 2>&1; then
			echo "P12 $v $b ok LTO=$(grep -c '^CONFIG_LTO=y' $o/.config) $(for f in u-boot.bin spl/u-boot-spl.bin tpl/u-boot-tpl.bin; do [ -f $o/$f ] && echo -n "$f=$(md5sum < $o/$f | cut -c1-8) "; done)"
		else
			echo "P12 $v $b FAILED: $(grep -m3 -E 'jobserver|lto-wrapper|Error' $OUT/logs/p12-$v-$b.log | cut -c1-120 | tr '\n' '|')"
		fi
		rm -rf $o
	done
done

say "P14"
for t in V4_13 V4_14; do rm -rf /tmp/p14-$t; mkdir -p /tmp/p14-$t; git -C /src archive ${!t} | tar -x -C /tmp/p14-$t; done
python3 /out/p14.py /tmp/p14-V4_13 /tmp/p14-V4_14
rm -rf /tmp/p14-V4_13 /tmp/p14-V4_14

say "SAV"
cur=; tree V4_17
for b in turris_1x_nor turris_1x_sdcard kmcoge5ne; do
	o=/tmp/sav; rm -rf $o; cfg $b $o; make -s -C /tmp/t-cur O=$o savedefconfig > /dev/null 2>&1
	if cmp -s $o/defconfig /tmp/t-cur/configs/${b}_defconfig; then echo "SAV $b identical"; else echo "SAV $b DIFFERS:"; diff /tmp/t-cur/configs/${b}_defconfig $o/defconfig | head -20; fi
	rm -rf $o
done
say DONE
