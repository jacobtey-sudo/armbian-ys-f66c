# ys-f66c: панель (2026-11-08)

Плата: 192.168.1.10.

## Итог

Панель работает под Armbian. Изображение видно.

Рабочая конфигурация: Android-профиль 224.

## Причина прошлых сбоев

- Профиль 35 не подходит этой панели.
- Не хватало бита `MIPI_DSI_MODE_NO_EOT_PACKET` (BIT(9)).

## Рабочий конфиг

- Полная `panel-init-sequence` из U-Boot `panel-initcode224` (983 байта).
  Таблица побайтно равна `mipi_para_choose/panel-initcode224` живого Android.
- Тайминг 224: 70 МГц, hback 40, hfront 60, hsync 30, vback 12, vfront 18, vsync 4.
- `dsi,flags = 0xa03` (VIDEO | BURST | NO_EOT_PACKET | LPM).
- `dsi,lanes = 4`.
- `reset-gpios` = `GPIO_ACTIVE_LOW`. Иначе панель держится в сбросе.

## Проверено на железе

- Режим: 800x1280p57.28. dclk 70 МГц.
- DSI-Link: 450 x 4 Mbps.
- VP1 ACTIVE, backlight1 200/236.
- В логе нет ошибок `failed to write dcs cmd`.
- sddm активен, VT2.

## Открыто

- U-Boot платы выбирает профиль 35. Ядро Armbian шлёт 224.
- EEPROM отдаёт 224 и 35.
- Нет даташита PXZ-101-P005.

## Файлы

- DTS: `kernel/rk35xx-vendor-6.1/dt/rk3566-ys-f66c.dts`
- Эталон: `~/board/android-reference-224.md`
- Дамп живого DT Android: `~/board/android-dump/`
- Подробный статус: `~/board/DSI-PANEL-STATUS.md`
