// SPDX-License-Identifier: MIT
/*
 * Just enough UEFI for the NX809J's small EFI programs (no SDK): types,
 * protocols, console output, file reading and the Linux-style hand-off
 * (MMU and D-cache off, jump with x0).
 */
#pragma once

typedef unsigned char u8;
typedef unsigned short u16;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef u64 uintn;
typedef uintn status;
typedef void *handle;

#define EFI_SUCCESS 0
#define EFI_ERR(n) (0x8000000000000000ULL | (n))
#define EFI_BUFFER_TOO_SMALL EFI_ERR(5)
#define EFI_NOT_FOUND EFI_ERR(14)
#define EFI_LOAD_ERROR EFI_ERR(1)
#define EFI_INVALID_PARAMETER EFI_ERR(2)

typedef struct { u32 a; u16 b, c; u8 d[8]; } guid;
typedef struct { u64 sig; u32 rev, size, crc, res; } table_header;

typedef struct text_out {
	status (*reset)(struct text_out *, int);
	status (*output)(struct text_out *, const u16 *);
} text_out;

typedef struct {
	u32 type, pad;
	u64 phys, virt, pages, attr;
} mem_desc;

typedef struct {
	table_header hdr;
	void *raise_tpl, *restore_tpl;
	status (*alloc_pages)(int, int, uintn, u64 *);
	void *free_pages;
	status (*get_memory_map)(uintn *, mem_desc *, uintn *, uintn *, u32 *);
	status (*alloc_pool)(int, uintn, void **);
	status (*free_pool)(void *);
	void *create_event, *set_timer, *wait_for_event, *signal_event,
	     *close_event, *check_event, *install_proto, *reinstall_proto,
	     *uninstall_proto;
	status (*handle_protocol)(handle, const guid *, void **);
	void *reserved, *register_notify, *locate_handle, *locate_dp,
	     *install_config;
	status (*load_image)(u8, handle, const void *, void *, uintn, handle *);
	status (*start_image)(handle, uintn *, u16 **);
	void *exit, *unload_image;
	status (*exit_boot_services)(handle, uintn);
	void *next_count;
	status (*stall)(uintn);
	void *set_watchdog_timer, *connect_controller, *disconnect_controller,
	     *open_protocol, *close_protocol, *open_protocol_info,
	     *protocols_per_handle, *locate_handle_buffer;
	status (*locate_protocol)(const guid *, void *, void **);
} boot_services;

typedef struct {
	table_header hdr;
	u16 *vendor;
	u32 vendor_rev, pad;
	handle con_in_h; void *con_in;
	handle con_out_h; text_out *con_out;
	handle err_h; void *err;
	void *runtime;
	boot_services *bs;
} system_table;

typedef struct {
	u32 rev, pad;
	handle parent;
	system_table *st;
	handle device;
	void *path, *reserved;
	u32 options_size, pad2;
	void *options;
	void *base;
	u64 size;
} loaded_image;

typedef struct file {
	u64 rev;
	status (*open)(struct file *, struct file **, const u16 *, u64, u64);
	status (*close)(struct file *);
	status (*del)(struct file *);
	status (*read)(struct file *, uintn *, void *);
	status (*write)(struct file *, uintn *, const void *);
	status (*get_pos)(struct file *, u64 *);
	status (*set_pos)(struct file *, u64);
	void *get_info, *set_info;
	status (*flush)(struct file *);
} file;

typedef struct fs {
	u64 rev;
	status (*open_volume)(struct fs *, file **);
} fs;

static const guid loaded_image_guid =
	{ 0x5B1B31A1, 0x9562, 0x11d2, { 0x8E, 0x3F, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B } };
static const guid simple_fs_guid =
	{ 0x964E5B22, 0x6459, 0x11d2, { 0x8E, 0x39, 0x00, 0xA0, 0xC9, 0x69, 0x72, 0x3B } };

static const guid device_path_guid __attribute__((unused)) =
	{ 0x09576e91, 0x6d3f, 0x11d2, { 0x8e, 0x39, 0x00, 0xa0, 0xc9, 0x69, 0x72, 0x3b } };

static system_table *ST;

void *memcpy(void *d, const void *s, uintn n)
{
	u8 *dp = d;
	const u8 *sp = s;

	if (!(((uintn)d | (uintn)s | n) & 7)) {
		u64 *dq = d;
		const u64 *sq = s;
		for (n /= 8; n--; )
			*dq++ = *sq++;
		return d;
	}
	while (n--)
		*dp++ = *sp++;
	return d;
}

void *memset(void *d, int c, uintn n)
{
	u8 *dp = d;

	while (n--)
		*dp++ = c;
	return d;
}

static __attribute__((unused)) void print(const char *s)
{
	u16 buf[160];
	int i = 0;

	while (*s) {
		if (*s == '\n')
			buf[i++] = '\r';
		buf[i++] = (u8)*s++;
		if (i >= 156 || !*s) {
			buf[i] = 0;
			ST->con_out->output(ST->con_out, buf);
			i = 0;
		}
	}
}

