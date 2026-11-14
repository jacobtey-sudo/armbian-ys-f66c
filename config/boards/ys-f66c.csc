BOARD_NAME="Yisheng YS-F66C"
BOARDFAMILY="rk35xx"
BOARD_MAINTAINER="ys-f66c"
KERNEL_TARGET="vendor"
BOOT_SOC="rk3566"
BOOT_FDT_FILE="rockchip/rk3566-ys-f66c.dtb"

# The rk35xx vendor default points the serial getty at ttyFIQ0, but this kernel
# has no fiq-debugger device; serial-getty@ttyFIQ0 waits 90 s on
# BindsTo=dev-ttyFIQ0.device and the panel shows a black screen that looks like
# a hang. The boot script already uses console=ttyS2 (UART2, 1500000 baud), so
# point Armbian at the real port instead. ttyFIQ0 is still masked below.
function post_family_config__ys_f66c_serial_console() {
	display_alert "$BOARD" "Using ttyS2 as the serial console getty" "info"
	declare -g SERIALCON="ttyS2:1500000"
}

# The internal camera is a plain USB UVC device, so a generic V4L2 app is
# enough: Kamoso for the desktop plus v4l-utils for CLI testing. The rotation
# service needs gst-launch-1.0.
# Maliit is KWin's virtual keyboard provider and the only OSK on the image
# (Onboard removed). Verified 14.11.2026 in Plasma 6 Wayland and SDDM.
PACKAGE_LIST_BOARD="kamoso v4l-utils gstreamer1.0-tools pulseaudio-utils maliit-keyboard maliit-framework libmaliit-plugins2"

# WiFi: two hardware revisions exist. The AP6212 revision (SDIO 02d0:a9a6)
# uses the in-tree brcmfmac. The AIC8800 revision (SDIO c8a1) uses the Radxa
# DKMS package from the radxa-aic8800 extension. The extension is installed
# on every image; its modules do not bind on AP6212 units.
# Verified on hardware: AIC 08.11.2026 (HE, ping/HTTP OK), AP6212 09.11.2026.
AIC8800_TYPE="sdio"
enable_extension "radxa-aic8800"

# Bluetooth is on UART1 (serial@fe650000). The Rockchip rfkill-bt driver
# controls power and reset. Kernel 6.1 attaches hci0 through a serdev child
# node; no hciattach is needed.
#   AP6212 revision (BCM43430A1): hci_uart_bcm loads brcm/BCM43430A1.hcd.
#     This is the default DTB.
#   AIC8800 revision: hci_uart_aic asks the AIC SDIO driver for the firmware.
#     This revision uses rk3566-ys-f66c-aic.dtb (see the selector below).
# Verified on hardware 09.11.2026 (AP6212): hci0 up, scan finds devices.
function post_family_tweaks_bsp__ys_f66c_bt_unblock() {
	display_alert "$BOARD" "Installing YS-F66C BT rfkill unblock service" "info"
	install -d -m 0755 "${destination}/usr/lib/systemd/system"
	cat > "${destination}/usr/lib/systemd/system/ys-f66c-bt-unblock.service" <<-'EOT'
		[Unit]
		Description=Unblock Bluetooth rfkill (YS-F66C)
		After=bluetooth.service
		Wants=bluetooth.service

		[Service]
		Type=oneshot
		ExecStart=/usr/sbin/rfkill unblock bluetooth
		RemainAfterExit=yes

		[Install]
		WantedBy=multi-user.target
	EOT
}

function post_family_tweaks__ys_f66c_enable_bt_unblock() {
	display_alert "$BOARD" "Enabling YS-F66C BT rfkill unblock service" "info"
	chroot_sdcard systemctl --no-reload enable ys-f66c-bt-unblock.service
}

