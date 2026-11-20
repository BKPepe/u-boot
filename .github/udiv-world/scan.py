#!/usr/bin/env python3
# Local testing helper, not for submission upstream.
#
# One line per commit and board of a buildman output directory: commit number,
# board, make return code ('-' if not built), number of lines in the err file,
# and the 64-bit division helpers of libgcc found in each ELF's function sizes.
import glob
import os
import re
import sys

HELPERS = re.compile(r'\s(__udivdi3|__umoddi3|__divdi3|__moddi3|__udivmoddi4|'
                     r'__divmoddi4|__aeabi_uldivmod|__aeabi_ldivmod)$')

for cdir in sorted(glob.glob(os.path.join(sys.argv[1], '[0-9]*_*/'))):
    commit = os.path.basename(cdir.rstrip('/')).split('_')[0]
    for bdir in sorted(glob.glob(cdir + '*/')):
        board = os.path.basename(bdir.rstrip('/'))
        done = '-'
        if os.path.exists(bdir + 'done'):
            with open(bdir + 'done', encoding='utf-8') as inf:
                done = inf.read().split()[0]
        nerr = 0
        if os.path.exists(bdir + 'err'):
            with open(bdir + 'err', encoding='utf-8', errors='replace') as inf:
                nerr = sum(1 for _ in inf)
        found = []
        for fname in sorted(glob.glob(bdir + '*.sizes')):
            elf = os.path.basename(fname)[:-len('.sizes')]
            with open(fname, encoding='utf-8', errors='replace') as inf:
                for line in inf:
                    m = HELPERS.search(line.rstrip('\n'))
                    if m:
                        found.append(f'{elf}:{m.group(1)}')
        print('\t'.join([commit, board, done, str(nerr), ','.join(found) or '-']))
