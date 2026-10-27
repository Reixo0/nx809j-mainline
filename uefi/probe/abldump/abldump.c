// SPDX-License-Identifier: GPL-2.0
/*
 * Exposes what ABL left in memory for Mu (device tree and initrd, see
 * uefi/probe/AblProbe.c) as debugfs files. Mu keeps that memory reserved,
 * and the kernel won't let /dev/mem read it.
 *
 *   insmod abldump.ko dtb=0x... initrd_start=0x... initrd_end=0x...
 *   /sys/kernel/debug/abldump/{dtb,initrd}
 *
 * Without dtb=, it logs where device trees start in scan_start..scan_end
 * (page aligned) and fails to load.
 */
#include <linux/debugfs.h>
#include <linux/io.h>
#include <linux/module.h>

static unsigned long dtb, initrd_start, initrd_end;
module_param(dtb, ulong, 0444);
module_param(initrd_start, ulong, 0444);
module_param(initrd_end, ulong, 0444);

static unsigned long scan_start = 0xc7800000, scan_end = 0xd7800000;
module_param(scan_start, ulong, 0444);
module_param(scan_end, ulong, 0444);

static struct dentry *dir;
static void *dtb_va, *initrd_va;
static struct debugfs_blob_wrapper dtb_blob, initrd_blob;

static int abldump_scan(void)
{
	unsigned long pa;
	u8 *va;

	for (pa = scan_start; pa < scan_end; pa += SZ_1M) {
		unsigned long off;

		va = memremap(pa, SZ_1M, MEMREMAP_WB);
		if (!va)
			return -ENOMEM;
		for (off = 0; off < SZ_1M; off += PAGE_SIZE)
			if (be32_to_cpup((__be32 *)(va + off)) == 0xd00dfeed)
				pr_info("abldump: device tree at %#lx, size %#x\n",
					pa + off, be32_to_cpup((__be32 *)(va + off + 4)));
		memunmap(va);
	}
	return -EAGAIN;
}

static int __init abldump_init(void)
{
	if (!dtb)
		return abldump_scan();
	if (!initrd_start || initrd_end <= initrd_start)
		return -EINVAL;

	/* The device tree header gives its size (big endian, offset 4) */
	dtb_va = memremap(dtb, PAGE_SIZE, MEMREMAP_WB);
	if (!dtb_va)
		return -ENOMEM;
	if (be32_to_cpup(dtb_va) != 0xd00dfeed) {
		memunmap(dtb_va);
		return -ENODATA;
	}
	dtb_blob.size = be32_to_cpup(dtb_va + 4);
	memunmap(dtb_va);
	dtb_va = memremap(dtb, dtb_blob.size, MEMREMAP_WB);
	initrd_blob.size = initrd_end - initrd_start;
	initrd_va = memremap(initrd_start, initrd_blob.size, MEMREMAP_WB);
	if (!dtb_va || !initrd_va) {
		if (dtb_va)
			memunmap(dtb_va);
		if (initrd_va)
			memunmap(initrd_va);
		return -ENOMEM;
	}
	dtb_blob.data = dtb_va;
	initrd_blob.data = initrd_va;

	dir = debugfs_create_dir("abldump", NULL);
	debugfs_create_blob("dtb", 0400, dir, &dtb_blob);
	debugfs_create_blob("initrd", 0400, dir, &initrd_blob);
	return 0;
}

static void __exit abldump_exit(void)
{
	debugfs_remove_recursive(dir);
	memunmap(dtb_va);
	memunmap(initrd_va);
}

module_init(abldump_init);
module_exit(abldump_exit);
MODULE_DESCRIPTION("Read ABL's device tree and initrd left behind for UEFI");
MODULE_LICENSE("GPL");
