# Камера: поворот изображения

## Проблема

Встроенная камера — USB UVC с портретным сенсором. Сырое изображение
повёрнуто на 90°. Аппаратного поворота у UVC нет, Kamoso поворот не умеет.

## Решение

Сервис `ys-f66c-camera-rotate` читает `/dev/video0` через GStreamer
(`videoflip`), поворачивает кадр и пишет в виртуальную камеру
`/dev/video10` (v4l2loopback). Приложения видят только её.

| Файл | Назначение |
|---|---|
| `/etc/systemd/system/ys-f66c-camera-rotate.service` | сервис |
| `/usr/local/sbin/ys-f66c-camera-start` | конвейер GStreamer |
| `/etc/default/ys-f66c-camera` | поворот и режим съёмки |
| `/etc/modprobe.d/ys-f66c-v4l2loopback.conf` | параметры v4l2loopback |
| `/etc/udev/rules.d/72-ys-f66c-hide-raw-camera.rules` | скрыть сырую камеру от пользователя |

## Настройка

Файл `/etc/default/ys-f66c-camera`:

- `ROTATE` — `none`, `clockwise`, `counterclockwise`, `rotate-180`;
- `WIDTH`, `HEIGHT`, `FPS` — режим съёмки (по умолчанию 640×480@30).

После правки: `systemctl restart ys-f66c-camera-rotate`.

## Kamoso и libcamera

GStreamer-провайдер libcamera скрывает все v4l2-устройства от
`GstDeviceMonitor`. Kamoso берёт первую камеру из этого списка, поэтому
виртуальную камеру не видел. Пакет `gstreamer1.0-libcamera` удалён при сборке.
Если он вернётся после обновления — удалить снова:
`sudo apt remove gstreamer1.0-libcamera`.

## Проверка

```bash
v4l2-ctl --list-devices
systemctl status ys-f66c-camera-rotate
gst-launch-1.0 v4l2src device=/dev/video10 num-buffers=1 ! jpegenc ! filesink location=/tmp/cam.jpg
```

## Ограничения

- Сырая камера (`/dev/video0`) доступна только root: её занимает сервис.
- Приложения через PipeWire (видеозвонки в браузере) могут использовать
  сырую камеру без поворота. Поворот проверен в Kamoso.
- Нагрузка: около 30 % одного ядра на поворот и около 60 % на предпросмотр
  Kamoso при 640×480@30.
