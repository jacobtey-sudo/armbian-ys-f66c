# Armbian support for Yisheng YS-F66C (RK3566)

Custom Armbian support for the Yisheng YS-F66C industrial tablet (RK3566, 4+32G, 10.1" MIPI, IP101GR PHY).

## Status (mainline 6.18.57)

| Component | Status | Notes |
|---|---|---|
| HDMI (video) | ✅ Working | 1080p, KDE Plasma |
| HDMI (audio) | ✅ Working | via `i2s0_8ch` |
| Ethernet | ✅ Working | RMII, IP101GR, DHCP |
| USB 2.0 (host) | ✅ Working | Mouse + keyboard via `usb-host-power-gpio` |
| KDE Plasma | ✅ Working | — |
| Network (DHCP) | ✅ Working | — |
| Internal speakers | ❌ Not working | Need `spk-ctl-gpios` in `rk809_codec` |
| USB 3.0 (blue port) | ❌ Not working | `combphy` reset regression in 6.18 |
| Headphone jack | ❓ Not tested | Need `rk_headset` node |
| Camera | ❓ Not tested | Need `ov5648`/`gc2145` node |
| Microphone | ❓ Not tested | PGA settings in `rk809_codec` |
| MIPI display | ❓ Not tested | `dsi1_panel` in reference DTS |
| Touchscreen | ❓ Not tested | `goodix_ts@5d` on i2c1 |

## Structure

- `6.18/rk3566-ys-f66c-working-full.dts` — mainline 6.18 DTS (working: HDMI video+audio, Ethernet, USB 2.0, KDE)
- `6.18/rk3566-ys-f66c-working-full.dtb` — compiled DTB
- `6.18/rk3566-ys-f66c-working-eth.dts` — intermediate state (Ethernet + USB, before HDMI)
- `6.18/rk3566-ys-f66c.dts` — early minimal DTS
- `6.18/boot.cmd` — U-Boot boot script
- `rk3566-ys-f66c.dts` — vendor 4.19 DTS (Android/BSP)
- `ys-f66c-4.19-changes.patch` — patches for 4.19

## Build

```bash
cd ~/build/linux-6.18
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- rockchip/rk3566-ys-f66c.dtb
