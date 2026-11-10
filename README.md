# BLAZE GAME VPS Installer

Public installer for deploying the **private** `FeelFonk26/BLAZE-GAME` repository to the prepared Ubuntu VPS.

The game source code is not published in this repository.

## Run on the BLAZE VPS

Run this single command as root:

```bash
curl -fsSL https://raw.githubusercontent.com/FeelFonk26/BLAZE-GAME-Installer/main/install-vps.sh -o /tmp/blaze-install.sh && bash /tmp/blaze-install.sh
```

The installer asks for two secrets using hidden terminal input:

1. A GitHub Personal Access Token with **Contents: Read-only** access to the private `FeelFonk26/BLAZE-GAME` repository. A fine-grained token restricted to that one repository is recommended.
2. The BotFather token for `@BlazeGameAppBot`, if it has not already been configured in `/opt/blaze-game/.env`.

Neither token is embedded in the command, written to the Git remote URL, or committed to this repository. The temporary Git token file is removed after the private source has been cloned or updated.

The installer creates a separate BLAZE Docker stack and Nginx virtual host. It does not stop or reconfigure TASKORA, and it does not touch BLACK CITY.

## Security

- Keep the game repository private.
- Do not paste either token into chat or share it.
- If a token is exposed, revoke it in GitHub/BotFather and create a replacement.
