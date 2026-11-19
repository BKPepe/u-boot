#!/bin/bash
# Writes /out/env.sh for the LTO v3 scripts from the series branch checked out in /src: V3_0 is the tree of the
# base (HEAD~14, must be BASE), V3_n the tree after patch n, V3N07 the tip with patch 07 reverted (needs git >= 2.40).
# usage: mkenv.sh BASE-COMMIT
set -euo pipefail
cd /src; git config --global --add safe.directory '*'
[ "$(git rev-parse HEAD~14)" = "$(git rev-parse "$1")" ] || { echo "HEAD~14 is not the base $1"; exit 1; }
{
echo "# generated $(date '+%F %T') from $(git rev-parse --short=11 HEAD), base $(git rev-parse --short=11 HEAD~14)"
for i in $(seq 0 14); do echo "V3_$i=$(git rev-parse HEAD~$((14 - i))^{tree})"; done
t07=$(git rev-parse HEAD~7)
[ "$(git log -1 --format=%s $t07)" = "powerpc: Drop -ffunction-sections and -fdata-sections with LTO" ] || { echo "HEAD~7 is not patch 07"; exit 1; }
if r=$(git merge-tree --write-tree --merge-base=$t07 HEAD $t07~1 2>/dev/null | head -1); then echo "V3N07=$r"; else echo "# V3N07 not available ($(git --version))"; fi
} > /out/env.sh
cat /out/env.sh