# The default DTB targets the AP6212, so Bluetooth works on the first boot.
# On a unit with the AIC8800 SDIO id c8a1, point fdtfile at the AIC DTB and
# reboot once.
function post_family_tweaks_bsp__ys_f66c_bt_dtb() {
	display_alert "$BOARD" "Installing YS-F66C Bluetooth DTB selector" "info"
	install -d -m 0755 "${destination}/usr/local/sbin" "${destination}/usr/lib/systemd/system"
	cat > "${destination}/usr/local/sbin/ys-f66c-bt-dtb" <<-'EOT'
		#!/bin/sh
		# Select the Bluetooth DTB variant once (see the board config).
		set -e
		envfile=/boot/armbianEnv.txt
		marker=/etc/ys-f66c-bt-dtb.done
		[ -e "$marker" ] && exit 0
		[ -f "$envfile" ] || exit 0
		aic=0
		for dev in /sys/bus/sdio/devices/*; do
		    [ -r "$dev/uevent" ] || continue
		    if grep -qi "^SDIO_ID=C8A1:" "$dev/uevent"; then
		        aic=1
		        break
		    fi
		done
		if [ "$aic" = 1 ] && grep -q "^fdtfile=rockchip/rk3566-ys-f66c\.dtb$" "$envfile"; then
		    sed -i "s|^fdtfile=.*|fdtfile=rockchip/rk3566-ys-f66c-aic.dtb|" "$envfile"
		    touch "$marker"
		    sync
		    systemctl reboot
		    exit 0
		fi
		touch "$marker"
	EOT
	chmod 0755 "${destination}/usr/local/sbin/ys-f66c-bt-dtb"
	cat > "${destination}/usr/lib/systemd/system/ys-f66c-bt-dtb.service" <<-'EOT'
		[Unit]
		Description=Select Bluetooth DTB revision (YS-F66C)
		After=local-fs.target sysinit.target
		ConditionPathExists=!/etc/ys-f66c-bt-dtb.done

		[Service]
		Type=oneshot
		ExecStart=/usr/local/sbin/ys-f66c-bt-dtb

		[Install]
		WantedBy=multi-user.target
	EOT
}

function post_family_tweaks__ys_f66c_enable_bt_dtb() {
	display_alert "$BOARD" "Enabling YS-F66C Bluetooth DTB selector" "info"
	chroot_sdcard systemctl --no-reload enable ys-f66c-bt-dtb.service
}

# Several identical tablets otherwise show up on the network under the same
# name, because HOST defaults to BOARD ("ys-f66c"). On first boot, before
# networking starts, derive a unique name from the SoC serial number:
#   serial 0000000000000000 -> ys-f66c-XXXX
# The service only acts while /etc/hostname still holds the image default, so
# a name set by the user is never overwritten.
function post_family_tweaks_bsp__ys_f66c_unique_hostname() {
	display_alert "$BOARD" "Installing unique hostname service" "info"
	install -d -m 0755 "${destination}/usr/local/sbin" "${destination}/usr/lib/systemd/system"
	cat > "${destination}/usr/local/sbin/ys-f66c-hostname" <<-'EOT'
		#!/bin/sh
		# Unique hostname (ys-f66c-XXXX) from the RK3566 serial number.
		set -e
		default=ys-f66c
		[ "$(cat /etc/hostname 2>/dev/null)" = "$default" ] || exit 0
		serial=$(tr -d "\000" < /proc/device-tree/serial-number 2>/dev/null | tr -d "[:space:]") || exit 0
		[ -n "$serial" ] || exit 0
		suffix=$(printf "%s" "$serial" | tail -c 4)
		name="$default-$suffix"
		printf "%s\n" "$name" > /etc/hostname
		if grep -q "^127\.0\.1\.1" /etc/hosts; then
			sed -i "s/^127\.0\.1\.1.*/127.0.1.1 $name/" /etc/hosts
		else
			printf "127.0.1.1 %s\n" "$name" >> /etc/hosts
		fi
		hostname "$name" 2>/dev/null || true
	EOT
	chmod 0755 "${destination}/usr/local/sbin/ys-f66c-hostname"
	cat > "${destination}/usr/lib/systemd/system/ys-f66c-hostname.service" <<-'EOT'
		[Unit]
		Description=Unique hostname from board serial (YS-F66C)
		DefaultDependencies=no
		After=local-fs.target
		Before=network-pre.target systemd-hostnamed.service

		[Service]
		Type=oneshot
		ExecStart=/usr/local/sbin/ys-f66c-hostname
		RemainAfterExit=yes

		[Install]
		WantedBy=sysinit.target
	EOT
}

