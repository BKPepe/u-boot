// SPDX-License-Identifier: GPL-2.0
/*
 * 64-bit unsigned division and modulo for the private libgcc
 *
 * GCC calls __udivdi3() and __umoddi3() for '/' and '%' on unsigned 64-bit
 * operands on 32-bit PowerPC.
 *
 * udivmod64() is a copy of __div64_32() from lib/div64.c, changed to take a
 * 64-bit divisor. Its shift-and-subtract loop already works with one. Like
 * __div64_32(), the functions are not instrumented, as tracing code may
 * divide. The copyright notices below are those of lib/div64.c.
 *
 *   Copyright (C) 2003 Bernardo Innocenti <bernie@develer.com>
 *
 *   Based on former do_div() implementation from asm-parisc/div64.h:
 *	Copyright (C) 1999 Hewlett-Packard Co
 *	Copyright (C) 1999 David Mosberger-Tang <davidm@hpl.hp.com>
 */

#include <linux/types.h>

static notrace u64 udivmod64(u64 n, u64 base, u64 *rem)
{
	u64 b = base;
	u64 res, d = 1;
	u32 high = n >> 32;

	/*
	 * Divide the high word first, as __div64_32() does. This is a 32-bit
	 * division, so it is only valid when the divisor fits into 32 bits.
	 */
	res = 0;
	if (!(base >> 32) && high >= base) {
		high /= (u32)base;
		res = (u64)high << 32;
		n -= (u64)(high * (u32)base) << 32;
	}

	while ((s64)b > 0 && b < n) {
		b = b + b;
		d = d + d;
	}

	do {
		if (n >= b) {
			n -= b;
			res += d;
		}
		b >>= 1;
		d >>= 1;
	} while (d);

	*rem = n;
	return res;
}

/**
 * __udivdi3() - divide two 64-bit unsigned integers
 *
 * @n:		dividend
 * @d:		divisor
 * Return:	quotient
 */
notrace u64 __udivdi3(u64 n, u64 d)
{
	u64 rem;

	return udivmod64(n, d, &rem);
}

/**
 * __umoddi3() - remainder of the division of two 64-bit unsigned integers
 *
 * @n:		dividend
 * @d:		divisor
 * Return:	remainder
 */
notrace u64 __umoddi3(u64 n, u64 d)
{
	u64 rem;

	udivmod64(n, d, &rem);

	return rem;
}
