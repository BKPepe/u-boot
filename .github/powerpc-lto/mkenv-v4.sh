#!/bin/bash
# Writes /out/env.sh for the LTO v4 scripts: V4_0 is the tree of the base (REF~17, must be BASE), V4_n the tree
# after patch n, V4N10 the tip with patch 10 ("powerpc: Drop -ffunction-sections and -fdata-sections with LTO")
# reverted (needs git >= 2.40). usage: mkenv-v4.sh BASE-COMMIT [REF, default HEAD] (repository in /src)
set -euo pipefail
cd /src; git config --global --add safe.directory '*'
R=${2:-HEAD}
[ "$(git rev-parse $R~17)" = "$(git rev-parse "$1")" ] || { echo "$R~17 is not the base $1"; exit 1; }
{
echo "# generated $(date '+%F %T') from $(git rev-parse --short=11 $R), base $(git rev-parse --short=11 $R~17)"
for i in $(seq 0 17); do echo "V4_$i=$(git rev-parse $R~$((17 - i))^{tree})"; done
t10=$(git rev-parse $R~7)
[ "$(git log -1 --format=%s $t10)" = "powerpc: Drop -ffunction-sections and -fdata-sections with LTO" ] || { echo "$R~7 is not patch 10"; exit 1; }
if r=$(git merge-tree --write-tree --merge-base=$t10 $R $t10~1 2>/dev/null | head -1); then echo "V4N10=$r"; else echo "# V4N10 not available ($(git --version))"; fi
} > /out/env.sh
cat /out/env.sh
