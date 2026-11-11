#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

APP_DIR="/opt/blaze-game"
TOKEN_FILE="/etc/blaze-game/github-token"
REPO="https://github.com/FeelFonk26/BLAZE-GAME.git"
COMPOSE_FILE="docker-compose.production.yml"
AUTH_DIR=""

log() { printf '\n[BLAZE updater] %s\n' "$*"; }
fail() { printf '\n[BLAZE updater] ERROR: %s\n' "$*" >&2; exit 1; }
cleanup() {
  unset GIT_ASKPASS GIT_TERMINAL_PROMPT BLAZE_GITHUB_TOKEN_FILE 2>/dev/null || true
  if [[ -n "$AUTH_DIR" && -d "$AUTH_DIR" ]]; then rm -rf -- "$AUTH_DIR"; fi
}
trap cleanup EXIT
trap 'fail "Установка прервана на строке $LINENO. Контейнеры и данные БД не удалялись."' ERR

[[ "$EUID" -eq 0 ]] || fail "Запусти скрипт от root."
command -v git >/dev/null || fail "Git не установлен."
command -v docker >/dev/null || fail "Docker не установлен."
docker compose version >/dev/null 2>&1 || fail "Docker Compose недоступен."
command -v systemctl >/dev/null || fail "systemd недоступен."
[[ -d "$APP_DIR/.git" ]] || fail "$APP_DIR не является Git-репозиторием BLAZE."
[[ -f "$APP_DIR/.env" ]] || fail "Не найден $APP_DIR/.env."
[[ -f "$TOKEN_FILE" && -s "$TOKEN_FILE" ]] || fail "Не найден GitHub read-only token: $TOKEN_FILE."
[[ "$(stat -c '%a' "$TOKEN_FILE")" == "600" ]] || fail "Права $TOKEN_FILE должны быть 0600."
[[ "$(git -C "$APP_DIR" branch --show-current)" == "main" ]] || fail "Репозиторий должен находиться на main."
[[ "$(git -C "$APP_DIR" remote get-url origin)" == "$REPO" ]] || fail "У репозитория неожиданный origin."
[[ -z "$(git -C "$APP_DIR" status --porcelain)" ]] || fail "В репозитории есть локальные изменения. Сначала разберись с ними вручную."

AUTH_DIR="$(mktemp -d /tmp/blaze-updater-auth.XXXXXX)"
chmod 700 "$AUTH_DIR"
cat > "$AUTH_DIR/askpass" <<'ASKPASS'
#!/bin/sh
case "$1" in
  *Username*) printf '%s\n' "x-access-token" ;;
  *Password*) cat "$BLAZE_GITHUB_TOKEN_FILE" ;;
  *) exit 1 ;;
esac
ASKPASS
chmod 700 "$AUTH_DIR/askpass"
export GIT_ASKPASS="$AUTH_DIR/askpass"
export GIT_TERMINAL_PROMPT=0
export BLAZE_GITHUB_TOKEN_FILE="$TOKEN_FILE"

log "Получаю актуальный main приватного репозитория"
git -C "$APP_DIR" fetch origin main
git -C "$APP_DIR" merge --ff-only origin/main
unset GIT_ASKPASS GIT_TERMINAL_PROMPT BLAZE_GITHUB_TOKEN_FILE
cleanup
AUTH_DIR=""

for file in deploy/updater/update.sh deploy/updater/git-askpass deploy/updater/updater-server.py deploy/updater/blaze-game-updater.socket deploy/updater/blaze-game-updater.service deploy/updater/blaze-game-update-runner.service; do
  [[ -s "$APP_DIR/$file" ]] || fail "Не найден обязательный файл $APP_DIR/$file."
done
[[ -f "$APP_DIR/$COMPOSE_FILE" ]] || fail "Не найден production compose."
docker compose --project-directory "$APP_DIR" --env-file "$APP_DIR/.env" -f "$APP_DIR/$COMPOSE_FILE" config --services | grep -qx bot || fail "В production compose не найден сервис bot."

if [[ -d /run/blaze-game-updater.sock && ! -S /run/blaze-game-updater.sock ]]; then
  fail "/run/blaze-game-updater.sock уже существует как каталог, а не socket. Ничего не удаляю автоматически."
fi

log "Устанавливаю ограниченный systemd updater"
install -d -m 0755 /etc/blaze-game /usr/local/libexec/blaze-game
install -m 0755 "$APP_DIR/deploy/updater/update.sh" /usr/local/sbin/blaze-game-update
install -m 0755 "$APP_DIR/deploy/updater/git-askpass" /usr/local/libexec/blaze-game/git-askpass
install -m 0755 "$APP_DIR/deploy/updater/updater-server.py" /usr/local/libexec/blaze-game/updater-server.py
install -m 0644 "$APP_DIR/deploy/updater/blaze-game-updater.socket" /etc/systemd/system/blaze-game-updater.socket
install -m 0644 "$APP_DIR/deploy/updater/blaze-game-updater.service" /etc/systemd/system/blaze-game-updater.service
install -m 0644 "$APP_DIR/deploy/updater/blaze-game-update-runner.service" /etc/systemd/system/blaze-game-update-runner.service
touch /var/log/blaze-game-update.log
chmod 0600 /var/log/blaze-game-update.log
systemctl daemon-reload
systemctl enable --now blaze-game-updater.socket
systemctl restart blaze-game-updater.service
systemctl is-active --quiet blaze-game-updater.socket || fail "systemd socket не запустился."
[[ -S /run/blaze-game-updater.sock ]] || fail "systemd не создал Unix socket."

log "Собираю только bot и пересоздаю только bot, чтобы подключить socket и актуальную команду /restart"
cd "$APP_DIR"
docker compose --env-file .env -f "$COMPOSE_FILE" build bot
docker compose --env-file .env -f "$COMPOSE_FILE" up -d --no-deps --force-recreate bot
docker compose --env-file .env -f "$COMPOSE_FILE" ps bot

log "Проверяю socket и службы"
systemctl is-active --quiet blaze-game-updater.socket
[[ -S /run/blaze-game-updater.sock ]]
printf '\nУстановка updater завершена. PostgreSQL, API и web не пересоздавались.\n'
printf 'Теперь проверь /restart в личном чате с @BlazeGameAppBot от аккаунта владельца.\n'
