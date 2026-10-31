# NX809J device files

Everything the phone needs in its root filesystem besides the kernel and
firmware, independent of the distribution (any systemd one). `rootfs/` holds
the files at their installed paths, all under `/usr`, so `/etc` stays free for
local changes.

| File | What it does |
|---|---|
| `nx809j-rmtfs-copies` (+ service) | On first boot, copies the modem's file system partitions (modemst1, modemst2, fsc, fsg) to `/var/lib/rmtfs`, reading the partitions only |
| `rmtfs.service.d/nx809j.conf` | rmtfs serves those copies (`-o /var/lib/rmtfs`, never `-P`) and starts the modem (`-s`) |
| `80-nx809j-modem-recovery.rules` | Turns modem crash recovery off: restarting the modem still freezes the SoC |
| `nx809j-dnssec.conf` | `DNSSEC=no` for systemd-resolved: operator DNS servers strip the signatures, so every lookup on mobile data failed |
| `nx809j-wifi-mac` (+ service) | Wi-Fi MAC address from the persist partition (read only, `debugfs -c`) |
| `nx809j-bt-addr` (+ service) | Bluetooth address from the persist partition (read only) |
| `nx809j-mark-boot-successful.service` | `qbootctl -m a`, as Android does every boot, so ABL keeps slot a bootable |
| `nx809j-usb-uplink.service` | Internet through the PC over the USB network (172.16.42.2) |
| `50-nx809j-usb0-unmanaged.conf` | Keeps NetworkManager off `usb0` (the rootfs may come over NBD on it) |
| `nx809j-cpufreq-boost.conf` | Allows the prime cores' boost steps (4.51 and 4.61 GHz) |
| UCM (`Nubia-NX809J.conf`, `HiFi.conf`, `VoiceCall.conf`) | ALSA use case profile: speakers, mic, headphones, headset mic, calls |
| `nx809j-audio-hexagonrpcd.service` | Serves the ADSP's voice modules (Fluence) to its audio PD; speech doesn't flow without them. Patched hexagonrpc (`archlinux/hexagonrpc`) |
| `callaudio.service.d/wait-card.conf` | callaudio waits for the sound card, which comes up after the user session |
| `/usr/lib/dmail/modem-setup` | What dmail runs before talking to the modem: here it only checks that our services started it |
| `iio-sensor-proxy.service.d/nx809j.conf` | 3 s stop timeout: the Qualcomm sensor backend waits for a sensor hub that never answers (no hexagonrpcd) and held shutdown for 90 s |
| `nx809j-reboot-linux` (+ "Reboot to Linux" launcher) | Dual boot: arms the Canoe boot manager's boot-once record for Linux in `misc`, then reboots (see `uefi/README.md`); needs passwordless sudo when run as a user |
| `80-nx809j.preset` | Which of these services (and rmtfs, tqftpserv) systemd enables. ModemManager is left to you: the Arch image uses dmail (`phonewave-nx809j`) instead, and the two conflict |

The Android side (KernelSU module with an Action button, LSPosed item
**Linux** in the power menu's restart options) is
[android-reboot-to-linux](https://github.com/Reixo0/android-reboot-to-linux).

## Packages

The services above need these from the distribution:

| Purpose | postmarketOS / Alpine | Arch Linux ARM |
|---|---|---|
| Modem file system and firmware servers | `rmtfs`, `tqftpserv` | `rmtfs`, `tqftpserv`, if packaged; otherwise build them from [linux-msm](https://github.com/linux-msm) |
| Mobile data, calls | `modemmanager` (1.24 or later, for the `qcom-soc` plugin) | `phonewave-nx809j` (dmail, callaudio) |
| Call audio | not packaged | `hexagonrpc`, `phonewave-nx809j` |
| Network | `networkmanager`, `systemd-resolved` | `networkmanager` (systemd-resolved is part of `systemd`) |
| Boot slot marking | `qbootctl` | build [qbootctl](https://github.com/linux-msm/qbootctl) |
| Reading persist (MAC, BT address) | `e2fsprogs-extra` (debugfs) | `e2fsprogs` |
| Bluetooth address | `bluez-btmgmt` | `bluez-utils` |
| Vulkan on the Adreno 840 | `mesa-vulkan-freedreno` | `vulkan-freedreno` |
| Audio | PipeWire (`postmarketos-base-ui-audio-backend-pipewire`) | `pipewire`, `wireplumber`, `alsa-ucm-conf` |

On postmarketOS, `device-nubia-nx809j` installs `rootfs/` (packed by
`scripts/pmos-kernel-pkg.sh`) and pulls in the packages.

## Installing into another root filesystem

With the root filesystem mounted at `/mnt` and the packages above installed:

```bash
sudo RMTFS_FROM=/old-root/var/lib/rmtfs scripts/install-device-files.sh /mnt
```

This installs `rootfs/`, the firmware (`scripts/firmware-files.sh`: GPU, DSPs,
modem, IPA, Wi-Fi, Bluetooth, audio, the ADSP's voice modules, the voice
profile if you built it) and the kernel modules, and enables the
services. `RMTFS_FROM` carries the modem's file system copies over from the
old root, so the modem keeps its state; without it they are made fresh from
the partitions on first boot. The copies and the firmware come from this
phone and are private (IMEI, calibration): they are never in git.

## Voice call profile

Calls need `qcom/kaanapali/nubia/nx809j/voice.bin`, the graphs the kernel's
q6apm voice session runs. It is built from the phone's stock ACDB, so it is
vendor data: never in git and in no public image. `audio/voice.toml` says what
to ask of the ACDB. The generator is
[Phonewave](https://github.com/denialwm/phonewave)'s `services/audio/voicegen`
(gcc, autotools, Python 3.11 or later; any Linux PC). With `DENIAL_BUILD` as
for `scripts/build-denial.sh`, and with the ACDB from Android's
`/vendor/etc/acdbdata` in `dump/vendor-audio/acdbdata`:

```bash
make -C ~/denial-build/phonewave/services/audio/voicegen
```

```bash
python3 ~/denial-build/phonewave/services/audio/voicegen/voiceprofile.py device/audio/voice.toml dump/vendor-audio/nx809j-voice.bin --vault dump
```

`scripts/firmware-files.sh` picks it up from there. For
`firmware/nx809j-firmware.sh`, push it next to that script. To check a build,
start the graphs without a call: the sound card's `Voice Call` profile should
leave no DSP errors in the kernel log. Switch back to HiFi afterwards:
WirePlumber remembers the choice, and a stored `Voice Call` is one suspect for
past resets at boot.

The profile's TX path uses Fluence, a library the ADSP loads at run time from
`NX809J-audio/dsp/adsp` (`vendor/dsp/adsp` on Android). Without
`nx809j-audio-hexagonrpcd.service` running, no speech flows from the modem.

## Not in here

- The mobile data profile depends on the SIM. With dmail, when its automatic
  choice is refused, `apn = "<apn>"` in `/etc/dmail/apn.toml`. With ModemManager
  and NetworkManager:

  ```bash
  sudo nmcli connection add type gsm ifname qrtr0 con-name mobile apn <apn> \
    gsm.pin-flags 4 gsm.password-flags 4
  ```

  The flags stop NetworkManager from asking for a PIN and a password itself;
  the desktop's SIM unlock dialog (or `mmcli -i any --pin=<pin>`) unlocks the
  SIM, and the profile connects after that.
- The kernel's built-in initramfs mounts the root filesystem
  (`nx809j.root=dm` or `nbd`) and starts `/sbin/init`, so the boot image does
  not depend on the distribution.
