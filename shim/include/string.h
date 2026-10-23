/* SPDX-License-Identifier: GPL-2.0 */
/* Freestanding string.h for libfdt; implemented in shim.c */
#ifndef SHIM_STRING_H
#define SHIM_STRING_H
#include <stddef.h>

void *memcpy(void *dst, const void *src, size_t n);
void *memmove(void *dst, const void *src, size_t n);
void *memset(void *dst, int c, size_t n);
int memcmp(const void *a, const void *b, size_t n);
void *memchr(const void *s, int c, size_t n);
size_t strlen(const char *s);
size_t strnlen(const char *s, size_t max);
char *strrchr(const char *s, int c);

#endif
