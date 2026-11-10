#!/usr/bin/env bash
set -Eeuo pipefail
umask 077

APP_DIR="/opt/blaze-game"
DOMAIN="blazegame.duckdns.org"
REPO="https://github.com/FeelFonk26/BLAZE-GAME.git"
COMPOSE_FILE="docker-compose.production.yml"
NGINX_SITE="/etc/nginx/sites-available/blazegame"
NGINX_LINK="/etc/nginx/sites-enabled/blazegame"
AUTH_DIR=""
AUTH_FILE=""

log() { printf '\n\033[1;36m[BLAZE] %s\033[0m\n' "$*"; }
fail() { printf '\n[BLAZE] ОШИБКА: %s\n' "$*" >&2; exit 1; }
cleanup() {
  unset GIT_ASKPASS GIT_TERMINAL_PROMPT BLAZE_GITHUB_TOKEN_FILE 2>/dev/null || true
  if [[ -n "$AUTH_DIR" && -d "$AUTH_DIR" ]]; then rm -rf -- "$AUTH_DIR"; fi
  return 0
}
trap cleanup EXIT
trap 'fail "Установка прервалась на строке $LINENO. Существующие службы TASKORA не останавливались."' ERR

[[ "$EUID" -eq 0 ]] || fail "Запусти скрипт от root: sudo bash /tmp/blaze-install.sh"
command -v docker >/dev/null || fail "Docker не установлен."
docker compose version >/dev/null 2>&1 || fail "Docker Compose не установлен."
command -v nginx >/dev/null || fail "Nginx не установлен."
systemctl is-active --quiet nginx || fail "Nginx не активен. Существующие сайты не трогаю."
command -v git >/dev/null || fail "Git не установлен."
command -v python3 >/dev/null || fail "Python 3 не установлен."
command -v openssl >/dev/null || fail "OpenSSL не установлен."

printf '\nНужен GitHub Personal Access Token с доступом только Contents: Read-only к приватному FeelFonk26/BLAZE-GAME.\n'
printf 'Создать токен можно здесь: https://github.com/settings/personal-access-tokens/new\n'
printf 'Ввод скрыт. Токен не будет сохранён в Git remote, .env или истории команд.\n'
read -r -s -p "GitHub read-only token: " GITHUB_TOKEN_VALUE
printf '\n'
[[ -n "$GITHUB_TOKEN_VALUE" ]] || fail "GitHub-токен не введён."

AUTH_DIR="$(mktemp -d /tmp/blaze-git-auth.XXXXXX)"
chmod 700 "$AUTH_DIR"
AUTH_FILE="$AUTH_DIR/token"
printf '%s' "$GITHUB_TOKEN_VALUE" > "$AUTH_FILE"
chmod 600 "$AUTH_FILE"
unset GITHUB_TOKEN_VALUE
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
export BLAZE_GITHUB_TOKEN_FILE="$AUTH_FILE"

log "Проверяю доступ к приватному репозиторию"
git ls-remote "$REPO" refs/heads/main >/dev/null || fail "GitHub не дал прочитать FeelFonk26/BLAZE-GAME. Проверь, что токен имеет Contents: Read-only именно для этого репозитория."
log "Проверяю DNS домена"
DNS_IP="$(getent ahostsv4 "$DOMAIN" | awk 'NR==1 {print $1}')"
[[ "$DNS_IP" == "157.228.125.45" ]] || fail "$DOMAIN сейчас разрешается в '$DNS_IP', ожидался 157.228.125.45. Проверь DuckDNS."

log "Подготавливаю каталог проекта"
if [[ -d "$APP_DIR/.git" ]]; then
  CURRENT_BRANCH="$(git -C "$APP_DIR" branch --show-current)"
  [[ "$CURRENT_BRANCH" == "main" ]] || fail "$APP_DIR уже существует на ветке '$CURRENT_BRANCH'. Автоматически переключать ветки не буду."
  [[ -z "$(git -C "$APP_DIR" status --porcelain)" ]] || fail "$APP_DIR содержит локальные изменения. Ничего не перезаписываю."
  ORIGIN="$(git -C "$APP_DIR" remote get-url origin)"
  [[ "$ORIGIN" == "$REPO" ]] || fail "У $APP_DIR другой origin ($ORIGIN). Ничего не меняю."
  git -C "$APP_DIR" pull --ff-only origin main
elif [[ ! -e "$APP_DIR" ]]; then
  git clone --branch main --single-branch "$REPO" "$APP_DIR"
