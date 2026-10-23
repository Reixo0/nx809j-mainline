/* SPDX-License-Identifier: GPL-2.0 */
ENTRY(_start)
SECTIONS
{
	. = 0;
	.text : { *(.text.head) *(.text .text.*) }
	.rodata : { *(.rodata .rodata.*) }
	.data : { *(.data .data.*) }
	.bss : { *(.bss .bss.*) *(COMMON) }
	/DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.ARM.*) }
}