function post_family_tweaks__ys_f66c_enable_unique_hostname() {
	display_alert "$BOARD" "Enabling unique hostname service" "info"
	chroot_sdcard systemctl --no-reload enable ys-f66c-hostname.service
}

# Own bootenv file. It shows the full kernel log on the UART (verbosity=7)
# and enables earlycon on uart2 for bring-up.
function post_family_config__ys_f66c_bootenv() {
    declare -g BOOTENV_FILE="ys-f66c.txt"
}

# Pin the vendor kernel to the validated commit. Branch rk-6.1-rkr7.2 moves often.
# A moving branch changes the kernel artifact hash, so it forces full rebuilds.
function post_family_config__ys_f66c_pin_kernel_commit() {
    display_alert "$BOARD" "Pinning vendor kernel to commit a21efef" "info"
    declare -g KERNELBRANCH="commit:a21efefcf2b5731d1df0505ddf725af6e5530cfb"
}

# Драйверы панели и подсветки обязаны быть встроенными (=y), а не модулями.
# DSI-хост ищет панель в своём probe, задолго до монтирования rootfs. Пока
# драйвер панели лежит модулем в rootfs, drm_of_find_panel_or_bridge()
# возвращает -EPROBE_DEFER, DRM-подсистема зацикливается на повторном
# probe и загрузка никогда не доходит до init (проверено на UART 02.11.2026).
function custom_kernel_config__ys_f66c_display_builtin() {
	# Анонс правок в хэш-массиве нужен в ОБЕИХ фазах вызова хука.
	# Во второй фазе .config ещё нет — если анонсировать только внутри
	# "if [[ -f .config ]]", версия артефакта ядра не меняется, Armbian
	# берёт ядро из кэша и правки .config никуда не попадают (проверено
	# 02.11.2026: сборка молча использовала старое ядро).
	kernel_config_modifying_hashes+=("DRM_PANEL_SIMPLE=y")
	kernel_config_modifying_hashes+=("BACKLIGHT_PWM=y")
	if [[ -f .config ]]; then
		display_alert "$BOARD" "Display drivers built into the kernel" "info"
		kernel_config_set_y "DRM_PANEL_SIMPLE"
		kernel_config_set_y "BACKLIGHT_PWM"
	fi
}

function post_family_config__ys_f66c_use_mainline_uboot() {
    display_alert "$BOARD" "Using mainline U-Boot for $BOARD / $BRANCH" "info"
    declare -g BOOTSOURCE="https://github.com/u-boot/u-boot.git"
    declare -g BOOTBRANCH="tag:v2025.10"
    declare -g BOOTPATCHDIR="v2025.10"
    declare -g BOOTCONFIG="generic-rk3568_defconfig"
    declare -g BOOTDIR="u-boot-${BOARD}"
    declare -g BOOTDELAY=1
    declare -g UBOOT_TARGET_MAP="BL31=${RKBIN_DIR}/${BL31_BLOB} ROCKCHIP_TPL=${RKBIN_DIR}/${DDR_BLOB};;u-boot-rockchip.bin"
    unset uboot_custom_postprocess write_uboot_platform write_uboot_platform_mtd

    function write_uboot_platform() {
        dd "if=$1/u-boot-rockchip.bin" "of=$2" bs=32k seek=1 conv=notrunc status=none
    }
}

# Power button (short press) opens the KDE logout / shutdown dialog.
# powerdevil handles the key itself and inhibits logind's power key.
# SuspendSession::LogoutDialogMode == 16; key is powerButtonAction (lowercase)
# in the per-action group [<profile>][HandleButtonEvents].
function post_family_tweaks__ys_f66c_power_button() {
	display_alert "$BOARD" "KDE power button -> logout/shutdown dialog" "info"
	local g
	for g in "${SDCARD}/etc/xdg/powerdevilrc" \
	         "${SDCARD}/etc/skel/.config/powerdevilrc"; do
		install -d -m 0755 "$(dirname "$g")"
		cat > "$g" <<-'EOT'
			[AC][HandleButtonEvents]
			powerButtonAction=16
			
			[Battery][HandleButtonEvents]
			powerButtonAction=16
			
			[LowBattery][HandleButtonEvents]
			powerButtonAction=16
		EOT
	done
}

