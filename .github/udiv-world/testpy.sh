#!/bin/bash
# Local testing helper, not for submission upstream.
#
# test.py on a board as the upstream GitLab CI runs it for sandbox, at the
# base or at the tip of a series. Runs in the image of the upstream CI, as its
# user.
#
#   BRANCH  series branch in /src
#   COUNT   commits of the series plus its base
#   REV     base or tip
#   BD      board, sandbox by default
#   SPEC    optional test selection instead of the upstream one
# Results go to /out.
set -euo pipefail
: "${BRANCH:?}" "${COUNT:?}" "${REV:?}"
BD=${BD:-sandbox}
git config --global --add safe.directory '*'
git clone -q --no-local --single-branch --branch "$BRANCH" /src /tmp/src
cd /tmp/src
case $REV in
	base) git checkout -q "HEAD~$((COUNT - 1))" ;;
	tip) ;;
	*) echo "REV must be base or tip"; exit 1 ;;
esac
git log --format='%h %s' -n 1 | tee "/out/commit-$REV.txt"
git clone -q --depth=1 https://git.u-boot-project.org/u-boot/u-boot-test-hooks /tmp/uboot-test-hooks
ln -s travis-ci "/tmp/uboot-test-hooks/bin/$(hostname)"
ln -s travis-ci "/tmp/uboot-test-hooks/py/$(hostname)"
python3 -m venv /tmp/venv
. /tmp/venv/bin/activate
pip install -q -r test/py/requirements.txt -r tools/binman/requirements.txt \
	-r tools/buildman/requirements.txt -r tools/u_boot_pylib/requirements.txt \
	setuptools
B=/tmp/$BD
./tools/buildman/buildman -o "$B" -w -E -W -e --board "$BD" > "/out/build-$REV.log" 2>&1
cp /opt/grub/grub_x86.efi /opt/grub/grub_x64.efi "$B/"
cp /opt/grub/grubriscv64.efi "$B/grub_riscv64.efi"
cp /opt/grub/grubaa64.efi "$B/grub_arm64.efi"
cp /opt/grub/grubarm.efi "$B/grub_arm.efi"
export PATH=/opt/qemu/bin:/tmp/uboot-test-hooks/bin:$PATH
export PYTHONPATH=/tmp/uboot-test-hooks/py/travis-ci
ret=0
./test/py/test.py -ra --bd "$BD" --timing -k "${SPEC:-not event_dump}" \
	--build-dir "$B" --junitxml="/out/results-$REV.xml" > "/out/testpy-$REV.log" 2>&1 || ret=$?
echo "$ret" > "/out/testpy-ret-$REV"
tail -5 "/out/testpy-$REV.log"
echo "test.py returned $ret"
