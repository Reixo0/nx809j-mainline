// SPDX-License-Identifier: MIT
/*
 * Starts Android from Mu-Silicium on the NX809J.
 *
 * ABL boots Mu's boot_a like an Android boot: it leaves its device tree
 * (dtbo applied, Android's command line in /chosen) and the initrd (vendor
 * and generic ramdisks plus bootconfig) in the "Kernel" region, which Mu
 * keeps reserved. This program loads Android's kernel Image from the ESP,
 * leaves UEFI, puts the kernel where ABL would, and starts it with ABL's
 * device tree, so the kernel sees an ordinary ABL boot.
 *
 * Image path: \nx809j\android\Image on the volume this program is on.
 *
 * With "save-ramoops" as its options it only copies Android's ramoops area
 * (its console log, which Linux's ramoops would wipe if the header got
 * corrupted) to \nx809j\android\ramoops.bin and returns.
 */
#include "../include/efi-mini.h"

/* The region ABL loads the kernel and leaves its device tree and initrd
 * in ("Kernel" in nx809jPkg's MemoryMapLib.c) */
#define ABL_REGION_START 0xC7800000ULL
#define ABL_REGION_END   0xD7800000ULL
/* Where the kernel goes, as ABL would place it */
#define KERNEL_BASE      ABL_REGION_START
/* ramoops in Android's (and our) device tree */
#define RAMOOPS_BASE     0xE2000000ULL
#define RAMOOPS_SIZE     0x200000ULL


/* Whether the initrd ends with a bootconfig trailer */
static int memcmp_bootconfig(u64 rd_end)
{
	const char *magic = "#BOOTCONFIG\n";
	const u8 *t = (const u8 *)(rd_end - 12);
	int i;

	for (i = 0; i < 12; i++)
		if (t[i] != (u8)magic[i])
			return 1;
	return 0;
}

/* A property of the top-level /chosen node */
static const u8 *chosen_prop(const u8 *fdt, const char *name, u32 *len)
{
	const u8 *st = fdt + be32(fdt + 8);
	const char *strs = (const char *)fdt + be32(fdt + 12);
	u32 size = be32(fdt + 36), off = 0;
	int depth = 0, in_chosen = 0;

	while (off + 4 <= size) {
		u32 tag = be32(st + off);
		off += 4;
		if (tag == 1) {
			const char *n = (const char *)st + off;
			depth++;
			if (depth == 2 && streq(n, "chosen"))
				in_chosen = 1;
			off += (strlen(n) + 4) & ~3U;
		} else if (tag == 2) {
			if (depth == 2)
				in_chosen = 0;
			depth--;
		} else if (tag == 3) {
			u32 plen = be32(st + off), noff = be32(st + off + 4);
			if (in_chosen && depth == 2 && streq(strs + noff, name)) {
				*len = plen;
				return st + off + 8;
			}
			off += 8 + ((plen + 3) & ~3U);
		} else if (tag == 9) {
			break;
		} else if (tag != 4) {
			break;
		}
	}
	return 0;
}

static u64 cell(const u8 *p, u32 len)
{
	return len == 8 ? (u64)be32(p) << 32 | be32(p + 4) : be32(p);
}

/* ABL's device tree: the one in its region that names an initrd */
static const u8 *find_abl_dt(u64 *rd_start, u64 *rd_end)
{
	u64 pa;

	for (pa = ABL_REGION_START; pa < ABL_REGION_END; pa += 0x1000) {
		const u8 *fdt = (const u8 *)pa;
		const u8 *p;
		u32 len;

		if (be32(fdt) != 0xd00dfeed || be32(fdt + 4) > 0x400000)
			continue;
		p = chosen_prop(fdt, "linux,initrd-start", &len);
		if (!p)
			continue;
		*rd_start = cell(p, len);
		p = chosen_prop(fdt, "linux,initrd-end", &len);
		if (!p)
			continue;
		*rd_end = cell(p, len);
		return fdt;
	}
	return 0;
}


static status save_ramoops(file *root)
{
	file *f;
	status s;
	uintn n = RAMOOPS_SIZE;

	/* Replace any earlier copy */
	if (!root->open(root, &f, u"\\nx809j\\android\\ramoops.bin", 3, 0))
		f->del(f);
	s = root->open(root, &f, u"\\nx809j\\android\\ramoops.bin",
		       0x8000000000000003ULL, 0);
	if (s)
		return s;
	s = f->write(f, &n, (const void *)RAMOOPS_BASE);
	f->flush(f);
	f->close(f);
	return s;
}

