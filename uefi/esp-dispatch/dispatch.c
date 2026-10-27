// SPDX-License-Identifier: MIT
/*
 * \EFI\BOOT\BOOTAA64.EFI on the NX809J's ESP.
 *
 * Started by the phone's own Qualcomm UEFI (superfastboot's "Boot to ESP"),
 * it loads Mu-Silicium's firmware image \nx809j\mu\MU.fd, leaves UEFI and
 * starts it the way Mu's boot shim does after ABL: copied to its link
 * address with the MMU and D-cache off. Mu's own boot manager then starts
 * this file again; under Mu it hands over to systemd-boot.
 *
 * So Android stays on boot_a and boots straight from ABL, and Linux runs on
 * Mu instead of the stock UEFI.
 *
 * ABL's "Boot to ESP" registers an ExitBootServices callback that powers the
 * display off. Mu then brings the panel up cold, and Linux's display
 * glitches. An ABL kernel boot keeps the panel running instead, so before
 * leaving UEFI this replaces the display power protocol's SetDisplayPowerState
 * with one that does nothing.
 */
#include "../include/efi-mini.h"

#define MU_FD_BASE  0xC6900000ULL  /* FD_BASE in uefi/nx809j.toml */
#define MU_FD_SIZE  0x300000ULL

/* QcomPkg EFIDisplayPwr.h */
static const guid display_power_guid =
	{ 0xf352021d, 0x9593, 0x4432, { 0xbf, 0x04, 0x67, 0xb9, 0xf3, 0xb7, 0x60, 0x08 } };

typedef struct {
	u32 rev;
	status (*set_state)(void *, u32);
	status (*get_state)(void *, u32 *);
} display_power;

static status keep_display_on(void *this, u32 state)
{
	(void)this;
	(void)state;
	return EFI_SUCCESS;
}

static const u16 mu_path[] = u"\\nx809j\\mu\\MU.fd";
static const u16 sdboot_path[] = u"\\EFI\\systemd\\systemd-bootaa64.efi";

/* Whether the firmware vendor string contains word */
static int vendor_has(const char *word)
{
	const u16 *v = ST->vendor;
	uintn i, j;

	for (i = 0; v && v[i]; i++) {
		for (j = 0; word[j] && v[i + j] == (u8)word[j]; j++)
			;
		if (!word[j])
			return 1;
	}
	return 0;
}

static int overlaps(u64 a, u64 alen, u64 b, u64 blen)
{
	return a < b + blen && b < a + alen;
}

static status start_systemd_boot(handle img, loaded_image *li)
{
	boot_services *bs = ST->bs;
	const u8 *dev;
	u8 *dp;
	uintn dev_len = 0, plen = sizeof(sdboot_path), n;
	handle child;
	status s;

	/* Device path of our volume + file node, so systemd-boot finds the ESP */
	s = bs->handle_protocol(li->device, &device_path_guid, (void **)&dev);
	if (s)
		return s;
	while (!(dev[dev_len] == 0x7f && dev[dev_len + 1] == 0xff))
		dev_len += dev[dev_len + 2] | dev[dev_len + 3] << 8;
	n = dev_len + 4 + plen + 4;
	s = bs->alloc_pool(4, n, (void **)&dp);
	if (s)
		return s;
	memcpy(dp, dev, dev_len);
	dp[dev_len] = 4;		/* media */
	dp[dev_len + 1] = 4;		/* file path */
	dp[dev_len + 2] = (4 + plen) & 0xff;
	dp[dev_len + 3] = (4 + plen) >> 8;
	memcpy(dp + dev_len + 4, sdboot_path, plen);
	memcpy(dp + dev_len + 4 + plen, "\x7f\xff\x04\x00", 4);

	s = bs->load_image(0, img, dp, 0, 0, &child);
	if (s)
		return s;
	return bs->start_image(child, 0, 0);
}

static status start_mu(handle img, loaded_image *li, file *root)
{
	void *fd;
	u64 size;
	status s;

	s = read_file(root, mu_path, &fd, &size);
	if (s) {
		print_hex("Could not read \\nx809j\\mu\\MU.fd: ", s);
		return s;
	}
	if (size != MU_FD_SIZE) {
		print_hex("MU.fd has the wrong size: ", size);
		return EFI_LOAD_ERROR;
	}
	/* The copy runs from this program, so it must not sit where Mu goes */
	if (overlaps((u64)li->base, li->size, MU_FD_BASE, MU_FD_SIZE)) {
		print_hex("This program is loaded inside Mu's range at ", (u64)li->base);
		return EFI_LOAD_ERROR;
	}
	{
		display_power *dp;

		if (!ST->bs->locate_protocol(&display_power_guid, 0, (void **)&dp)) {
			dp->set_state = keep_display_on;
			print("Display stays on for Mu\n");
		} else {
			print("No display power protocol; the display may go off\n");
		}
	}
	print("Starting Mu-Silicium\n");
	ST->bs->stall(500000);

	s = exit_boot_services(img);
	if (s)
		return s;
	/* memmove: the buffer may overlap the destination */
	if ((u64)fd > MU_FD_BASE) {
		u64 *d = (u64 *)MU_FD_BASE, *p = fd;
		uintn i;
		for (i = 0; i < MU_FD_SIZE / 8; i++)
			d[i] = p[i];
	} else {
		u64 *d = (u64 *)MU_FD_BASE, *p = fd;
		uintn i;
		for (i = MU_FD_SIZE / 8; i--; )
			d[i] = p[i];
	}
	flush_range(MU_FD_BASE, MU_FD_BASE + MU_FD_SIZE);
	flush_range((u64)li->base, (u64)li->base + li->size);
	start_kernel(MU_FD_BASE, 0);
}

status efi_main(handle img, system_table *st)
{
	loaded_image *li;
	file *root;
	status s;

	ST = st;
	s = open_root(img, &root, &li);
	if (s) {
		print_hex("Could not open the ESP: ", s);
		st->bs->stall(5000000);
		return s;
	}
	if (vendor_has("Qualcomm"))
		s = start_mu(img, li, root);	/* returns only on failure */
	else
		s = start_systemd_boot(img, li);
	if (s) {
		print_hex("Boot failed: ", s);
		st->bs->stall(5000000);
	}
	return s;
}
