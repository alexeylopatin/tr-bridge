#!/usr/bin/env bash
# bot-bridge installer for macOS.
# Spec: §9.2 automatization-mac-mvp.md (3.9 Mac+Transmission Bridge MVP).
#
# Usage:
#   bash install/mac.sh <pair_code>     # первая установка
#   bash install/mac.sh                 # upgrade (если уже paired в Keychain)
#
# Env overrides (для отладки/staging):
#   BOT_BRIDGE_VERSION   — версия wheel'а в GitHub Release (default: 0.1.0)
#   BOT_BRIDGE_WEBHOOK   — URL Cloud Run tg-webhook (default: prod URL ниже)
#   BOT_BRIDGE_REPO      — owner/name репо с релизом (default: alexeylopatin/tr-bridge)

set -euo pipefail

PAIR_CODE="${1:-}"

BRIDGE_VERSION="${BOT_BRIDGE_VERSION:-0.1.0}"
WEBHOOK_URL="${BOT_BRIDGE_WEBHOOK:-https://tg-webhook-nl2zzrzzgq-ew.a.run.app}"
BRIDGE_REPO="${BOT_BRIDGE_REPO:-alexeylopatin/tr-bridge}"
WHEEL_URL="https://github.com/${BRIDGE_REPO}/releases/download/bridge-v${BRIDGE_VERSION}/bot_bridge-${BRIDGE_VERSION}-py3-none-any.whl"

INSTALL_DIR="${HOME}/.local/share/bot-bridge"
PLIST="${HOME}/Library/LaunchAgents/com.alexey.bot-bridge.plist"

# 0. Xcode Command Line Tools (нужны для python3). Без CLT системный
#    /usr/bin/python3 — стуб, который при первом вызове открывает GUI-диалог
#    «Install» и блокирует терминал. Проверяем заранее, чтобы не словить
#    зависший shell в середине установки.
if ! xcode-select -p >/dev/null 2>&1; then
    cat <<'EOF' >&2
Xcode Command Line Tools не установлены — без них python3 в macOS
не работает (триггерит GUI-диалог).

Установи и перезапусти этот скрипт:
    xcode-select --install
EOF
    exit 1
fi

# 1. Проверка Transmission RPC. 401 = жив + auth настроен; 409 = жив + просит CSRF
#    session-id (Transmission так делает на первом запросе). Любой другой код
#    означает либо «не запущен», либо «без auth» — оба сценария требуют
#    вмешательства юзера.
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
                 -u "bot-bridge:dummy" \
                 http://127.0.0.1:9091/transmission/rpc || echo "000")
if [ "${HTTP_CODE}" != "401" ] && [ "${HTTP_CODE}" != "409" ]; then
    cat <<EOF >&2
Transmission не отвечает на 127.0.0.1:9091 (HTTP ${HTTP_CODE}).

Установка:
  brew install --cask transmission   # GUI-версия
или
  brew install transmission-cli      # headless-демон

Затем включи RPC:
  Transmission.app → Preferences → Remote → Enable Remote Access
  Username: bot-bridge
  Password: <придумай и запомни — попрошу ниже>

После — перезапусти этот скрипт.
EOF
    exit 1
fi

# 2. venv + установка wheel'а из GitHub Release.
mkdir -p "${INSTALL_DIR}"
python3 -m venv "${INSTALL_DIR}/.venv"
"${INSTALL_DIR}/.venv/bin/pip" install --upgrade pip --quiet
"${INSTALL_DIR}/.venv/bin/pip" install --quiet "${WHEEL_URL}"

# 3. Конфиг + пароль Transmission в Keychain. Пароль через stdin —
#    чтобы не светиться в `ps aux` на этапе config-init.
read -rsp "Transmission RPC password: " TRANS_PASSWORD; echo
printf '%s\n' "${TRANS_PASSWORD}" | \
    "${INSTALL_DIR}/.venv/bin/bot-bridge" config-init \
        --webhook-url "${WEBHOOK_URL}" \
        --transmission-password-stdin
unset TRANS_PASSWORD

# 4. Pair (обмен кода → device_token; токен в Keychain).
#    Idempotent: для upgrade-сценария (`bash install/mac.sh` без аргумента)
#    пропускаем pair-шаг, если устройство уже paired. status exit 0 =
#    config + device на месте + (webhook OK или временный network error);
#    status exit 1 = config/device отсутствует или токен revoked → нужен
#    свежий pair_code.
if "${INSTALL_DIR}/.venv/bin/bot-bridge" status >/dev/null 2>&1; then
    echo "Устройство уже paired (status OK) — pair-шаг пропускаю."
    if [ -n "${PAIR_CODE}" ]; then
        echo "  (pair_code '${PAIR_CODE}' проигнорирован; для перепаринга:"
        echo "   bot-bridge unpair && bash install/mac.sh <new_code>)"
    fi
else
    if [ -z "${PAIR_CODE}" ]; then
        cat <<'EOF' >&2
Устройство не paired, а pair_code не передан.

Получи код через /connect в Telegram-боте и перезапусти:
    bash install/mac.sh <pair_code>
EOF
        exit 1
    fi
    "${INSTALL_DIR}/.venv/bin/bot-bridge" pair "${PAIR_CODE}"
fi

# 5. launchd plist. KeepAlive с SuccessfulExit=false: при clean exit
#    (revoke / unpair / нет config'а) launchd НЕ перезапускает; при
#    crash (non-zero exit) — перезапускает.
cat > "${PLIST}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key><string>com.alexey.bot-bridge</string>
    <key>ProgramArguments</key>
    <array>
        <string>${INSTALL_DIR}/.venv/bin/bot-bridge</string>
        <string>serve</string>
    </array>
    <key>RunAtLoad</key><true/>
    <key>KeepAlive</key>
    <dict>
        <key>SuccessfulExit</key><false/>
    </dict>
    <key>StandardOutPath</key><string>${INSTALL_DIR}/bot-bridge.log</string>
    <key>StandardErrorPath</key><string>${INSTALL_DIR}/bot-bridge.err</string>
    <key>EnvironmentVariables</key>
    <dict>
        <key>PATH</key><string>/usr/local/bin:/opt/homebrew/bin:/usr/bin:/bin</string>
    </dict>
</dict>
</plist>
EOF

# Идемпотентность: повторный install (upgrade) не должен падать на
# `set -euo pipefail`, если plist уже залужен — сначала bootout
# (молча, если нечего выгружать).
launchctl bootout "gui/$(id -u)" "${PLIST}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "${PLIST}"

echo
echo "✅ bot-bridge установлен и запущен."
echo "  Версия:   ${BRIDGE_VERSION}"
echo "  Статус:   launchctl list | grep bot-bridge"
echo "  Логи:     tail -f ${INSTALL_DIR}/bot-bridge.log"
echo "  Деинстал: bot-bridge unpair && launchctl bootout gui/\$(id -u) ${PLIST}"
