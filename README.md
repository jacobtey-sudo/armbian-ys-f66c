# Armbian для планшета Yisheng YS-F66C (Rockchip RK3566)

Board-support (`userpatches`) для сборки Armbian с вендорским ядром Rockchip 6.1
и рабочим железом планшета YS-F66C.

**English TL;DR:** Board support (`userpatches`) for the Yisheng YS-F66C RK3566
tablet. Clone the Armbian build framework (pinned commit), clone this repo as
`userpatches/`, run `./compile.sh ys-f66c build`. See the build section below.

---

## Железо

| | |
|---|---|
| SoC | Rockchip RK3566 (4× Cortex-A55) |
| RAM / eMMC | 4 ГБ / 32 ГБ |
| Экран | 10.1", 800×1280, MIPI DSI |
| Тачскрин | Goodix GT9271 (I2C1, INT GPIO3_C6 / RST GPIO3_C7) |
| PMIC / звук | RK809 (динамик, наушники 3.5 мм, микрофон) |
| WiFi / BT | AIC8800D80 (SDIO / UART) |
| Ethernet | IP101GR PHY (не проверялся) |
| Камера | внутренняя **USB UVC** (Sonix `1b17:0211`) за USB-хабом `1a40:0101` |
| Кнопка питания | GPIO-кнопка → меню завершения работы KDE |
| Загрузка | SD-карта (eMMC занята заводским Android) |

MIPI-камер (GC2145 / OV5648) на плате **нет** — они не распаяны.

## Что работает (проверено на железе)

- [x] Дисплей и подсветка (Android-профиль панели 224)
- [x] Тачскрин
- [x] WiFi 2.4/5 ГГц, HE (Wi-Fi 6) — AIC8800D80
- [x] Bluetooth 5.4, A2DP/HFP — AIC8800D80
- [x] Звук: динамик, наушники, микрофон (RK809)
- [x] USB-камера (UVC): `/dev/video*`, MJPG/YUYV
- [x] USB host (в т.ч. OTG-порт в режиме host)
- [x] Кнопка питания → меню «Завершение работы»
- [x] KDE Plasma (SDDM, X11)

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

Готовый образ появится в `output/images/`:

```
output/images/Armbian-unofficial_*_Ys-f66c_noble_vendor_*_kde-plasma_desktop.img
```

Первая сборка — примерно 1.5–2.5 часа (ядро + rootfs). Повторная заметно
быстрее: ядро, пакеты и ccache кэшируются в `cache/`.

Сборка идёт в Docker-контейнере, root на хосте не нужен — достаточно членства
в группе `docker`.

## Запись образа на SD-карту

```bash
# ВНИМАНИЕ: /dev/sdX — это именно ваша SD-карта, а не системный диск!
sudo dd if=output/images/Armbian-..._kde-plasma_desktop.img \
        of=/dev/sdX bs=4M status=progress conv=fsync
sync
```

Либо balenaEtcher / Raspberry Pi Imager («Use custom image»).

Вставьте SD-карту в планшет и включите. При первом запуске — стандартная
первичная настройка Armbian (root-пароль, пользователь, WiFi).

## Что лежит в репозитории

| Путь | Назначение |
|---|---|
| `config-ys-f66c.conf` | Параметры сборки: BOARD, BRANCH, RELEASE, KDE |
| `config/boards/ys-f66c.csc` | Описание платы: DTB, WiFi/BT, U-Boot, хук кнопки питания |
| `kernel/rk35xx-vendor-6.1/dt/rk3566-ys-f66c.dts` | Device Tree платы |
| `kernel/rk35xx-vendor-6.1/0000.patching_config.yaml` | Настройка патчей ядра |
| `bootenv/ys-f66c.txt` | bootenv: UART-лог, earlycon |
| `docs/*-STATUS.md` | Подробные заметки по отладке железа |
| `docs/reference/` | Справочные DTS/патчи других веток (в сборке не участвуют) |

`config-example.conf` и `customize-image.sh` — стандартные файлы-шаблоны
Armbian, оставлены для совместимости.

## Ключевые исправления

### Панель
Android-профиль 224 (полная `panel-init-sequence`), `dsi,flags = 0xa03`
(VIDEO | BURST | NO_EOT_PACKET | LPM), reset active-low. Профиль 35 не подходит.

### WiFi / Bluetooth AIC8800D80
Плата притворяется Broadcom (`ap6212`), но SDIO vendor — `0xc8a1`.
Используется Armbian-расширение `radxa-aic8800` (DKMS). BT — serdev
`cvte,aic8800-bt` на uart1 + сервис разблокировки rfkill.

### Питание USB-хаба и портов
Вендорский драйвер `usb-host-power-gpio` отсутствует в ядре 6.1. Заменён на
`gpio-hog`: `usb_hub_gpio` = gpio1 RK_PD3, `vcc_host` = gpio3 PA1/PA3/PA4.
Без этого не поднимается USB-камера. В вендорском DTS был неверный пин
`RK_PC3` вместо `RK_PD3`.

### Камера
Камера — не MIPI, а USB UVC `1b17:0211` за хабом `1a40:0101`. После включения
питания хаба определяется автоматически (`/dev/video10`, `/dev/video11`).
Нерабочие MIPI-узлы из DTS удалены.

### Кнопка питания
powerdevil: `PowerButtonAction=16` (`PromptLogoutDialog`) в
`/etc/xdg/powerdevilrc` и `/etc/skel/.config/powerdevilrc`.
Короткое нажатие открывает меню завершения работы KDE.

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
- `docs/reference/vendor-4.19/` — вендорский Android/BSP DTS 4.19 и патчи.
- `docs/reference/rk3566-youngfeel-yf023d.dts` — DTS соседней платы.

Итого: **vendor 6.1** (этот репозиторий) — полностью рабочий планшет
(панель, тач, звук, WiFi, BT, USB-камера), но с проблемой HDMI + встроенный экран.
**Mainline 6.18** — наоборот: HDMI и Ethernet, но без панели/тача/звука.

## Известные проблемы

- **HDMI + встроенный экран одновременно**: plasmashell (Plasma 5.27) уходит
  в crash-loop. Только встроенный экран или только HDMI — стабильно.
- Наушники и динамик играют одновременно (нет jack-detect и глушения усилителя).
- MIPI-камер нет; работает только USB-камера.
- Ethernet (IP101GR) не проверялся.

## Полезные команды на устройстве

```bash
# камера
lsusb | grep -i 1b17
v4l2-ctl --list-devices

# питание USB-хаба/портов (все линии должны быть out hi)
cat /sys/kernel/debug/gpio | grep usb-

# WiFi/BT
nmcli device status
bluetoothctl show

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
