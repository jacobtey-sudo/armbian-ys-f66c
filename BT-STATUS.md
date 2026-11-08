# Bluetooth YS-F66C (AIC8800D80) — РАБОТАЕТ

Статус на 08.11.2026: BT поднят, HCI-устройство создаётся ядром, сканирование
эфира работает. Проверено на железе.

## Что получилось

```
hci0:  Type: Primary  Bus: UART
       BD Address: DC:EC:4F:99:D5:C3
       UP RUNNING
       HCI Version: 5.4 (0xd)  LMP Version: 5.4
       Manufacturer: 2875 (0x0b3b)
       Name: 'ys-f66c'
```

`bluetoothctl` видит контроллер, профили A2DP/HFP/A2DP-Sink зарегистрированы.
`bluetoothctl --timeout 20 scan on` находит соседние устройства (например `W2`).

## Как это устроено (и почему не как у Radxa)

BT у AIC8800 идёт по **UART1** (`serial@fe650000`, `/dev/ttyS1`), а не по SDIO.
В ядре Armbian 6.1 уже есть:

* `CONFIG_BT_HCIUART_AIC=y` — протокол AIC в `hci_uart` (`drivers/bluetooth/hci_aic.c`);
* `CONFIG_RFKILL_RK=y` — Rockchip `rfkill-bt` (`net/rfkill/rfkill-bt.c`).

`hci_aic` — это **serdev**-драйвер: он цепляется к дочернему узлу UART с
`compatible = "cvte,aic8800-bt"`. При открытии HCI он:
1. ждёт CTS до 10 с;
2. делает `request_module("aic8800_fdrv_sdio")` — SDIO-драйвер грузит BT-прошивку;
3. читает `HCI_OP_READ_LOCAL_NAME`.

Поэтому **`hciattach` не нужен** (в отличие от Radxa `aic-bluetooth`, который
дёргает `/dev/ttyS1`). Более того, `hciattach` конфликтовал бы с serdev.

Питание/reset BT держит Rockchip `rfkill-bt` (узел `bluetooth-platdata`).
При загрузке он **держит BT в сбросе (soft-blocked)**, пока userspace не
разблокирует `rfkill`. Без этого BlueZ оставляет `hci0` в состоянии DOWN.

## Карта пинов (из Android DT)

| Сигнал            | GPIO            |
|-------------------|-----------------|
| BT reset          | GPIO1_D1 (active high) |
| BT wake           | GPIO0_C7 (active high) |
| BT host wake irq  | GPIO1_D2 (active high) |
| UART RTS          | GPIO2_B5 (active low)  |
| UART1 TX/RX       | GPIO2_B4 / GPIO2_B3 (m0) |
| UART1 CTS         | GPIO2_B6 (m0)          |

(UART1 m0: RX=B3, TX=B4, CTS=B6, RTS=B5.)

## Изменения в DTS (`dt/rk3566-ys-f66c.dts`)

```dts
&uart1 {
	status = "okay";
	pinctrl-names = "default";
	pinctrl-0 = <&uart1m0_xfer &uart1m0_ctsn>;

	bluetooth {
		compatible = "cvte,aic8800-bt";
	};
};

/ {
	wireless_bluetooth: wireless-bluetooth {
		compatible = "bluetooth-platdata";
		clocks = <&rk809 1>;
		clock-names = "ext_clock";
		uart_rts_gpios = <&gpio2 RK_PB5 GPIO_ACTIVE_LOW>;
		pinctrl-names = "default", "rts_gpio";
		pinctrl-0 = <&uart1m0_rtsn>;
		pinctrl-1 = <&uart1_gpios>;
		BT,reset_gpio = <&gpio1 RK_PD1 GPIO_ACTIVE_HIGH>;
		BT,wake_gpio = <&gpio0 RK_PC7 GPIO_ACTIVE_HIGH>;
		BT,wake_host_irq = <&gpio1 RK_PD2 GPIO_ACTIVE_HIGH>;
		status = "okay";
	};
};

&pinctrl {
	wireless-bluetooth {
		uart1_gpios: uart1-gpios {
			rockchip,pins = <2 RK_PB5 RK_FUNC_GPIO &pcfg_pull_up>;
		};
	};
};
```

DTB: `421a781dfd4aae992a6b940ef1ba1c03` (164586 байт), задеплоен в
`/boot/dtb/rockchip/rk3566-ys-f66c.dtb` (бэкап `.bak-prebt`).

## Разблокировка rfkill при загрузке

`systemd-rfkill` запоминает состояние между ребутами
(`/var/lib/systemd/rfkill/platform-wireless-bluetooth:bluetooth = 0`), поэтому
на этой SD после одного `rfkill unblock bluetooth` BT поднимается сам.

Для **чистого образа** в конфиг платы добавлен systemd-хук:

* `post_family_tweaks_bsp__ys_f66c_bt_unblock` — ставит
  `/usr/lib/systemd/system/ys-f66c-bt-unblock.service`
  (`ExecStart=/usr/sbin/rfkill unblock bluetooth`);
* `post_family_tweaks__ys_f66c_enable_bt_unblock` — включает его.

## Важно про имена модулей

`aic_setup()` просит модуль ровно `aic8800_fdrv_sdio`. Так называются модули
из Radxa DKMS-пакета (`aic8800_fdrv_sdio.ko` и т.д.).

При **ручной** сборке (как сейчас на плате) модули называются без суффикса
(`aic8800_fdrv.ko`), поэтому добавлен `modprobe`-alias:

```
/etc/modprobe.d/aic-bt.conf
alias aic8800_fdrv_sdio aic8800_fdrv
```

При сборке образа через расширение `radxa-aic8800` alias **не нужен** —
модули уже называются `_sdio`.

## Как проверить вручную

```bash
rfkill unblock bluetooth
hciconfig hci0 up
hciconfig -a
bluetoothctl show
bluetoothctl --timeout 20 scan on
```

## Проверка звука (08.11.2026, наушники BW-HP2)

Наушники `BW-HP2` (`6F:2D:90:50:0B:A8`, class `audio-headset`) сопряжены,
trusted, подключены. PulseAudio (сессия `sddm`) создал
`bluez_sink.6F_2D_90_50_0B_A8.a2dp_sink` (SBC, 44.1 кГц, stereo) и сделал его
дефолтным. Проверено на слух:

* **A2DP** — стерео, левый/правый каналы (`speaker-test`, 1 кГц);
* **HFP** (`handsfree_head_unit`) — моно 8 кГц, слышно в обоих.

Транспорт BlueZ при проигрывании переходит в `active`, громкость `127`.

Полезно: PulseAudio на плате крутится под пользователем `sddm` (greeter),
поэтому `pactl` надо запускать так:

```bash
sudo -u sddm env XDG_RUNTIME_DIR=/run/user/113 \
  PULSE_SERVER=unix:/run/user/113/pulse/native pactl list short sinks
```

## Дальше

Звук/запись (микрофон rk809, запись с BT-гарнитуры) — отложенная задача.