/* SPDX-License-Identifier: GPL-2.0 */
/*
 * NX809J boot shim entry.
 *
 * ABL ignores the DTB appended to the kernel and passes the downstream one
 * from vendor_boot in x0. We merge what ABL filled in (memory, initrd,
 * kaslr seed) into our embedded mainline DTB and enter Linux with that.
 *
 * Runs with the MMU and D-cache off (arm64 boot protocol), position
 * independent. If the merge fails we PSCI-reset, so a shim failure shows
 * up as a boot loop rather than a hang.
 */
#include "layout.h"

	.section .text.head, "ax"
	.global _start
_start:
	b	entry			/* code0 */
	.long	0			/* code1 */
	.quad	0			/* text_offset */
	.quad	0			/* image_size: patched by mkshim.py */
	.quad	0			/* flags: copied from the kernel by mkshim.py */
	.quad	0, 0, 0			/* res2-4 */
	.ascii	"ARM\x64"		/* magic */
	.long	0			/* res5 */

entry:
	mov	x19, x0			/* ABL's DTB */
	adr	x20, _start		/* our load address */
	add	x9, x20, #(SHIM_STACK_TOP >> 12), lsl #12
	mov	sp, x9

	mov	x0, x19
	mov	x1, x20
	bl	shim_main		/* returns merged DTB or NULL */
	cbz	x0, fail
	mov	x21, x0

#ifdef SHIM_DEBUG_OFF
	/* Debug build: merge worked, power off instead of entering Linux */
	movz	x0, #0x0008		/* PSCI SYSTEM_OFF */
	movk	x0, #0x8400, lsl #16
	smc	#0
#endif

	add	x9, x20, #(SHIM_KERNEL_OFF >> 12), lsl #12
	mov	x0, x21			/* x0 = DTB, x1-x3 = 0 per boot protocol */
	mov	x1, xzr
	mov	x2, xzr
	mov	x3, xzr
	br	x9

fail:
	movz	x0, #0x0009		/* PSCI SYSTEM_RESET */
	movk	x0, #0x8400, lsl #16
	smc	#0
1:	wfe
	b	1b
