#!/bin/bash
# Patch "xpl: Pass the make jobserver to the xPL link": turris_1x_sdcard (LTO) at -j8 with Debian's GCC 12.2
# and make 4.3, at lto-v4 (V4_17) with the '+' removed again (before) and as it is (after), two tries each.
# docker run --rm --tmpfs /tmp:rw,exec,size=4g -v <u-boot-master>:/src:ro -v <this dir>:/out ubppc:bookworm bash /out/gcc12.sh
set -uo pipefail
. /out/env.sh
git config --global --add safe.directory '*'
export CROSS_COMPILE=powerpc-linux-gnu- SOURCE_DATE_EPOCH=1790000000 KBUILD_BUILD_TIMESTAMP=2026-11-19
OUT=/out/gcc12-${TAG:-v4}; mkdir -p $OUT
echo "### $(date +%T) $(powerpc-linux-gnu-gcc --version | head -1); $(make --version | head -1); tree $V4_17"
for v in before after; do
	rm -rf /tmp/t-$v; mkdir -p /tmp/t-$v; git -C /src archive $V4_17 | tar -x -C /tmp/t-$v
	[ $v = before ] && sed -i 's|^\t+$(call if_changed,u-boot-spl)$|\t$(call if_changed,u-boot-spl)|' /tmp/t-$v/scripts/Makefile.xpl
	echo "### $v: SPL link rule: $(grep -A0 -E '^\s\+?\$\(call if_changed,u-boot-spl\)' /tmp/t-$v/scripts/Makefile.xpl | cat -A | head -1)"
	for try in 1 2; do
		o=/tmp/b-$v-$try; log=$OUT/turris_1x_sdcard-$v-$try.log; rm -rf $o
		make -s -C /tmp/t-$v O=$o turris_1x_sdcard_defconfig > $log 2>&1
		if make -s -C /tmp/t-$v O=$o -j8 >> $log 2>&1; then
			echo "### $(date +%T) $v try $try: turris_1x_sdcard -j8 ok LTO=$(grep -c '^CONFIG_LTO=y' $o/.config) u-boot.bin=$(stat -c %s $o/u-boot.bin) spl=$(stat -c %s $o/spl/u-boot-spl.bin)"
		else
			echo "### $(date +%T) $v try $try: turris_1x_sdcard -j8 FAILED: $(grep -m3 -E 'jobserver|lto-wrapper|Error' $log | cut -c1-120 | tr '\n' '|')"
		fi
		rm -rf $o
	done
	rm -rf /tmp/t-$v
done
echo "### $(date +%T) DONE"
