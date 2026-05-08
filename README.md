# tr-bridge

Distribution mirror для **bot-bridge** — daemon'а проекта [Torrent Checker](https://github.com/redkeyl/torrent-checker) (приватный репо) на стороне юзерского Mac.

Здесь живут только артефакты для установки:

- `install/mac.sh` — установщик для macOS.
- GitHub Releases (`bridge-vX.Y.Z`) с wheel'ами `bot_bridge-X.Y.Z-py3-none-any.whl`.

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/alexeylopatin/tr-bridge/main/install/mac.sh | bash -s -- <pair_code>
```

`pair_code` получается через `/connect` в Telegram-боте.

## Upgrade

```bash
curl -fsSL https://raw.githubusercontent.com/alexeylopatin/tr-bridge/main/install/mac.sh | bash
```

## Source

Исходники — в основном репо: <https://github.com/redkeyl/torrent-checker> (`bot-bridge/` модуль).