# Holding Backspace at the start of a line makes the terminal/application ring
# the system bell for every key repeat. Each bell creates a new KWin audio
# stream; with A2DP active this stalls the compositor (thousands of "Key repeat
# discarded" messages) and loops the bell. The tablet has no need for an
# audible bell, so disable it system-wide and for newly created users.
function post_family_tweaks__ys_f66c_disable_bell() {
	display_alert "$BOARD" "Disabling the KDE system bell" "info"
	local f
	for f in "${SDCARD}/etc/xdg/kaccessrc" \
	         "${SDCARD}/etc/skel/.config/kaccessrc"; do
		install -d -m 0755 "$(dirname "$f")"
		cat > "$f" <<-'EOT'
			[Bell]
			SystemBell=false
		EOT
	done
}

# The internal camera is a portrait UVC sensor: the raw picture is turned 90
# degrees. v4l2loopback carries a rotated copy on /dev/video10. Desktop apps
# see only the virtual camera; the raw device stays root-only. Kamoso uses the
# libcamera GStreamer provider, which hides every v4l2 device, so remove it.
function post_family_tweaks__ys_f66c_camera() {
	display_alert "$BOARD" "Installing YS-F66C rotated virtual camera" "info"
	local kv src="${SRC}/userpatches/packages"
	kv=$(ls -1 "${SDCARD}/lib/modules" | head -1)
	[[ -n "$kv" ]] || { display_alert "$BOARD" "No kernel modules found" "err"; exit 1; }

	install -D -m 0755 "${src}/ys-f66c-camera/ys-f66c-camera-start" "${SDCARD}/usr/local/sbin/ys-f66c-camera-start"
	install -D -m 0644 "${src}/ys-f66c-camera/ys-f66c-camera" "${SDCARD}/etc/default/ys-f66c-camera"
	install -D -m 0644 "${src}/ys-f66c-camera/ys-f66c-camera-rotate.service" "${SDCARD}/etc/systemd/system/ys-f66c-camera-rotate.service"
	install -D -m 0644 "${src}/ys-f66c-camera/ys-f66c-v4l2loopback.conf" "${SDCARD}/etc/modprobe.d/ys-f66c-v4l2loopback.conf"
	install -D -m 0644 "${src}/ys-f66c-camera/72-ys-f66c-hide-raw-camera.rules" "${SDCARD}/etc/udev/rules.d/72-ys-f66c-hide-raw-camera.rules"

	install -D -m 0644 "${src}/v4l2loopback-0.13.2.tar.gz" "${SDCARD}/usr/src/v4l2loopback-0.13.2.tar.gz"
	chroot_sdcard tar -xzf /usr/src/v4l2loopback-0.13.2.tar.gz -C /usr/src
	chroot_sdcard_apt_get_install build-essential
	if ! chroot_sdcard make -C "/lib/modules/${kv}/build" M="/usr/src/v4l2loopback-0.13.2" modules modules_install; then
		local prebuilt="${src}/v4l2loopback-0.13.2-${kv}.ko"
		[[ -f "$prebuilt" ]] || { display_alert "$BOARD" "v4l2loopback build failed" "err"; exit 1; }
		display_alert "$BOARD" "Using prebuilt v4l2loopback module" "warn"
		install -D -m 0644 "$prebuilt" "${SDCARD}/usr/lib/modules/${kv}/extra/v4l2loopback.ko"
	fi
	chroot_sdcard depmod -a "${kv}"
	rm -rf "${SDCARD}/usr/src/v4l2loopback-0.13.2" "${SDCARD}/usr/src/v4l2loopback-0.13.2.tar.gz"

	chroot_sdcard systemctl --no-reload enable ys-f66c-camera-rotate.service
	chroot_sdcard_apt_get_remove gstreamer1.0-libcamera || true
	rm -f "${SDCARD}/usr/lib/aarch64-linux-gnu/gstreamer-1.0/libgstlibcamera.so"
}

