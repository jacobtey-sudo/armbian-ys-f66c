# Armbian для планшета на плате Yisheng YS-F66C (Rockchip RK3566)

Board-support (`userpatches`) и консольная база Armbian для планшета на
Yisheng YS-F66C с вендорским ядром Rockchip 6.1.

**English TL;DR:** Board support and console base for the Yisheng YS-F66C
RK3566 tablet. Clone the Armbian build framework (pinned commit), clone this
repo as `userpatches/`, run `./compile.sh ys-f66c build`. The Plasma 6 desktop
image is built from
[armbian-ys-f66c-plasma6](https://github.com/jacobtey-sudo/armbian-ys-f66c-plasma6).

**Готовый образ:** сборка с рабочим столом Plasma 6 — в
[armbian-ys-f66c-plasma6](https://github.com/jacobtey-sudo/armbian-ys-f66c-plasma6/releases).
Она собрана из этого board support.

---

## Разделение с десктопом

| Репозиторий | Содержимое | Сборка |
|---|---|---|
| этот репозиторий | DTS, U-Boot, патчи ядра, железные хуки и сервисы, консольная база | `BUILD_DESKTOP=no` |
| [armbian-ys-f66c-plasma6](https://github.com/jacobtey-sudo/armbian-ys-f66c-plasma6) | board-конфиг Plasma 6, overlay, KDE/SDDM-хуки, Mesa и FlClash | `BUILD_DESKTOP=yes` |

Этот репозиторий не ставит рабочий стол. Desktop-пакеты, overlay и
KDE-настройки живут в `armbian-ys-f66c-plasma6`.

## Железо

| | |
|---|---|
| SoC | Rockchip RK3566 (4× Cortex-A55) |
| RAM / eMMC | 4 ГБ / 32 ГБ |
| Экран | 10.1", 800×1280, MIPI DSI |
| Тачскрин | Goodix GT9271 (I2C1, INT GPIO3_C6 / RST GPIO3_C7) |
| PMIC / звук | RK809 (динамик, наушники 3.5 мм, микрофон) |
| WiFi / BT | две ревизии: AP6212 (BCM43430A1, SDIO `02d0`) или AIC8800D80 (SDIO `c8a1`) |
| Ethernet | IP101GR |
| Камера | внутренняя **USB UVC** (`1b17:0211` / `0bda:2161`) за хабом `1a40:0101` |
| Кнопка питания | GPIO-кнопка |
| Загрузка | SD-карта или eMMC |

MIPI-камер (GC2145 / OV5648) на плате **нет** — они не распаяны.

## Что работает (проверено на железе)

- [x] Дисплей и подсветка (профиль панели 224)
- [x] Тачскрин
- [x] Ethernet (IP101GR)
- [x] WiFi 2.4/5 ГГц — AP6212 (`brcmfmac`) или AIC8800D80 (HE, Wi-Fi 6)
- [x] Bluetooth — AP6212 (BCM43430A1, HCI 4.0) или AIC8800D80 (HCI 5.4)
- [x] Звук: динамик, наушники, микрофон (RK809)
- [x] Глушение динамика при вставке проводных наушников
- [x] USB-камера (UVC): повёрнутая виртуальная камера `/dev/video10`
- [x] Датчик температуры (TSADC) и троттлинг CPU/GPU
- [x] USB host (в т.ч. OTG-порт в режиме host)
- [x] Установка на eMMC
- [x] Уникальное имя хоста (несколько планшетов в одной сети)
- [x] Загрузка с microSD

## Требования к сборочной машине

- Linux x86_64 (проверено на Debian 13 trixie)
- Docker; пользователь должен быть в группе `docker`
- ~50 ГБ свободного места
- 8 ГБ RAM (на 4 ГБ собирается, но долго)
- Интернет

Установка Docker (если ещё нет): <https://docs.docker.com/engine/install/>

```bash
sudo usermod -aG docker "$USER"   # затем перелогиниться
```

## Сборка

```bash
# 1. Каркас Armbian на проверенном коммите
git clone https://github.com/armbian/build.git armbian-build
cd armbian-build
git checkout 51d1cc65daa425010bc93d7fcff75ffdecc90670

# 2. Этот репозиторий — как userpatches
rm -rf userpatches
git clone https://github.com/jacobtey-sudo/armbian-ys-f66c.git userpatches

# 3. Сборка
./compile.sh ys-f66c build
```

Готовый консольный образ появится в `output/images/`:

```
output/images/Armbian-unofficial_*_Ys-f66c_trixie_vendor_*.img
```

Первая сборка — около 3 часов (ядро + rootfs). Повторная заметно
быстрее: ядро, пакеты и ccache кэшируются в `cache/`.

Сборка идёт в Docker-контейнере, root на хосте не нужен — достаточно членства
в группе `docker`.

## Запись образа на SD-карту

```bash
# ВНИМАНИЕ: /dev/sdX — это именно ваша SD-карта, а не системный диск!
sudo dd if=output/images/Armbian-..._trixie_vendor_*.img \
        of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Либо balenaEtcher / Raspberry Pi Imager («Use custom image»).

Вставьте SD-карту в планшет и включите. При первом запуске — стандартная
первичная настройка Armbian (root-пароль, пользователь, WiFi).

## Установка на eMMC

Загрузитесь с SD-карты и перенесите систему на eMMC:

```bash
sudo armbian-install --target /dev/mmcblk0 --boot emmc --fs ext4 --yes
```

Интерактивный вариант: `sudo armbian-install`, затем выбрать eMMC.
После установки выключите планшет, выньте SD-карту и включите снова.
Установка проверена: система загружается с `/dev/mmcblk0p1`.

## Уникальное имя хоста

При первом запуске сервис `ys-f66c-hostname` берёт последние 4 цифры
серийного номера SoC и задаёт имя `ys-f66c-XXXX`. Серийный номер
`0000000000000000` даёт `ys-f66c-XXXX`. Сервис меняет имя, только пока
`/etc/hostname` содержит значение по умолчанию `ys-f66c`, поэтому имя,
заданное вручную, не перезаписывается.

## Что лежит в репозитории

| Путь | Назначение |
|---|---|
| `config-ys-f66c.conf` | Параметры сборки: BOARD, BRANCH, RELEASE, консоль |
| `config/boards/ys-f66c.csc` | Описание платы: DTB, WiFi/BT, U-Boot, железные хуки |
| `kernel/rk35xx-vendor-6.1/dt/rk3566-ys-f66c.dts` | Device Tree платы |
| `kernel/rk35xx-vendor-6.1/0000.patching_config.yaml` | Настройка патчей ядра |
| `bootenv/ys-f66c.txt` | bootenv: UART-лог, earlycon |
| `docs/*-STATUS.md` | Подробные заметки по отладке железа |
| `docs/CAMERA.md` | Поворот камеры: сервис, настройка, ограничения |
| `packages/` | Исходник v4l2loopback и файлы сервиса камеры |
| `docs/reference/` | Справочные DTS/патчи других веток (в сборке не участвуют) |

`config-example.conf` — стандартный шаблон Armbian. `customize-image.sh` —
хук образа: правит битый список файлов dpkg в trixie.

## Документация

| Документ | Содержание |
| --- | --- |
| [docs/PANEL-STATUS.md](docs/PANEL-STATUS.md) | Панель и подсветка: профиль, DSI-флаги, отладка |
| [docs/WIFI-STATUS.md](docs/WIFI-STATUS.md) | WiFi: ревизии платы, драйверы, прошивки |
| [docs/BT-STATUS.md](docs/BT-STATUS.md) | Bluetooth: serdev, прошивки, выбор DTB |
| [docs/AUDIO-STATUS.md](docs/AUDIO-STATUS.md) | Звук rk809: динамик, наушники, микрофон, BT |
| [docs/CAMERA.md](docs/CAMERA.md) | Поворот USB-камеры: сервис и настройка |
| [docs/reference/mainline-6.18/README.md](docs/reference/mainline-6.18/README.md) | Mainline 6.18: что работает (справочно, в сборке не участвует) |

## Прекомпилированные артефакты

Часть файлов в репозитории — готовые бинарники; исходников в дереве нет.

| Файл | Что это |
|---|---|
| `packages/v4l2loopback-*.ko` | Запасной модуль виртуальной камеры; используется, только если сборка из `packages/v4l2loopback-0.13.2.tar.gz` не удалась |
| `packages/ys-f66c-misc-gpio/misc-gpio-*.ko` | То же для драйвера MCU (исходник `misc-gpio.c` рядом) |
| `docs/YS-F66C Specifications (Chinese).pdf` | Спецификация платы от производителя (китайский язык). В открытом доступе её нет — хранится здесь как единственный источник |

## Ключевые исправления

### Панель
Профиль панели 224 (полная `panel-init-sequence`), `dsi,flags = 0xa03`
(VIDEO | BURST | NO_EOT_PACKET | LPM), reset active-low. Профиль 35 не подходит.

### WiFi / Bluetooth
Платы выпускаются в двух ревизиях. Ревизию определяет SDIO vendor:

* `02d0:a9a6` — AP6212, Broadcom BCM43430A1. WiFi — встроенный `brcmfmac`,
  BT — serdev `brcm,bcm43430a1-bt` на uart1, прошивка `brcm/BCM43430A1.hcd`.
* `c8a1` — AIC8800D80. WiFi — расширение `radxa-aic8800` (DKMS), BT — serdev
  `cvte,aic8800-bt`; прошивку грузит AIC SDIO-драйвер.

Базовый DTB рассчитан на AP6212. На ревизии AIC8800 служба
`ys-f66c-bt-dtb.service` при первом запуске переключает `fdtfile` на
`rk3566-ys-f66c-aic.dtb` и один раз перезагружает планшет.
Служба `ys-f66c-bt-unblock.service` выполняет `rfkill unblock bluetooth`.
Подробности — `docs/BT-STATUS.md`.

### Питание USB-хаба и портов
Вендорский драйвер `usb-host-power-gpio` отсутствует в ядре 6.1. Заменён на
`gpio-hog`: `usb_hub_gpio` = gpio1 RK_PD3, `vcc_host` = gpio3 PA1/PA3/PA4.
Без этого не поднимается USB-камера. В вендорском DTS был неверный пин
`RK_PC3` вместо `RK_PD3`.

### Камера
Камера — не MIPI, а USB UVC (`1b17:0211` / `0bda:2161`) за хабом `1a40:0101`.
Нерабочие MIPI-узлы из DTS удалены. Сенсор портретный, поэтому сервис
`ys-f66c-camera-rotate` пишет повёрнутую картинку в `/dev/video10`.
Подробности — `docs/CAMERA.md`.

### Ядро
Vendor 6.1.172, закреплён на коммите
`a21efefcf2b5731d1df0505ddf725af6e5530cfb`.
Драйверы панели и подсветки встроены в ядро (`=y`), иначе DSI-хост не
дожидается панели до монтирования rootfs.

## Другие варианты ядра (справочно)

В `docs/reference/` лежат наработки по другим веткам. В сборке этого образа они
**не участвуют**, но полезны как источник данных по железу:

- `docs/reference/mainline-6.18/` — mainline 6.18: работают HDMI (видео и звук),
  Ethernet (RMII, IP101GR) и USB 2.0. MIPI-панель, тач, звук и камера не проверялись.
- `docs/reference/vendor-4.19/` — вендорский BSP DTS 4.19 и патчи.
- `docs/reference/rk3566-youngfeel-yf023d.dts` — DTS соседней платы.

Итого: **vendor 6.1** (этот репозиторий) — полностью рабочий планшет
(панель, тач, звук, WiFi, BT, USB-камера), но с проблемой HDMI + встроенный экран.
**Mainline 6.18** — наоборот: HDMI и Ethernet, но без панели/тача/звука.

## Известные проблемы

- **HDMI + встроенный экран одновременно**: на десктопном образе (Plasma 6)
  не проверялось; используйте один выход.
- MIPI-камер нет; работает только USB-камера.
- Видеозвонки через PipeWire (браузер) могут брать сырую камеру без
  поворота: поворот сделан на уровне V4L2/GStreamer.

## Полезные команды на устройстве

```bash
# камера
lsusb | grep -iE "1b17|0bda"
v4l2-ctl --list-devices
systemctl status ys-f66c-camera-rotate

# питание USB-хаба/портов (все линии должны быть out hi)
cat /sys/kernel/debug/gpio | grep usb-

# WiFi/BT
nmcli device status
bluetoothctl show
dmesg | grep -iE "brcmfmac|brcm|aic8800|bluetooth"

# ядро
dmesg | grep -iE "panel|dsi|aic8800|uvc"
```

UART-консоль: uart2, **1500000 8N1** (включён earlycon в `bootenv/ys-f66c.txt`).

## Лицензия

Скрипты и board-support — производные от Armbian и ядра Linux, **GPL-2.0**.
Device Tree — `GPL-2.0+ OR MIT`.

## Благодарности

- [Armbian build framework](https://github.com/armbian/build)
- [armbian/linux-rockchip](https://github.com/armbian/linux-rockchip)
- Armbian extension `radxa-aic8800` (DKMS-драйвер AIC8800)