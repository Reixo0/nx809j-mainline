/*
 * Boot-path probe: power off as soon as we get control, nothing else.
 *   - phone powers OFF -> ABL's normal boot path reaches the kernel entry
 *   - boot loop / hang -> it never gets here
 * Unplug USB before booting it, or the phone goes to off-mode charging.
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
	movz	x0, #0x0008		/* PSCI SYSTEM_OFF */
	movk	x0, #0x8400, lsl #16
	smc	#0
1:	wfe
	b	1b

	.balign	4096
image_end:
