# BLAZE GAME VPS Installer

Public installer for deploying the **private** `FeelFonk26/BLAZE-GAME` repository to the prepared Ubuntu VPS.

The game source code is not published in this repository.

## Run on the BLAZE VPS

Run this single command as root:

```bash
curl -fsSL https://raw.githubusercontent.com/FeelFonk26/BLAZE-GAME-Installer/main/install-vps.sh -o /tmp/blaze-install.sh && bash /tmp/blaze-install.sh
```

The installer asks for:

1. A GitHub Personal Access Token with **Contents: Read-only** access to the private `FeelFonk26/BLAZE-GAME` repository.
2. The BotFather token for `@BlazeGameAppBot`, if it has not already been configured in `/opt/blaze-game/.env`.
3. The owner's numeric Telegram ID, used to authorize the private `/restart` command.

The GitHub token is stored outside the project at `/etc/blaze-game/github-token` with mode 0600 so the host can securely fetch later updates. It is never embedded in the Git remote URL, copied into the bot container, or committed to this repository. The BotFather token remains in the protected `/opt/blaze-game/.env`.

The installer configures a restricted systemd updater. The bot receives access only to a root-owned Unix socket that accepts one fixed update operation; it does not receive the Docker socket or arbitrary host command access. The updater fast-forwards the private `main` branch, builds and recreates only BLAZE API/bot/web containers, and leaves PostgreSQL data and other host services alone.

The installer creates a separate BLAZE Docker stack and Nginx virtual host. It does not stop or reconfigure TASKORA, and it does not touch BLACK CITY.

## Security

- Keep the game repository private.
- Do not paste either token into chat or share it.
- If a token is exposed, revoke it in GitHub/BotFather and create a replacement.
