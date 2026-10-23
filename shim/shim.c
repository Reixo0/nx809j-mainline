// SPDX-License-Identifier: GPL-2.0
/*
 * NX809J boot shim: build the DTB Linux boots with.
 *
 * Start from our embedded mainline DTB and copy in what ABL fills in at
 * boot time into the downstream DTB it passes us:
 *   - /memory "reg"       (our DTS leaves the size for the bootloader)
 *   - /chosen initrd range, kaslr-seed, rng-seed
 *   - /chosen bootargs    (only if our DTB doesn't carry its own)
 *
 * Built twice: freestanding for the phone, and with SHIM_HOST for the
 * host-side test (shim/test-merge.c).
 */
#include <libfdt.h>

#include "layout.h"

#ifndef SHIM_HOST
/*
 * libc subset needed by libfdt. Byte-wise on purpose: we run with the MMU
 * off, where memory is Device type and unaligned accesses fault.
 */
void *memcpy(void *dst, const void *src, size_t n)
{
	unsigned char *d = dst;
	const unsigned char *s = src;

	while (n--)
		*d++ = *s++;
	return dst;
}

void *memmove(void *dst, const void *src, size_t n)
{
	unsigned char *d = dst;
	const unsigned char *s = src;

	if (d < s) {
		while (n--)
			*d++ = *s++;
	} else {
		while (n--)
			d[n] = s[n];
	}
	return dst;
}

void *memset(void *dst, int c, size_t n)
{
	unsigned char *d = dst;

	while (n--)
		*d++ = (unsigned char)c;
	return dst;
}

int memcmp(const void *a, const void *b, size_t n)
{
	const unsigned char *x = a, *y = b;

	for (; n; n--, x++, y++)
		if (*x != *y)
			return *x - *y;
	return 0;
}

void *memchr(const void *s, int c, size_t n)
{
	const unsigned char *p = s;

	for (; n; n--, p++)
		if (*p == (unsigned char)c)
			return (void *)p;
	return NULL;
}

size_t strlen(const char *s)
{
	const char *p = s;

	while (*p)
		p++;
	return p - s;
}

size_t strnlen(const char *s, size_t max)
{
	size_t n = 0;

	while (n < max && s[n])
		n++;
	return n;
}

char *strrchr(const char *s, int c)
{
	const char *last = NULL;

	do {
		if (*s == (char)c)
			last = s;
	} while (*s++);
	return (char *)last;
}
#endif /* !SHIM_HOST */

static int copy_prop(void *out, int onode, const void *abl, int anode,
		     const char *name)
{
	const void *val;
	int len;

	val = fdt_getprop(abl, anode, name, &len);
	if (!val)
		return len == -FDT_ERR_NOTFOUND ? 0 : len;
	return fdt_setprop(out, onode, name, val, len);
}

static int find_memory(const void *fdt)
{
	return fdt_node_offset_by_prop_value(fdt, -1, "device_type",
					     "memory", sizeof("memory"));
}

/*
 * No pointer tables anywhere in the shim: it isn't relocated, so any
 * absolute address stored in data would be wrong. String literals passed
 * directly are fine (PC-relative adrp/add).
 */
void *shim_merge(const void *abl, const void *ours, void *out, size_t out_max)
{
	int am, om, ac, oc;

	if (fdt_check_header(abl) || fdt_check_header(ours))
		return NULL;
	if (fdt_open_into(ours, out, out_max))
		return NULL;

	/* /memory: the reg cells must mean the same thing in both trees */
	if (fdt_address_cells(abl, 0) != fdt_address_cells(out, 0) ||
	    fdt_size_cells(abl, 0) != fdt_size_cells(out, 0))
		return NULL;
	am = find_memory(abl);
	om = find_memory(out);
	if (am < 0 || om < 0 || !fdt_getprop(abl, am, "reg", NULL))
		return NULL;
	if (copy_prop(out, om, abl, am, "reg"))
		return NULL;

	/* /chosen: look it up only now, the setprop above may move nodes */
	ac = fdt_path_offset(abl, "/chosen");
	oc = fdt_path_offset(out, "/chosen");
	if (oc < 0)
		oc = fdt_add_subnode(out, 0, "chosen");
	if (oc < 0)
		return NULL;
	if (ac >= 0) {
		if (copy_prop(out, oc, abl, ac, "linux,initrd-start") ||
		    copy_prop(out, oc, abl, ac, "linux,initrd-end") ||
		    copy_prop(out, oc, abl, ac, "kaslr-seed") ||
		    copy_prop(out, oc, abl, ac, "rng-seed"))
			return NULL;
		if (!fdt_getprop(out, oc, "bootargs", NULL) &&
		    copy_prop(out, oc, abl, ac, "bootargs"))
			return NULL;
	}

	if (fdt_pack(out))
		return NULL;
	return out;
}

void *shim_main(const void *abl, char *base)
{
	return shim_merge(abl, base + SHIM_DTB_OFF, base + SHIM_OUT_OFF,
			  SHIM_OUT_MAX);
}
