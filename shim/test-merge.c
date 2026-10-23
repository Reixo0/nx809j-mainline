// SPDX-License-Identifier: GPL-2.0
/*
 * Host test for shim_merge(): feed it the downstream DTB ABL passed to
 * Android (dump/runtime/live.dtb) and our mainline DTB, write the result.
 * Usage: test-merge <abl.dtb> <ours.dtb> <out.dtb>
 */
#include <stdio.h>
#include <stdlib.h>
#include <libfdt.h>

void *shim_merge(const void *abl, const void *ours, void *out, size_t out_max);

static void *slurp(const char *path)
{
	FILE *f = fopen(path, "rb");
	long n;
	void *buf;

	if (!f || fseek(f, 0, SEEK_END) || (n = ftell(f)) < 0)
		exit(1);
	rewind(f);
	buf = malloc(n);
	if (!buf || fread(buf, 1, n, f) != (size_t)n)
		exit(1);
	fclose(f);
	return buf;
}

int main(int argc, char **argv)
{
	static char out[0x100000];
	void *res;
	FILE *f;

	if (argc != 4)
		return 2;
	res = shim_merge(slurp(argv[1]), slurp(argv[2]), out, sizeof(out));
	if (!res) {
		fprintf(stderr, "shim_merge failed\n");
		return 1;
	}
	f = fopen(argv[3], "wb");
	fwrite(out, 1, fdt_totalsize(out), f);
	fclose(f);
	printf("merged: %u bytes\n", fdt_totalsize(out));
	return 0;
}
