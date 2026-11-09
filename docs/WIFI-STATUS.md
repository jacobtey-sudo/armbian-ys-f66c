# WiFi YS-F66C (RK3566, Armbian vendor 6.1) — РАБОТАЕТ

Статус на 08.11.2026: WiFi поднят и проверен на железе. BT — не тестирован (см. ниже).

## Что за чип

Плата **не** Broadcom. SDIO-карта:

```
/sys/bus/sdio/devices/mmc2:390b:1  vendor=0xc8a1 device=0x0082
/sys/bus/sdio/devices/mmc2:390b:2  vendor=0xc8a1 device=0x0182
```

`0xc8a1` — это **AIC8800D80** (драйвер печатает `USE AIC8800D80, chip rev 7`).
Вендорский DT врёт: `wifi_chip_type = "ap6212"` — заглушка, `brcmfmac` к ней не привязывается.

SDIO висит на `sdmmc1` (`fe2c0000`), алиас `mmc2`.

## Три причины, которые пришлось устранить

### 1. SDIO не инициализировался: `mmc2: tuning execution failed: -5`

У нашего `&sdmmc1` не был задан `max-frequency`, поэтому контроллер лез в SDR104
(148.5 МГц) и валил тюнинг. Android/вендор ставят лимит **50 МГц**
(`max-frequency = <0x2faf080>` = 50000000) — тогда карта поднимается.

Фикс в `dt/rk3566-ys-f66c.dts`:

```dts
&sdmmc1 {
	...
	/* Android: max-frequency = 50000000; SDR104 tuning fails above this. */
	max-frequency = <50000000>;
	...
};
```

### 2. Модули вообще не грузились (не только WiFi)

`uname -r` был `6.1.172`, а каталог модулей — `/lib/modules/6.1.172-vendor-rk35xx`,
vermagic модулей `6.1.172-vendor-rk35xx ...`. Значит `modprobe` ничего не находил
(`lsmod` почти пуст).

Armbian собирает ядро с `LOCALVERSION=-${BRANCH}-${LINUXFAMILY}` = `-vendor-rk35xx`
(`lib/functions/compilation/kernel-make.sh`). Ручной `make Image` **без** этого
флага даёт релиз `6.1.172` и ломает загрузку модулей.

Правильная ручная сборка ядра:

```bash
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) \
     LOCALVERSION=-vendor-rk35xx Image
```

`grep -a -o 'Linux version 6.1.172[^ ]*' arch/arm64/boot/Image` → `6.1.172-vendor-rk35xx`.
Полноценная сборка образа через Armbian делает это сама.

### 3. Драйвер AIC8800 (не Broadcom)

Исходника AIC8800 в дереве vendor-ядра 6.1 нет; готовые `aic8800_*.ko` в
`vendor_modules/` собраны под Android-ядро **4.19.232** — не подходят.

Воспроизводимое решение — расширение Armbian (конфиг платы):

```bash
AIC8800_TYPE="sdio"
enable_extension "radxa-aic8800"
```

Расширение `extensions/radxa-aic8800.sh` тянет DKMS- и firmware-пакеты из
`radxa-pkg/aic8800` и собирает модуль в chroot. Патчи Radxa (`fix-sdio-firmware-path`,
`fix-sdio-per-chip-firmware-path`) задают путь прошивки
`/lib/firmware/aic8800_fw/SDIO/<chip>` — туда же firmware-пакет их и кладёт, поэтому
**`modprobe.d` для пути прошивки не нужен**.

`KERNEL_HAS_WORKING_HEADERS=yes` для 6.x; заголовки `linux-headers-vendor-rk35xx`
в `output/debs` есть, DKMS собирается.

## Как проверялось (ручная кросс-сборка, до образа)

```bash
git clone --depth 1 https://github.com/radxa-pkg/aic8800.git
cd aic8800-src/src/SDIO/driver_fw/driver/aic8800
make KDIR=<kworktree> ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- \
     LOCALVERSION=-vendor-rk35xx -j$(nproc)
# modinfo -F vermagic → 6.1.172-vendor-rk35xx SMP mod_unload modversions aarch64
```

Модули и проверка: `aic8800_bsp` + `aic8800_fdrv` в
`/lib/modules/6.1.172-vendor-rk35xx/updates/`, `depmod -a`.
Для ручных (непатченных) модулей путь прошивки пришлось задать вручную:

```
/etc/modprobe.d/aic8800.conf
options aic8800_bsp aic_fw_path=/lib/firmware/aic8800/SDIO/aic8800D80
```

(с патчами Radxa это не требуется).

Результат (после перезагрузки — первый probe):

```
wlan0  UP  192.168.1.11/24   (MAC 00:11:22:33:44:55)
iw dev wlan0 link → Connected to 00:11:22:33:44:77, SSID "ExampleNet",
                    freq 2412, HE (Wi-Fi 6), signal -69 dBm
ping -I wlan0 192.168.1.1 → 0% loss
ping -I wlan0 1.1.1.1      → 0% loss
curl --interface wlan0 https://www.google.com → http=200
```

Важно: повторный `rmmod`+`modprobe` aic8800_bsp без перезагрузки валится
(`aicbsp_dummy_sdmmc ... error -123`) — карта остаётся в плохом состоянии,
нужен reboot.

## Стабильность (для этой сети)

AP «ExampleNet» вещает WPA2/WPA3 transition + PMF. При свободном роуминге между
BSSID и включённом PMF ассоциация рвётся на 4-way handshake
(`rwnx_rx_sm_disconnect_ind reason code:2`; NetworkManager:
`disconnected during association, asking for new key` → `no secrets`).
Рабочая настройка (BSSID — конкретно этого AP):

```bash
nmcli connection modify examplenet 802-11-wireless.bssid 00:11:22:33:44:77
nmcli connection modify examplenet wifi-sec.pmf 3     # PMF disabled, WPA2-PSK
nmcli connection up examplenet
```

После этого — **30/30 пингов за 60 с, 0% потерь**, сигнал −66 dBm, `https=200`.
Логин/пароль сети — пользовательские, в userpatches не кладутся.

## Артефакты

* `dt/rk3566-ys-f66c.dts` — `&sdmmc1 { max-frequency = <50000000>; }`
* `config/boards/ys-f66c.csc` — `AIC8800_TYPE="sdio"` + `enable_extension "radxa-aic8800"`
* Ядро на плате: `6.1.172-vendor-rk35xx` (LOCALVERSION), `/boot/vmlinuz-...`
* Rучная копия модулей (fallback): `~/board/aic8800-modules/`

## BT (следующий шаг)

BT у AIC8800 идёт по **UART** (вендор: `/dev/ttyS1`, т.е. uart1; в DT
`wireless-bluetooth` с `uart_rts_gpios`/`BT,reset_gpio`). У нас в DTS включён
только `&uart2` (это консоль/earlycon) — uart1 для BT не настроен. Нужно:
включить uart1 с нужным mux, добавить узлы reset/wake GPIO, поднять
`aic8800_btlpm_sdio` и `hciattach` (см. `packages/bsp/aic8800/aic-bluetooth`).
