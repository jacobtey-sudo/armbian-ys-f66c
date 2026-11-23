# Overlay

Файлы, которые кладутся в образ как есть. Сейчас это desktop-конфиги из
`/etc/skel`, унаследованные новыми пользователями:

- `etc/skel/.config/kwinrc`, `kwinoutputconfig.json` — compositor, поворот, DPMS;
- `etc/skel/.config/kdedefaults/` — дефолты KWin/Plasma;
- `etc/skel/.config/plasma-org.kde.plasma.desktop-appletsrc` — панель и апплеты
  (включая Window Buttons и виджет eMMC с диаграммой);
- `etc/skel/.config/kglobalshortcutsrc`, `kxkbrc`, `plasma-localerc` — раскладки
  и локаль;
- `etc/skel/.config/bluedevilglobalrc` — Bluetooth;
- `etc/skel/.config/gtk-3.0/`, `gtk-4.0/` — тема GTK;
- прочие `*-rc` приложений KDE.

Скрипты:

- `usr/local/bin/ys-f66c-install-flclash` — ставит FlClash (arm64) из
  зафиксированного релиза. SHA256 проверяется, `.deb` в git не хранится.
  `customize-image.sh` запускает скрипт при сборке образа.

Maliit (экранная клавиатура):

- `usr/share/maliit/keyboard2/devices/ys-f66c-{small,medium,large}.json` — размеры;
- `usr/share/glib-2.0/schemas/99-ys-f66c-maliit.gschema.override` — языки en/ru;
- `usr/local/bin/ys-f66c-osk-scale` и
  `usr/share/applications/ys-f66c-osk-scale.desktop` — выбор размера;
- `usr/local/bin/xdg-open` — снимает `QT_WAYLAND_SHELL_INTEGRATION` от Maliit,
  обрабатывает схему `ys-osk:`, остальные URL отдаёт `/usr/bin/xdg-open`;
- `usr/lib/aarch64-linux-gnu/maliit/keyboard2/qml/keys/LanguageMenu.qml` —
  пункт «Settings...» открывает `ys-osk:scale`.

`scripts/build.sh` копирует `overlay/.` поверх board support, а
`scripts/install-overlay.sh` ставит то же самое на живую систему.

Не добавлять:

- пароли, токены, SSH-ключи;
- машинно-зависимые hostname, serial и MAC;
- абсолютные домашние пути конкретного пользователя;
- большие бинарники.

---

[← Mainline 6.18](../docs/reference/mainline-6.18/README.md) · [Оглавление](../README.md#документация)
