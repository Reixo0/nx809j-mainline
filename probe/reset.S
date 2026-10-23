/*
 * Minimal arm64 "kernel" that reboots the phone as soon as it gets control.
 * Answers one question: does `fastboot boot` via superfastboot ever reach
 * the kernel entry point? (immediate reboot = yes, logo hang = no)
 *
 * Laid out as a standard arm64 Image (Documentation/arch/arm64/booting.rst)
 * so ABL's header checks pass.
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
	/* PSCI SYSTEM_RESET via SMC, the conduit the DT declares */
	movz	x0, #0x0009
	movk	x0, #0x8400, lsl #16
	smc	#0
	/* Fallback if the call returns: SYSTEM_OFF never, just spin */
1:	wfe
	b	1b

	.balign	4096
image_end:
