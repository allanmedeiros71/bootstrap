# bootstrap

One command to take a fresh machine from zero to my working setup on
Ubuntu, Zorin, Pop!_OS, Fedora, Arch or macOS:

```sh
curl -fsSL https://boot.medeiros.cloud | bash
```

## What it does

1. Installs git, curl and ssh (the Command Line Tools on macOS).
2. Creates an ed25519 SSH key and loads it into `ssh-agent`.
3. Registers the key on GitHub through `gh`, signing in from the browser or
   a phone, with no copy-and-paste of keys.
4. Clones my private `scripts` repository into `~/Projects/scripts`.
5. Hands over to `pos-install.sh`, which installs packages and applies my
   dotfiles with [chezmoi](https://www.chezmoi.io/).

```
curl | bash  ──►  bootstrap.sh  ──►  scripts/pos-install.sh  ──►  chezmoi (dotfiles)
```

## Options

```sh
curl -fsSL https://boot.medeiros.cloud | bash -s -- --dry-run            # show what would run
curl -fsSL https://boot.medeiros.cloud | bash -s -- --only dotfiles,apps # passed on to pos-install
curl -fsSL https://boot.medeiros.cloud | bash -s -- --bootstrap-only     # stop after the clone
```

| Variable       | Purpose                                                          |
| -------------- | ---------------------------------------------------------------- |
| `GH_TOKEN`     | Token with `admin:public_key`, skips the interactive login       |
| `SCRIPTS_REPO` | Repository to clone (default `git@github.com:allanmedeiros71/scripts.git`) |
| `SCRIPTS_DIR`  | Clone target (default `~/Projects/scripts`)                      |

The script reads interactive input from `/dev/tty`, so prompts work even
though it arrives through a pipe.

## Hosting

`boot.medeiros.cloud` is only a redirect to the raw script, served by Caddy
on my VPS under Coolify (see [`coolify/`](coolify/)). If the VPS is down, use
GitHub directly:

```sh
curl -fsSL https://raw.githubusercontent.com/allanmedeiros71/bootstrap/main/bootstrap.sh | bash
```

This repository is public on purpose: it holds no secrets.
