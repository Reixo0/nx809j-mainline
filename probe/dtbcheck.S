/*
 * Boot-path probe for the NX809J, meant to be flashed to boot_a.
 *
 * Checks which DTB ABL handed over in x0 and signals the result:
 *   - phone powers OFF  -> the DTB contains NEEDLE (default "nubia,nx809j",
 *                          i.e. our mainline DTB; build with
 *                          -DNEEDLE='"qcom,canoe"' to detect the downstream one)
 *   - phone REBOOTS     -> kernel entry reached, but with another DTB
 *                          (downstream one from vendor_boot) or none
 *   - stuck on logo     -> control never reached the kernel entry
 *
 * Laid out as a standard arm64 Image (Documentation/arch/arm64/booting.rst).
 * Entry runs with the MMU off, so only aligned word loads and byte loads.
 */
	.section .text
	.global _start
_start:
	b	entry			/* code0 */
	.long	0			/* code1 */
	.quad	0			/* text_offset */
	.quad	image_end - _start	/* image_size */
	.quad	0xa			/* flags: LE, 4K pages, place anywhere */
	.quad	0, 0, 0			/* res2-4 */
	.ascii	"ARM\x64"		/* magic */
	.long	0			/* res5 */

entry:
	cbz	x0, reset		/* no DTB at all */
	tst	x0, #7
	b.ne	reset			/* misaligned: not a valid DTB pointer */

	/* FDT magic 0xd00dfeed, stored big-endian */
	ldr	w1, [x0]
	rev	w1, w1
	movz	w2, #0xfeed
	movk	w2, #0xd00d, lsl #16
	cmp	w1, w2
	b.ne	reset

	/* Scan totalsize bytes for the needle */
	ldr	w3, [x0, #4]
	rev	w3, w3
	add	x4, x0, x3		/* end of blob */
	adr	x5, needle
	mov	x6, x0			/* cursor */
scan:
	cmp	x6, x4
	b.hs	reset
	mov	x7, #0
cmp_byte:
	ldrb	w8, [x6, x7]
	ldrb	w9, [x5, x7]
	cmp	w8, w9
	b.ne	next
	add	x7, x7, #1
	cmp	x7, #(needle_end - needle)
	b.lo	cmp_byte
	b	poweroff
next:
	add	x6, x6, #1
	b	scan

poweroff:
	movz	x0, #0x0008		/* PSCI SYSTEM_OFF */
	movk	x0, #0x8400, lsl #16
	smc	#0
	b	hang
reset:
	movz	x0, #0x0009		/* PSCI SYSTEM_RESET */
	movk	x0, #0x8400, lsl #16
	smc	#0
hang:
	wfe
	b	hang

#ifndef NEEDLE
#define NEEDLE "nubia,nx809j"
#endif
needle:
	.ascii	NEEDLE
needle_end:

	.balign	4096
image_end:
