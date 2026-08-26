// SPDX-License-Identifier: GPL-2.0+
/*
 * Copyright (C) 2026 Josef Schlehofer <pepe.schlehofer@gmail.com>
 */

#include <asm/global_data.h>

DECLARE_GLOBAL_DATA_PTR;

void arch_setup_gd(gd_t *new_gd)
{
	set_gd(new_gd);
}
