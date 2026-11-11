# BLAZE GAME VPS Installer

Public installer for deploying the **private** `FeelFonk26/BLAZE-GAME` repository to the prepared Ubuntu VPS.

The game source code is not published in this repository.

## Install BLAZE on a fresh VPS

Run the full installer only on a fresh/prepared host where the BLAZE stack is not already deployed:

```bash
curl -fsSL https://raw.githubusercontent.com/FeelFonk26/BLAZE-GAME-Installer/main/install-vps.sh -o /tmp/blaze-install.sh && bash /tmp/blaze-install.sh
```

The installer configures Docker, the BLAZE stack, Nginx/HTTPS and the restricted updater. It asks for a GitHub Personal Access Token with **Contents: Read-only** access to the private `FeelFonk26/BLAZE-GAME` repository, the BotFather token if not configured, and the owner's numeric Telegram ID.

## Install or repair only the Telegram /restart updater

For an existing BLAZE deployment, do **not** rerun the full installer. Use this updater-only installer as root:

```bash
curl -fsSL https://raw.githubusercontent.com/FeelFonk26/BLAZE-GAME-Installer/main/install-updater-only.sh -o /tmp/blaze-updater-install.sh && bash /tmp/blaze-updater-install.sh
```

It requires the existing `/opt/blaze-game` checkout on a clean `main` branch, `.env`, and the existing read-only token at `/etc/blaze-game/github-token` (mode 0600). It fast-forwards the private repository, installs the restricted systemd updater, builds the bot image, and recreates **only the bot container** so its Unix-socket mount and current `/restart` handler are active.

It does not run the full deployment, modify Nginx/Certbot, recreate API/web/PostgreSQL, remove Docker volumes, or edit database contents. If it detects a dirty checkout, wrong remote/branch, missing token, or an unexpected socket path, it stops instead of overwriting anything.

## Security

- Keep the game repository private.
- The GitHub token stays on the VPS at `/etc/blaze-game/github-token` with mode 0600; never paste it into chat.
- The bot receives access only to a root-owned Unix socket that accepts one fixed update operation. It does not receive the Docker socket or arbitrary host command access.
- The updater fast-forwards the private `main` branch, builds and recreates only BLAZE API/bot/web containers, and leaves PostgreSQL data and other host services alone.
- The installer does not stop or reconfigure TASKORA, and it does not touch BLACK CITY.