static __attribute__((unused)) void print_hex(const char *label, u64 v)
{
	char buf[19] = "0x";
	int i;

	for (i = 0; i < 16; i++)
		buf[2 + i] = "0123456789abcdef"[(v >> (60 - 4 * i)) & 0xf];
	buf[18] = 0;
	print(label);
	print(buf);
	print("\n");
}

static __attribute__((unused)) u32 be32(const void *p)
{
	const u8 *b = p;
	return (u32)b[0] << 24 | (u32)b[1] << 16 | (u32)b[2] << 8 | b[3];
}

static __attribute__((unused)) int streq(const char *a, const char *b)
{
	while (*a && *a == *b) {
		a++;
		b++;
	}
	return *a == *b;
}

static __attribute__((unused)) uintn strlen(const char *s)
{
	uintn n = 0;
	while (s[n])
		n++;
	return n;
}

static __attribute__((unused)) status open_root(handle img, file **root, loaded_image **li)
{
	boot_services *bs = ST->bs;
	fs *vol;
	status s;

	s = bs->handle_protocol(img, &loaded_image_guid, (void **)li);
	if (s)
		return s;
	s = bs->handle_protocol((*li)->device, &simple_fs_guid, (void **)&vol);
	if (s)
		return s;
	return vol->open_volume(vol, root);
}

/* Whether the load options (UCS-2) contain word */
static __attribute__((unused)) int has_option(loaded_image *li, const char *word)
{
	const u16 *o = li->options;
	uintn n = li->options_size / 2, i, j;

	for (i = 0; o && i < n; i++) {
		for (j = 0; word[j] && i + j < n && o[i + j] == (u8)word[j]; j++)
			;
		if (!word[j])
			return 1;
	}
	return 0;
}

/* Clean and invalidate [start, end) to the point of coherency */
static __attribute__((unused)) void flush_range(u64 start, u64 end)
{
	u64 ctr, line, a;

	__asm__ volatile("mrs %0, ctr_el0" : "=r"(ctr));
	line = 4ULL << ((ctr >> 16) & 0xf);
	for (a = start & ~(line - 1); a < end; a += line)
		__asm__ volatile("dc civac, %0" :: "r"(a) : "memory");
	__asm__ volatile("dsb sy" ::: "memory");
}

/* Linux arm64 boot protocol: MMU and D-cache off, x0 = device tree */
static __attribute__((unused)) void __attribute__((noreturn)) start_kernel(u64 entry, u64 dt)
{
	__asm__ volatile(
		"mov	x19, %0\n"
		"mov	x20, %1\n"
		"msr	daifset, #0xf\n"
		"mrs	x2, CurrentEL\n"
		"cmp	x2, #8\n"
		"b.eq	1f\n"
		"mrs	x2, sctlr_el1\n"
		"bic	x2, x2, #1\n"		/* M */
		"bic	x2, x2, #4\n"		/* C */
		"msr	sctlr_el1, x2\n"
		"b	2f\n"
		"1:\n"
		"mrs	x2, sctlr_el2\n"
		"bic	x2, x2, #1\n"
		"bic	x2, x2, #4\n"
		"msr	sctlr_el2, x2\n"
		"2:\n"
		"isb\n"
		"ic	iallu\n"
		"dsb	sy\n"
		"isb\n"
		"mov	x0, x20\n"
		"mov	x1, xzr\n"
		"mov	x2, xzr\n"
		"mov	x3, xzr\n"
		"br	x19\n"
		:: "r"(entry), "r"(dt) : "x0", "x1", "x2", "x3", "x19", "x20", "memory");
	__builtin_unreachable();
}

/* Read a whole file from the volume this program was loaded from. */
static __attribute__((unused)) status read_file(file *root, const u16 *path,
						void **buf, u64 *size)
{
	file *f;
	status s;
	uintn n;

	s = root->open(root, &f, path, 1, 0);
	if (s)
		return s;
	f->set_pos(f, ~0ULL);
	f->get_pos(f, size);
	f->set_pos(f, 0);
	s = ST->bs->alloc_pool(4 /* EfiLoaderData */, *size, buf);
	if (!s) {
		n = *size;
		s = f->read(f, &n, *buf);
		if (!s && n != *size)
			s = EFI_LOAD_ERROR;
	}
	f->close(f);
	return s;
}

/* ExitBootServices, retrying while the memory map changes under us. */
static __attribute__((unused)) status exit_boot_services(handle img)
{
	boot_services *bs = ST->bs;
	mem_desc *map = 0;
	uintn map_size, key, dsize;
	u32 dver;
	status s = EFI_LOAD_ERROR;
	int tries;

	for (tries = 0; tries < 5; tries++) {
		map_size = 0;
		s = bs->get_memory_map(&map_size, map, &key, &dsize, &dver);
		if (s == EFI_BUFFER_TOO_SMALL) {
			if (map)
				bs->free_pool(map);
			map_size += 8 * sizeof(mem_desc);
			if (bs->alloc_pool(4, map_size, (void **)&map))
				return EFI_LOAD_ERROR;
			s = bs->get_memory_map(&map_size, map, &key, &dsize, &dver);
		}
		if (s)
			continue;
		s = bs->exit_boot_services(img, key);
		if (!s)
			return 0;
	}
	return s;
}
