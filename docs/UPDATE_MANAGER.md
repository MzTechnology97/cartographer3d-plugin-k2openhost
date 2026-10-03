# Moonraker / Mainsail Update Manager

This document covers updating the K2-OpenHost Cartographer fork and the external-host Kalico checkout from Mainsail.

Reviewed: **2026-10-02**.

## Cartographer updater

Add this section to `~/printer_data/config/moonraker.conf`:

```ini
[update_manager cartographer]
type: git_repo
channel: dev
path: ~/cartographer3d-plugin-k2openhost
origin: https://github.com/MzTechnology97/cartographer3d-plugin-k2openhost.git
primary_branch: main
virtualenv: ~/klippy-env
requirements: requirements.txt
is_system_service: False
managed_services: klipper
info_tags:
  desc=Cartographer3D Plugin - K2-OpenHost
```

A copy is available as `moonraker-cartographer.conf` in the repository. Restart Moonraker after editing its configuration.

## Why the older example fails

A configuration such as:

```ini
[update_manager cartographer]
type: git_repo
path: ~/cartographer3d-plugin-k2openhost
primary_branch: main
origin: https://github.com/MzTechnology97/cartographer3d-plugin-k2openhost.git
env: ~/klippy-env/bin/python
install_script: install.sh
is_system_service: False
managed_services: klipper
```

has two problems on current Moonraker:

1. `env` is deprecated for extension updaters. Use `virtualenv: ~/klippy-env`.
2. `install_script: install.sh` points to a file that does not exist at the repository root. The K2-OpenHost installer is `scripts/install.sh`.

More importantly, Moonraker's `install_script` option is not a generic post-update installer hook. K2-OpenHost therefore uses:

```ini
virtualenv: ~/klippy-env
requirements: requirements.txt
```

The repository is installed into that virtualenv in editable mode, so a Git pull immediately changes the Python source imported by Kalico.

## Initial installation

The update manager does not replace the first installation:

```bash
cd ~
git clone https://github.com/MzTechnology97/cartographer3d-plugin-k2openhost.git
cd cartographer3d-plugin-k2openhost
./scripts/install.sh --klipper ~/klipper --klippy-env ~/klippy-env
```

After the editable install and loader are in place, normal source updates can be performed from Mainsail.

## Loader behavior on `kalico-k2pro`

Since 2026-10-03 `MzTechnology97/kalico-k2pro` no longer tracks `klippy/extras/cartographer.py`. The loader belongs to this fork's installation and lives in:

```text
klippy/plugins/cartographer.py
```

which Kalico's `.gitignore` excludes, so the Kalico checkout stays clean for Moonraker.

After updating Kalico past that change, run the installer once more so the loader exists in `klippy/plugins/`:

```bash
~/cartographer3d-plugin-k2openhost/scripts/install.sh --klipper ~/klipper --klippy-env ~/klippy-env
```

Exactly one loader must exist, otherwise Kalico stops with:

```text
Module 'cartographer' found in both extras and plugins!
```

The installer removes untracked loaders from `klippy/extras/`. To verify:

```bash
cd ~/klipper
ls -l klippy/extras/cartographer.py klippy/plugins/cartographer.py 2>/dev/null || true
```

Only `klippy/plugins/cartographer.py` should be listed.

## Kalico / Klipper updater

Current Moonraker detects the running Klipper source path and Python executable from the connected Klippy instance. Make sure the checkout itself is on the K2-OpenHost branch and tracks its remote:

```bash
cd ~/klipper
git remote set-url origin https://github.com/MzTechnology97/kalico-k2pro.git
git fetch origin
git checkout k2-pro-openhost
git branch --set-upstream-to=origin/k2-pro-openhost k2-pro-openhost
```

Then use only the built-in updater override:

```ini
[update_manager klipper]
channel: dev
```

Do not add a second updater pointing at `~/klipper` under another name.

## Repository must be clean

Moonraker will refuse normal updates if the repository contains tracked local modifications.

Check Cartographer:

```bash
cd ~/cartographer3d-plugin-k2openhost
git status --short
git remote -v
git branch -vv
```

Check Kalico:

```bash
cd ~/klipper
git status --short
git remote -v
git branch -vv
```

Files tracked by `kalico-k2pro` should be restored from Git instead of overwritten by third-party installers.

Locally installed extras that are not part of the fork can remain outside Git tracking. If an external plugin creates an untracked file/symlink under `~/klipper/klippy/extras`, use a local `.git/info/exclude` entry rather than committing unrelated plugin code into the Kalico fork.

Example for a local ShakeTune installation:

```bash
cd ~/klipper
grep -qxF 'klippy/extras/shaketune' .git/info/exclude || \
  echo 'klippy/extras/shaketune' >> .git/info/exclude
```

For a local DynamicMacros module:

```bash
grep -qxF 'klippy/extras/dynamicmacros.py' .git/info/exclude || \
  echo 'klippy/extras/dynamicmacros.py' >> .git/info/exclude
```

Use the exact path shape shown by `git status --short`; a symlink such as `shaketune` is matched without a trailing slash.

## Verify Moonraker loading

After restarting Moonraker:

```bash
journalctl -u moonraker --since "5 minutes ago" --no-pager | \
  grep -Ei 'update_manager|cartographer|klipper|warning|error'
```

In Mainsail, refresh **Machine -> Update Manager**.

For Cartographer verify:

```text
configured type: git_repo
branch: main
remote/origin: MzTechnology97/cartographer3d-plugin-k2openhost
working tree: clean
```

For Kalico verify:

```text
branch: k2-pro-openhost
tracking remote: origin/k2-pro-openhost
```

## If Cartographer does not appear in Mainsail

Check Moonraker's log first. Common causes are:

- the `path` does not exist;
- the repository is not a Git checkout;
- `virtualenv` does not point to a valid Python virtual environment;
- `requirements.txt` is missing;
- `origin` does not match the configured repository;
- the same update-manager section is defined more than once.

Expected paths:

```text
~/cartographer3d-plugin-k2openhost
~/klippy-env
~/cartographer3d-plugin-k2openhost/requirements.txt
```

## If Mainsail says the Kalico repository is dirty

Start with:

```bash
cd ~/klipper
git status --short
```

For a tracked file that should match the fork:

```bash
git restore --source=HEAD -- path/to/file
```

For untracked third-party extras, either keep them outside the Kalico tree or add an exact local `.git/info/exclude` entry. Do not hide a tracked modification with an exclude rule; Git ignore/exclude only applies to untracked paths.

## Update behavior

A normal Cartographer update performs conceptually:

```text
fetch/pull repository
-> update requirements if requirements.txt changed
-> source is immediately visible through editable install
-> restart Klipper
```

It does not need to rerun the K2-OpenHost installation script for ordinary source updates.