# The RK817 codec has one output path at a time. Android used the rk_headset
# driver on GPIO3_D1 and the codec's spk-ctl GPIO to mute the speakers when a
# 3.5-mm plug was inserted. The kernel already has CONFIG_RK_HEADSET=y; this
# installs the userspace bridge from extcon to the codec's Playback Path.
function post_family_tweaks_bsp__ys_f66c_headset() {
	display_alert "$BOARD" "Installing YS-F66C headphone jack routing" "info"
	local src="${SRC}/userpatches/packages/ys-f66c-headset"
	install -D -m 0755 "${src}/ys-f66c-headset-route" "${destination}/usr/local/sbin/ys-f66c-headset-route"
	install -D -m 0644 "${src}/90-ys-f66c-headset.rules" "${destination}/etc/udev/rules.d/90-ys-f66c-headset.rules"
	install -D -m 0644 "${src}/ys-f66c-headset-route.service" "${destination}/usr/lib/systemd/system/ys-f66c-headset-route.service"
}

function post_family_tweaks__ys_f66c_enable_headset() {
	chroot_sdcard systemctl --no-reload enable ys-f66c-headset-route.service
}

# The vendor default is ondemand. schedutil is a better fit for the A55 +
# Plasma workload and reacts faster to interactive load.
function post_family_tweaks_bsp__ys_f66c_cpufreq_governor() {
	display_alert "$BOARD" "Installing YS-F66C cpufreq governor service" "info"
	install -d -m 0755 "${destination}/usr/lib/systemd/system"
	cat > "${destination}/usr/lib/systemd/system/ys-f66c-cpufreq-governor.service" <<-'EOT'
		[Unit]
		Description=Set YS-F66C CPU governor to schedutil
		After=sysinit.target
		Before=display-manager.service

		[Service]
		Type=oneshot
		ExecStart=/bin/sh -c 'for p in /sys/devices/system/cpu/cpufreq/policy*; do [ -w "$p/scaling_governor" ] && echo schedutil > "$p/scaling_governor"; done'
		RemainAfterExit=yes

		[Install]
		WantedBy=multi-user.target
	EOT
}

function post_family_tweaks__ys_f66c_enable_cpufreq_governor() {
	chroot_sdcard systemctl --no-reload enable ys-f66c-cpufreq-governor.service
}

# The SDDM greeter is X11. Rotate it before the greeter starts.
# The Plasma session is Wayland and keeps KWin's Rotated270 transform.
function post_family_tweaks_bsp__ys_f66c_sddm_rotation() {
	display_alert "$BOARD" "Installing YS-F66C SDDM rotation hook" "info"
	install -d -m 0755 "${destination}/usr/local/sbin" "${destination}/etc/sddm.conf.d"
	cat > "${destination}/usr/local/sbin/ys-f66c-sddm-xsetup" <<-'EOT'
		#!/bin/sh
		# Rotate the greeter X server. Keep this idempotent.
		LOG=/var/log/ys-f66c-sddm-xsetup.log
		{
			echo "--- $(date '+%F %T') ---"
			echo "env DISPLAY=${DISPLAY:-} XAUTHORITY=${XAUTHORITY:-}"
		} >>"$LOG" 2>&1

		[ -n "${DISPLAY:-}" ] || DISPLAY=:0
		if [ -z "${XAUTHORITY:-}" ]; then
			XAUTHORITY=$(ls -t /run/sddm/xauth_* 2>/dev/null | head -1)
		fi
		export DISPLAY XAUTHORITY
		echo "use DISPLAY=$DISPLAY XAUTHORITY=${XAUTHORITY:-}" >>"$LOG" 2>&1
		command -v xrandr >/dev/null 2>&1 || exit 0

		# The connector can appear a moment after Xorg starts.
		i=0
		outputs=
		while [ "$i" -lt 25 ]; do
			outputs=$(xrandr --query 2>/dev/null | awk '/ connected/{print $1}')
			[ -n "$outputs" ] && break
			i=$((i + 1))
			sleep 0.2
		done
		echo "outputs: ${outputs:-none}" >>"$LOG" 2>&1
		for output in $outputs; do
			geometry=$(xrandr --query 2>/dev/null | awk -v out="$output" '$1 == out {print $3; exit}')
			case "$geometry" in
				*x*+*)
					width=${geometry%%x*}
					rest=${geometry#*x}
					height=${rest%%+*}
					if [ "${width:-0}" -lt "${height:-0}" ]; then
						echo "rotate $output right" >>"$LOG" 2>&1
						xrandr --output "$output" --rotate right >>"$LOG" 2>&1 || true
					fi
					;;
			esac
		done
	EOT
	chmod 0755 "${destination}/usr/local/sbin/ys-f66c-sddm-xsetup"
	cat > "${destination}/etc/sddm.conf.d/ys-f66c-rotation.conf" <<-'EOT'
		[General]
		DisplayServer=x11

		[X11]
		DisplayCommand=/usr/local/sbin/ys-f66c-sddm-xsetup
	EOT
}

