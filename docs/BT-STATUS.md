# Bluetooth YS-F66C — РАБОТАЕТ

Статус на 09.11.2026: BT поднят на ревизии AP6212, сканирование находит
устройства. Вторая ревизия (AIC8800) использует отдельный DTB.

## Две ревизии железа

| Ревизия | SDIO WiFi | BT-чип | Драйвер BT | DTB |
|---------|-----------|--------|------------|-----|
| AP6212 (Broadcom) | `02d0:a9a6` (brcmfmac) | BCM43430A1 | `hci_uart_bcm` | `rk3566-ys-f66c.dtb` (по умолчанию) |
| AIC8800D80 | `c8a1` (radxa-aic8800) | AIC8800 | `hci_uart_aic` | `rk3566-ys-f66c-aic.dtb` |

Проверено на AP6212 (09.11.2026):

```
hci0:  Bus: UART
       BD Address: 00:11:22:33:44:66
       UP RUNNING
       HCI Version: 4.0 (0x6)
       Manufacturer: 15 (0x000f, Broadcom)
       Name: 'ys-f66c-XXXX'
```

`bluetoothctl --timeout 30 scan on` находит соседние устройства
(`W2`, `Redmi Smart Band 2 B30D`).

Проверено на AIC8800 (08.11.2026): hci0 AIC8820, HCI 5.4, скан работает.

## Как это устроено

BT подключён к **UART1** (`serial@fe650000`, `/dev/ttyS1`). Ядро Armbian 6.1
содержит оба serdev-драйвера; драйвер выбирает `compatible` дочернего узла:

* `brcm,bcm43430a1-bt` — `hci_uart_bcm`; сам грузит `brcm/BCM43430A1.hcd`;
* `cvte,aic8800-bt` — `hci_uart_aic`; BT-прошивку грузит AIC SDIO-драйвер
  (`request_module("aic8800_fdrv_sdio")`).

`hciattach` не нужен. Питание и reset держит Rockchip `rfkill-bt`
(узел `bluetooth-platdata`).

## Выбор DTB при первом запуске

Базовый DTB рассчитан на AP6212, чтобы BT работал сразу после установки.
Служба `ys-f66c-bt-dtb.service` при первом запуске читает SDIO id:

* `c8a1` — пишет `fdtfile=rockchip/rk3566-ys-f66c-aic.dtb` в
  `/boot/armbianEnv.txt` и один раз перезагружается;
* иначе — ставит маркер `/etc/ys-f66c-bt-dtb.done` и больше не запускается.

## Карта пинов (из Android DT)

| Сигнал            | GPIO            |
|-------------------|-----------------|
| BT reset          | GPIO1_D1 (active high) |
| BT wake           | GPIO0_C7 (active high) |
| BT host wake irq  | GPIO1_D2 (active high) |
| UART RTS          | GPIO2_B5 (active low)  |
| UART1 TX/RX       | GPIO2_B4 / GPIO2_B3 (m0) |
| UART1 CTS         | GPIO2_B6 (m0)          |

## rfkill

Rockchip `rfkill-bt` может держать BT в сбросе. Служба
`ys-f66c-bt-unblock.service` выполняет `rfkill unblock bluetooth` после
`bluetooth.service`.

## Проверка

```bash
hciconfig -a
bluetoothctl show
bluetoothctl --timeout 30 scan on
```

## Примечание для AIC8800

`aic_setup()` запрашивает модуль ровно `aic8800_fdrv_sdio`. В ручной сборке
Radxa DKMS модуль называется `aic8800_fdrv`, поэтому нужен alias:

```
/etc/modprobe.d/aic-bt.conf
alias aic8800_fdrv_sdio aic8800_fdrv
```

Расширение `radxa-aic8800` ставит модули с суффиксом `_sdio`; alias не нужен.
