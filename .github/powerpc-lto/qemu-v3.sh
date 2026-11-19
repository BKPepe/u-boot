#!/bin/bash
# Upstream CI's "qemu-ppce500 test.py" job (test hooks, -k "not sleep"), inside ubppc:trixie, for
#   base  = u-boot/next e6fa1282975 (V3_0), no LTO (reference)
#   nolto = lto-v3 (V3_14), no LTO
#   lto   = lto-v3 (V3_14), CONFIG_LTO=y
# docker run --rm --tmpfs /tmp:rw,exec,size=4g -v <u-boot-master>:/src:ro -v <hooks>:/hooks:ro -v <this dir>:/out ubppc:trixie bash /out/qemu.sh
set -uo pipefail
. /out/env.sh
git config --global --add safe.directory '*'
OUT=/out/qemu-${TAG:-v3}; mkdir -p $OUT
declare -A REV=([base]=$V3_0 [nolto]=$V3_14 [lto]=$V3_14)
export CROSS_COMPILE=powerpc-linux-gnu-
rm -rf /tmp/uboot-test-hooks; cp -r /hooks /tmp/uboot-test-hooks
ln -s travis-ci /tmp/uboot-test-hooks/bin/$(hostname)
ln -s travis-ci /tmp/uboot-test-hooks/py/$(hostname)
echo "### $(date +%T) $(powerpc-linux-gnu-gcc --version | head -1); $(qemu-system-ppc --version | head -1)"
for v in ${VARIANTS:-base nolto lto}; do
	s=/tmp/src-q-$v; b=/tmp/qemu-ppce500-$v; r=$OUT/$v
	rm -rf $s $b; mkdir -p $s $r
	git -C /src archive ${REV[$v]} | tar -x -C $s
	cd $s
	if [ ! -d /tmp/venv ]; then
		python3 -m venv /tmp/venv
		/tmp/venv/bin/pip install -q -r test/py/requirements.txt -r tools/binman/requirements.txt \
			-r tools/buildman/requirements.txt -r tools/u_boot_pylib/requirements.txt setuptools \
			> $OUT/pip.log 2>&1 || { echo "pip failed"; tail -5 $OUT/pip.log; exit 1; }
	fi
	. /tmp/venv/bin/activate
	make -s O=$b qemu-ppce500_defconfig > $r/build.log 2>&1
	[ $v = lto ] && { scripts/config --file $b/.config -e LTO; make -s O=$b olddefconfig >> $r/build.log 2>&1; }
	echo "### $v tree $(echo ${REV[$v]} | cut -c1-11) LTO=$(grep -c '^CONFIG_LTO=y' $b/.config)"
	make -s O=$b -j8 >> $r/build.log 2>&1 || { echo "### $v build FAILED"; tail -5 $r/build.log; deactivate; continue; }
	powerpc-linux-gnu-size $b/u-boot | tail -1
	export PATH=/tmp/uboot-test-hooks/bin:$PATH PYTHONPATH=/tmp/uboot-test-hooks/py/travis-ci
	./test/py/test.py -ra --bd qemu-ppce500 -k "not sleep" --build-dir $b --result-dir $r \
		--persistent-data-dir $r/persist > $r/testpy.log 2>&1
	echo "### $v test.py exit $?: $(grep -E '^=+ .*(passed|failed).* =+$' $r/testpy.log | tail -1)"
	grep -E '^FAILED' $r/testpy.log | sed "s/^/### $v /"
	deactivate
	cd /; rm -rf $s $b
done
echo "### $(date +%T) DONE"