# The image enables a serial getty for ttyFIQ0, but this kernel has no
# fiq-debugger device. The getty's BindsTo=dev-ttyFIQ0.device makes every boot
# wait 90 seconds at getty.target; the panel then sits on a black screen with
# a cursor long enough to look like a hang. There is no usable ttyFIQ0 on this
# board, so disable and mask that one instance. UART2 (ttyS2) remains available.
function post_family_tweaks__ys_f66c_disable_fiq_getty() {
	display_alert "$BOARD" "Disabling nonexistent ttyFIQ0 serial getty" "info"
	chroot_sdcard systemctl --no-reload disable serial-getty@ttyFIQ0.service || true
	chroot_sdcard systemctl --no-reload mask serial-getty@ttyFIQ0.service || true
}

# DPMS off/on corrupts the DSI panel. Keep the display on.
function post_family_tweaks__ys_f66c_no_screen_off() {
	display_alert "$BOARD" "Disabling automatic display power-off" "info"
	for profile in AC Battery LowBattery; do
		chroot_sdcard kwriteconfig6 --file /etc/xdg/powerdevilrc \
			--group "$profile" --group Display \
			--key TurnOffDisplayWhenIdle --type bool false
		chroot_sdcard kwriteconfig6 --file /etc/xdg/powerdevilrc \
			--group "$profile" --group Display \
			--key DimDisplayWhenIdle --type bool false
	done
}

# MCU power/heartbeat control: Android's misc_gpio driver equivalent.
# Drives mcu_shutdown_control low before poweroff/halt and high before restart
# (with the same ~2 s settle), and toggles mcu,gpio as a 3 s heartbeat.
function post_family_tweaks__ys_f66c_misc_gpio() {
	display_alert "$BOARD" "Installing YS-F66C MCU misc-gpio module" "info"
	local kv src="${SRC}/userpatches/packages/ys-f66c-misc-gpio"
	kv=$(ls -1 "${SDCARD}/lib/modules" | head -1)
	[[ -n "$kv" ]] || { display_alert "$BOARD" "No kernel modules found" "err"; exit 1; }

	install -D -m 0644 "${src}/misc-gpio.c" "${SDCARD}/usr/src/misc-gpio/misc-gpio.c"
	install -D -m 0644 "${src}/Makefile" "${SDCARD}/usr/src/misc-gpio/Makefile"
	chroot_sdcard_apt_get_install build-essential || true
	if ! chroot_sdcard make -C "/lib/modules/${kv}/build" M="/usr/src/misc-gpio" modules modules_install; then
		local prebuilt="${src}/misc-gpio-${kv}.ko"
		[[ -f "$prebuilt" ]] || { display_alert "$BOARD" "misc-gpio build failed" "err"; exit 1; }
		display_alert "$BOARD" "Using prebuilt misc-gpio module" "warn"
		install -D -m 0644 "$prebuilt" "${SDCARD}/usr/lib/modules/${kv}/extra/misc-gpio.ko"
	fi
	chroot_sdcard depmod -a "${kv}"
	install -D -m 0644 "${src}/misc-gpio.conf" "${SDCARD}/etc/modules-load.d/misc-gpio.conf"
	rm -rf "${SDCARD}/usr/src/misc-gpio"
}

# SDDM greeter: keep the working Breeze on-screen keyboard and avoid the
# Qt 6.8.2 qtvirtualkeyboard hang. Plasma uses Maliit through KWin.
function post_family_tweaks_bsp__ys_f66c_sddm_inputmethod() {
	display_alert "$BOARD" "Installing YS-F66C SDDM InputMethod=none" "info"
	install -d -m 0755 "${destination}/etc/sddm.conf.d"
	cat > "${destination}/etc/sddm.conf.d/ys-f66c-inputmethod.conf" <<-'EOT'
		[General]
		InputMethod=none
	EOT
}
