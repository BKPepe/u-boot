#!/bin/bash
# Local testing helper, not for submission upstream.
#
# One shard of a world build: the boards that the world build of the upstream
# GitLab CI covers (all but xtensa), built with buildman at the base and at
# each patch of a series. Runs in the image of the upstream CI, as its user.
#
#   BRANCH  series branch in /src
#   COUNT   commits to build: the patches plus their base
#   SHARD   shard number, from 0, and SHARDS the number of shards
#   BOARDS  optional comma-separated list of boards instead of the shard
#   T       optional buildman thread count
# Results go to /out.
set -euo pipefail
: "${BRANCH:?}" "${COUNT:?}" "${SHARD:?}" "${SHARDS:?}"
git config --global --add safe.directory '*'
git clone -q --no-local --single-branch --branch "$BRANCH" /src /tmp/src
cd /tmp/src
git log --format='%h %s' -n "$COUNT" | tee /out/commits.txt
python3 -m venv /tmp/venv
. /tmp/venv/bin/activate
pip install -q -r tools/binman/requirements.txt -r tools/buildman/requirements.txt \
	-r board/qualcomm/requirements.txt setuptools
if [ -z "${BOARDS:-}" ]; then
	./tools/buildman/buildman -R /tmp/boards.cfg
	# Status Arch CPU SoC Vendor Board Target ...: all but xtensa, as
	# "buildman -x xtensa" in the upstream world build
	awk '!/^#/ && NF >= 7 && $2 != "xtensa" {print $7}' /tmp/boards.cfg | sort > /out/all-boards.txt
	awk -v s="$SHARD" -v n="$SHARDS" '(NR - 1) % n == s' /out/all-boards.txt > /out/boards.txt
	BOARDS=$(paste -sd, /out/boards.txt)
else
	tr , '\n' <<< "$BOARDS" > /out/boards.txt
fi
echo "shard $SHARD of $SHARDS: $(wc -l < /out/boards.txt) boards"
BM=(./tools/buildman/buildman -b "$BRANCH" -c "$COUNT" -o /tmp/bm --boards "$BOARDS" ${T:+-T "$T"})
{ "${BM[@]}" -n 2>&1 || true; } | head -20 > /out/dry-run.txt
ret=0
"${BM[@]}" -EWM > /out/build.log 2>&1 || ret=$?
echo "$ret" > /out/buildman-ret
"${BM[@]}" -sSe > /out/summary.txt 2>&1 || true
"${BM[@]}" -sSd > /out/sizes.txt 2>&1 || true
python3 /ci/scan.py /tmp/bm/"$BRANCH" > /out/scan.tsv
echo "buildman returned $ret"
