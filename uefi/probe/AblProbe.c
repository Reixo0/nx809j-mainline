#include <Library/BaseLib.h>

/*
 * ABL hand-off probe, compiled into Sec.c by build.sh when ABL_PROBE=1.
 *
 * The boot shim stores what ABL passed to the "kernel" at ABL_PROBE_BASE:
 * x0 (device tree), x1, x2, x3 and the shim's own load address. This prints
 * them on the screen with what the device tree says about the ramdisk and
 * bootconfig, then waits so the screen can be photographed.
 */
#define ABL_PROBE_BASE  0xC6800000ULL  /* FD_Reserved, untouched until DXE */
#define ABL_PROBE_WAIT  20             /* seconds */

STATIC UINT32 ProbeBe32 (CONST VOID *P)
{
  CONST UINT8 *B = P;
  return ((UINT32)B[0] << 24) | ((UINT32)B[1] << 16) | ((UINT32)B[2] << 8) | B[3];
}

STATIC UINT64 ProbeBe64 (CONST VOID *P)
{
  return ((UINT64)ProbeBe32 (P) << 32) | ProbeBe32 ((CONST UINT8 *)P + 4);
}

STATIC BOOLEAN ProbeStrEq (CONST CHAR8 *A, CONST CHAR8 *B)
{
  while (*A != 0 && *A == *B) { A++; B++; }
  return *A == *B;
}

/* Value of a /chosen property (only a top-level "chosen" node is searched). */
STATIC CONST UINT8 *ProbeChosenProp (CONST UINT8 *Fdt, CONST CHAR8 *Name, UINT32 *Len)
{
  CONST UINT8  *Struct  = Fdt + ProbeBe32 (Fdt + 8);
  CONST CHAR8  *Strings = (CONST CHAR8 *)Fdt + ProbeBe32 (Fdt + 12);
  UINT32        Size    = ProbeBe32 (Fdt + 36);
  UINT32        Off     = 0;
  INTN          Depth   = 0;
  BOOLEAN       InChosen = FALSE;

  while (Off + 4 <= Size) {
    UINT32 Tag = ProbeBe32 (Struct + Off);
    Off += 4;
    if (Tag == 1) {                     /* BEGIN_NODE */
      CONST CHAR8 *NodeName = (CONST CHAR8 *)Struct + Off;
      UINTN        L        = AsciiStrLen (NodeName);
      Depth++;
      if (Depth == 2 && ProbeStrEq (NodeName, "chosen")) {
        InChosen = TRUE;
      }
      Off += (L + 1 + 3) & ~3U;
    } else if (Tag == 2) {              /* END_NODE */
      if (Depth == 2) {
        InChosen = FALSE;
      }
      Depth--;
    } else if (Tag == 3) {              /* PROP */
      UINT32 PLen = ProbeBe32 (Struct + Off);
      UINT32 NOff = ProbeBe32 (Struct + Off + 4);
      if (InChosen && Depth == 2 && ProbeStrEq (Strings + NOff, Name)) {
        *Len = PLen;
        return Struct + Off + 8;
      }
      Off += 8 + ((PLen + 3) & ~3U);
    } else if (Tag == 9) {              /* END */
      break;
    }
  }
  return NULL;
}

STATIC UINT64 ProbeCell (CONST UINT8 *P, UINT32 Len)
{
  return Len == 8 ? ProbeBe64 (P) : ProbeBe32 (P);
}

STATIC VOID AblProbe (VOID)
{
  volatile UINT64 *Saved = (volatile UINT64 *)ABL_PROBE_BASE;
  CONST UINT8     *Fdt   = (CONST UINT8 *)(UINTN)Saved[0];
  CONST UINT8     *P;
  UINT32           Len;
  UINT64           RdStart = 0, RdEnd = 0;

  DEBUG ((EFI_D_WARN, "ABL probe: x0=0x%lx x1=0x%lx x2=0x%lx x3=0x%lx shim=0x%lx\n",
          Saved[0], Saved[1], Saved[2], Saved[3], Saved[4]));

  if (Fdt == NULL || ProbeBe32 (Fdt) != 0xD00DFEED) {
    DEBUG ((EFI_D_WARN, "ABL probe: no device tree at x0\n"));
  } else {
    DEBUG ((EFI_D_WARN, "ABL probe: DT size 0x%x\n", ProbeBe32 (Fdt + 4)));
    P = ProbeChosenProp (Fdt, "linux,initrd-start", &Len);
    if (P != NULL) {
      RdStart = ProbeCell (P, Len);
    }
    P = ProbeChosenProp (Fdt, "linux,initrd-end", &Len);
    if (P != NULL) {
      RdEnd = ProbeCell (P, Len);
    }
    DEBUG ((EFI_D_WARN, "ABL probe: initrd 0x%lx-0x%lx (0x%lx bytes)\n",
            RdStart, RdEnd, RdEnd - RdStart));
    if (RdEnd > RdStart + 12) {
      CONST UINT8 *T = (CONST UINT8 *)(UINTN)RdEnd - 12;
      if (CompareMem (T, "#BOOTCONFIG\n", 12) == 0) {
        /* Trailer: size, checksum (little endian), magic */
        DEBUG ((EFI_D_WARN, "ABL probe: bootconfig 0x%x bytes\n", *(CONST UINT32 *)(T - 8)));
      } else {
        DEBUG ((EFI_D_WARN, "ABL probe: no bootconfig trailer\n"));
      }
      DEBUG ((EFI_D_WARN, "ABL probe: initrd starts %02x %02x %02x %02x %02x %02x\n",
              ((UINT8 *)(UINTN)RdStart)[0], ((UINT8 *)(UINTN)RdStart)[1],
              ((UINT8 *)(UINTN)RdStart)[2], ((UINT8 *)(UINTN)RdStart)[3],
              ((UINT8 *)(UINTN)RdStart)[4], ((UINT8 *)(UINTN)RdStart)[5]));
    }
    P = ProbeChosenProp (Fdt, "bootargs", &Len);
    if (P != NULL) {
      DEBUG ((EFI_D_WARN, "ABL probe: bootargs (%u bytes): %a\n", Len, (CONST CHAR8 *)P));
    }
  }

  DEBUG ((EFI_D_WARN, "ABL probe: waiting %u seconds\n", ABL_PROBE_WAIT));
  MicroSecondDelay (ABL_PROBE_WAIT * 1000000ULL);
}