elif [[ -d "$APP_DIR" ]] && [[ -z "$(find "$APP_DIR" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  rmdir "$APP_DIR"
  git clone --branch main --single-branch "$REPO" "$APP_DIR"
else
  fail "$APP_DIR существует, но это не Git-репозиторий или каталог не пуст. Ничего не удаляю."
fi
cleanup
AUTH_DIR=""
AUTH_FILE=""
cd "$APP_DIR"
[[ -f "$COMPOSE_FILE" && -f "production.env.example" && -f "deploy/nginx-host.conf" ]] || fail "В репозитории отсутствуют необходимые production-файлы."

log "Создаю закрытую конфигурацию"
if [[ ! -f .env ]]; then
  cp production.env.example .env
fi
chmod 600 .env
grep -q '^POSTGRES_PASSWORD=' .env || fail "В .env нет POSTGRES_PASSWORD."
grep -q '^BOT_TOKEN=' .env || fail "В .env нет BOT_TOKEN."
grep -q '^DOMAIN=' .env || fail "В .env нет DOMAIN."
grep -q '^WEB_APP_URL=' .env || fail "В .env нет WEB_APP_URL."

python3 - <<'PY'
from pathlib import Path
p = Path(".env")
lines = p.read_text().splitlines()
updates = {"DOMAIN": "blazegame.duckdns.org", "WEB_APP_URL": "https://blazegame.duckdns.org"}
seen = set()
out = []
for line in lines:
    if "=" in line and not line.lstrip().startswith("#"):
        key = line.split("=", 1)[0]
        if key in updates:
            out.append(f"{key}={updates[key]}")
            seen.add(key)
            continue
    out.append(line)
for key, value in updates.items():
    if key not in seen:
        out.append(f"{key}={value}")
p.write_text("\n".join(out) + "\n")
PY

if grep -q '^POSTGRES_PASSWORD=replace_with_a_long_random_password$' .env; then
  DB_PASSWORD="$(openssl rand -hex 32)"
  DB_PASSWORD_VALUE="$DB_PASSWORD" python3 - <<'PY'
import os
from pathlib import Path
p = Path(".env")
lines = p.read_text().splitlines()
lines = [("POSTGRES_PASSWORD=" + os.environ["DB_PASSWORD_VALUE"]) if x.startswith("POSTGRES_PASSWORD=") else x for x in lines]
p.write_text("\n".join(lines) + "\n")
PY
  unset DB_PASSWORD DB_PASSWORD_VALUE
fi

if grep -q '^BOT_TOKEN=replace_with_BotFather_token$' .env; then
  printf '\nВставь токен BotFather для @BlazeGameAppBot. Ввод скрыт, токен не появится на экране.\n'
  read -r -s -p "BOT_TOKEN: " BOT_TOKEN_VALUE
  printf '\n'
  [[ -n "$BOT_TOKEN_VALUE" ]] || fail "Пустой токен."
  BOT_TOKEN_VALUE="$BOT_TOKEN_VALUE" python3 - <<'PY'
import os
from pathlib import Path
p = Path(".env")
lines = p.read_text().splitlines()
token = os.environ["BOT_TOKEN_VALUE"]
lines = [("BOT_TOKEN=" + token) if x.startswith("BOT_TOKEN=") else x for x in lines]
p.write_text("\n".join(lines) + "\n")
PY
  unset BOT_TOKEN_VALUE
fi

grep -q '^BOT_TOKEN=replace_' .env && fail "В .env остался шаблон BOT_TOKEN."
grep -q '^POSTGRES_PASSWORD=replace_' .env && fail "В .env остался шаблон пароля базы."
chmod 600 .env

log "Собираю и запускаю изолированные контейнеры BLAZE"
docker compose --env-file .env -f "$COMPOSE_FILE" up -d --build

log "Добавляю отдельный виртуальный хост Nginx"
if [[ -e "$NGINX_SITE" || -L "$NGINX_SITE" ]]; then
  cmp -s "deploy/nginx-host.conf" "$NGINX_SITE" || fail "$NGINX_SITE уже существует и отличается. Не перезаписываю чужую конфигурацию."
else
  install -m 0644 "deploy/nginx-host.conf" "$NGINX_SITE"
fi
if [[ -L "$NGINX_LINK" ]]; then
  [[ "$(readlink -f "$NGINX_LINK")" == "$NGINX_SITE" ]] || fail "Ссылка $NGINX_LINK указывает на другой файл."
elif [[ -e "$NGINX_LINK" ]]; then
  fail "$NGINX_LINK уже существует и не является ожидаемой ссылкой."
else
  ln -s "$NGINX_SITE" "$NGINX_LINK"
fi
nginx -t
systemctl reload nginx

log "Проверяю Certbot и выпускаю HTTPS"
if ! command -v certbot >/dev/null; then
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y certbot python3-certbot-nginx
fi
certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos --register-unsafely-without-email --redirect

log "Проверяю BLAZE"
docker compose --env-file .env -f "$COMPOSE_FILE" ps
curl --retry 12 --retry-delay 5 --retry-connrefused -fsS "https://$DOMAIN/health"

printf '\nBLAZE GAME deployment finished.\n'
printf 'Mini App: https://%s\n' "$DOMAIN"
printf 'Bot: @BlazeGameAppBot\n'
printf 'Project: %s\n' "$APP_DIR"
printf 'TASKORA service/configuration was not modified.\n'
