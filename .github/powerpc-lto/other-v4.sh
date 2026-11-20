#!/bin/bash
# LTO v4: patches 4-7 change common code, so build it before (V4_3) and after them (V4_7) for other architectures:
#   sandbox (host, btrfs + squashfs + MMC), turris_omnia (arm, btrfs + MMC), xilinx_zynq_virt (arm, squashfs + MMC),
#   turris_mox (arm64, btrfs + MMC), mvebu_espressobin-88f3720 (arm64, squashfs + MMC): result, warnings, size of
#   U-Boot proper and whether the objects with the changed code were built. Then test.py's squashfs tests on sandbox
#   at V4_3 and V4_7. Needs gcc-arm-linux-gnueabihf, gcc-aarch64-linux-gnu (or a native arm64 host), squashfs-tools.
set -uo pipefail
. /out/env.sh
git config --global --add safe.directory '*'
export SOURCE_DATE_EPOCH=1790000000 KBUILD_BUILD_TIMESTAMP=2026-11-20
OUT=/out/other-${TAG:-v4}; mkdir -p $OUT/logs
say() { echo "### $(date +%T) $*"; }
command -v aarch64-linux-gnu-gcc > /dev/null || { echo "no aarch64-linux-gnu-gcc"; exit 1; }
BOARDS=${BOARDS:-"sandbox: turris_omnia:arm-linux-gnueabihf- xilinx_zynq_virt:arm-linux-gnueabihf- turris_mox:aarch64-linux-gnu- mvebu_espressobin-88f3720:aarch64-linux-gnu-"}
OBJS="fs/btrfs/disk-io.o fs/btrfs/extent-io.o fs/squashfs/sqfs.o fs/squashfs/sqfs_inode.o drivers/mmc/mmc_write.o"
say "start; $(gcc --version | head -1); $(arm-linux-gnueabihf-gcc --version | head -1); $(aarch64-linux-gnu-gcc --version | head -1)"
for tv in V4_3 V4_7; do
	s=/tmp/s-$tv; rm -rf $s; mkdir -p $s; git -C /src archive ${!tv} | tar -x -C $s
	for spec in $BOARDS; do
		b=${spec%%:*}; cc=${spec#*:}; o=/tmp/o-$b; log=$OUT/logs/$tv-$b.log; rm -rf $o
		if ! { make -s -C $s O=$o ${b}_defconfig CROSS_COMPILE=$cc > $log 2>&1 && make -s -C $s O=$o -j${J:-4} CROSS_COMPILE=$cc NO_SDL=1 >> $log 2>&1; }; then
			echo "### $tv $b FAILED: $(grep -m3 -E 'error|undefined' $log | cut -c1-160 | tr '\n' '|')"; rm -rf $o; continue
		fi
		built=$(for f in $OBJS; do [ -f $o/$f ] && echo -n "$(basename $f .o) "; done)
		echo "### $tv $b ok warnings=$(grep -c 'warning:' $log) $(${cc}size $o/u-boot | tail -1 | awk '{print "text="$1" data="$2" bss="$3}') objs: ${built:-none}"
		[ $b = sandbox ] && { rm -rf /tmp/sb-$tv; cp -a $o /tmp/sb-$tv; }
		rm -rf $o
	done
done
# test.py squashfs tests on the sandbox builds above
for tv in V4_3 V4_7; do
	s=/tmp/s-$tv; [ -d /tmp/sb-$tv ] || { echo "### $tv no sandbox build for test.py"; continue; }
	if [ ! -d /tmp/venv ]; then
		python3 -m venv /tmp/venv
		/tmp/venv/bin/pip install -q -r $s/test/py/requirements.txt > $OUT/pip.log 2>&1 || { echo "pip failed"; tail -5 $OUT/pip.log; exit 1; }
	fi
	r=$OUT/sqfs-$tv; mkdir -p $r
	(cd $s && /tmp/venv/bin/python3 ./test/py/test.py -ra --bd sandbox --build-dir /tmp/sb-$tv --result-dir $r \
		--persistent-data-dir $r/persist -k sqfs > $r/testpy.log 2>&1)
	echo "### $tv test.py -k sqfs exit $?: $(grep -E '^=+ .*(passed|failed|skipped).* =+$' $r/testpy.log | tail -1)"
	grep -E '^(FAILED|SKIPPED|ERROR)' $r/testpy.log | sed "s/^/### $tv /" | head -20
done
rm -rf /tmp/s-V4_3 /tmp/s-V4_7 /tmp/sb-V4_3 /tmp/sb-V4_7
say DONE
