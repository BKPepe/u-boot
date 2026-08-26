#!/bin/bash
# SPDX-License-Identifier: GPL-2.0+
# Copyright (C) 2020 Marek Behún <kabel@kernel.org>

# Generate __ADDRESSABLE(symbol) for every linker list entry symbol, so that LTO
# does not optimize these symbols away

# The first parameter of this script is the nm binary to use, the rest
# are the objects to parse, for example: $(NM) $(u-boot-main)

set -e

nm="$1"
shift

echo '#include <linux/compiler.h>'
"$nm" --defined-only "$@" 2>/dev/null | \
	grep -oe '_u_boot_list_2_[a-zA-Z0-9_]*_2_[a-zA-Z0-9_]*' \
	-e '__stack_chk_guard' | sort -u | \
	sed -e 's/^\(.*\)/extern char \1[];\n__ADDRESSABLE(\1);/'
