/* SPDX-License-Identifier: GPL-2.0 */
/*
 * Memory layout of the shim image, as offsets from where ABL loads it
 * (a 2 MiB aligned base, per the arm64 boot protocol):
 *
 *   0x000000  shim header + code          (max 64 KiB)
 *   0x010000  stack                       (grows down from 0x020000)
 *   0x020000  embedded mainline DTB       (max 896 KiB)
 *   0x100000  merged DTB handed to Linux  (max 1 MiB)
 *   0x200000  Linux Image                 (2 MiB aligned, as Linux requires)
 */
#ifndef SHIM_LAYOUT_H
#define SHIM_LAYOUT_H

#define SHIM_CODE_MAX	0x010000
#define SHIM_STACK_TOP	0x020000
#define SHIM_DTB_OFF	0x020000
#define SHIM_OUT_OFF	0x100000
#define SHIM_OUT_MAX	0x100000
#define SHIM_KERNEL_OFF	0x200000

#endif