static status read_image(handle img, void **buf, u64 *size)
{
	boot_services *bs = ST->bs;
	loaded_image *li;
	fs *vol;
	file *root, *f;
	status s;
	uintn n;

	s = bs->handle_protocol(img, &loaded_image_guid, (void **)&li);
	if (s)
		return s;
	s = bs->handle_protocol(li->device, &simple_fs_guid, (void **)&vol);
	if (s)
		return s;
	s = vol->open_volume(vol, &root);
	if (s)
		return s;
	s = root->open(root, &f, u"\\nx809j\\android\\Image", 1, 0);
	if (s)
		return s;
	f->set_pos(f, ~0ULL);
	f->get_pos(f, size);
	f->set_pos(f, 0);
	s = bs->alloc_pool(4 /* EfiLoaderData */, *size, buf);
	if (s)
		return s;
	n = *size;
	s = f->read(f, &n, *buf);
	f->close(f);
	if (!s && n != *size)
		s = EFI_LOAD_ERROR;
	return s;
}


status efi_main(handle img, system_table *st)
{
	boot_services *bs = st->bs;
	const u8 *dt;
	u64 rd_start, rd_end, size, image_size, kend;
	void *kernel;
	uintn map_size, key, dsize;
	u32 dver;
	mem_desc *map = 0;
	loaded_image *li;
	status s;
	int tries;

	ST = st;
	print("NX809J Android loader\n");

	{
		file *root;

		s = open_root(img, &root, &li);
		if (s) {
			print_hex("Could not open the ESP: ", s);
			bs->stall(5000000);
			return s;
		}
		if (has_option(li, "save-ramoops")) {
			s = save_ramoops(root);
			if (s)
				print_hex("Saving ramoops failed: ", s);
			else
				print("Saved Android's ramoops to \\nx809j\\android\\ramoops.bin\n");
			bs->stall(3000000);
			return s;
		}
	}

	dt = find_abl_dt(&rd_start, &rd_end);
	if (!dt) {
		print("No device tree from ABL found; was this boot started by ABL?\n");
		bs->stall(5000000);
		return EFI_NOT_FOUND;
	}
	print_hex("Device tree:  ", (u64)dt);
	print_hex("Initrd start: ", rd_start);
	print_hex("Initrd end:   ", rd_end);
	if (rd_end - rd_start < 12 || memcmp_bootconfig(rd_end))
		print("Warning: no bootconfig at the end of the initrd\n");

	s = read_image(img, &kernel, &size);
	if (s) {
		print_hex("Could not read \\nx809j\\android\\Image: ", s);
		bs->stall(5000000);
		return s;
	}
	image_size = *(u64 *)((u8 *)kernel + 16);
	if (*(u32 *)((u8 *)kernel + 0x38) != 0x644d5241 || !image_size) {
		print("\\nx809j\\android\\Image is not an arm64 kernel Image\n");
		bs->stall(5000000);
		return EFI_LOAD_ERROR;
	}
	kend = KERNEL_BASE + *(u64 *)((u8 *)kernel + 8) + image_size;
	print_hex("Kernel size:  ", size);
	print_hex("Kernel end:   ", kend);
	if (kend > (u64)dt || kend > rd_start || kend > ABL_REGION_END) {
		print("Kernel would overlap the device tree or initrd\n");
		bs->stall(5000000);
		return EFI_LOAD_ERROR;
	}
	bs->handle_protocol(img, &loaded_image_guid, (void **)&li);

	print("Starting Android\n");
	bs->stall(1000000);

	for (tries = 0; tries < 5; tries++) {
		map_size = 0;
		s = bs->get_memory_map(&map_size, map, &key, &dsize, &dver);
		if (s == EFI_BUFFER_TOO_SMALL) {
			if (map)
				bs->free_pool(map);
			map_size += 8 * sizeof(mem_desc);
			if (bs->alloc_pool(4, map_size, (void **)&map))
				break;
			s = bs->get_memory_map(&map_size, map, &key, &dsize, &dver);
		}
		if (s)
			continue;
		if (!bs->exit_boot_services(img, key))
			goto out;
	}
	print("ExitBootServices failed\n");
	return EFI_LOAD_ERROR;

out:
	/* No UEFI from here on. The kernel goes to the start of ABL's
	 * region (flags bit 3: any 2 MiB aligned address works). */
	memcpy((void *)(KERNEL_BASE + *(u64 *)((u8 *)kernel + 8)), kernel, size);
	flush_range(KERNEL_BASE, kend);
	flush_range((u64)dt, (u64)dt + be32(dt + 4));
	flush_range(rd_start, rd_end);
	flush_range((u64)li->base, (u64)li->base + li->size);
	start_kernel(KERNEL_BASE + *(u64 *)((u8 *)kernel + 8), (u64)dt);
}
