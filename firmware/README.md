# Firmware

Linux needs the phone's own firmware for the DSPs, modem, Wi-Fi, Bluetooth,
the GPU's zap shader and the speaker tuning. These files are signed for this
phone and nobody may redistribute them, so this repository doesn't ship them:
`nx809j-firmware.sh` copies them from your phone's Android, as root.

With Linux installed on the `linux` partition, from a PC with adb:

```bash
adb push firmware/nx809j-firmware.sh /data/local/tmp/
```

```bash
adb shell su -c sh /data/local/tmp/nx809j-firmware.sh
```

or run the second command (`su -c sh …`) in a terminal app on the phone. The
script reads Android's firmware read-only, mounts the Linux partition and
installs the files under `/usr/lib/firmware`. Run it again after updating
Android: the modem firmware should match the one Android last ran.

Other targets, as the first argument:

| Target | Result |
|---|---|
| (none) | `/dev/block/by-name/linux` is mounted and the files installed into it |
| a block device | the same, on that partition |
| a directory | files installed under `DIR/usr/lib/firmware` |
| `FILE.tar` | an archive of `usr/lib/firmware/…` to unpack into a Linux root |

What it copies (`qcom/kaanapali/nubia/nx809j/` unless noted):

| From Android | Installed as |
|---|---|
| `/vendor/firmware_mnt/image/{adsp,cdsp,modem,ipa_fws}*.mdt` + `.bNN` | `*.mbn`, rebuilt into single files like [pil-squasher](https://github.com/linux-msm/pil-squasher) |
| `soccp` partition, `image/soccp*.mbn` | `soccp.mbn`, `soccp_dtb.mbn` |
| `/vendor/firmware_mnt/image/{modemr.jsn,modem_pr,modem_oem}` | the same names, served to the modem by tqftpserv |
| `/vendor/firmware/gen80200_zap.mbn` | `gen80200_zap.mbn` |
| `/vendor/firmware/aw882xx_acf.bin` | `aw88461_acf.bin` |
| `/vendor/firmware_mnt/image/peach/*` | `ath12k/PEACH/hw2.0/{amss,m3,aux_ucode,board,regdb}.bin`, `qdss_trace_config.cfg` |
| `/vendor/bt_firmware/image/brhbt{fw20.mbn,nv20.*}` | `qca/` |

The Adreno 840 microcode (`qcom/gen80200_{sqe,gmu,aqe}`) comes from your
distribution's linux-firmware package instead: mainline doesn't work with the
phone's newer GMU firmware.
