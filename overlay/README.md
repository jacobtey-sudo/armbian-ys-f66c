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

`scripts/build.sh` копирует `overlay/.` поверх board support, а
`scripts/install-overlay.sh` ставит то же самое на живую систему.

Не добавлять:

- пароли, токены, SSH-ключи;
- машинно-зависимые hostname, serial и MAC;
- абсолютные домашние пути конкретного пользователя;
- большие бинарники.
