# Moonraker / Mainsail Update Manager

This document covers updating the K2-OpenHost Cartographer fork and the external-host Kalico checkout from Mainsail.

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

A copy is available as `moonraker-cartographer.conf` in the repository.

Restart Moonraker after editing its configuration.

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

1. `env` is deprecated for extension updaters. `virtualenv: ~/klippy-env` is the current form.
2. `install_script: install.sh` points to a file that does not exist at the repository root. The K2-OpenHost installer is `scripts/install.sh`.

More importantly, even changing it to `scripts/install.sh` would not provide a post-update hook. Moonraker's `install_script` option is a legacy dependency-discovery mechanism: Moonraker parses the script for system package declarations; it does not execute the installer after every Git update.

K2-OpenHost therefore uses:

```ini
virtualenv: ~/klippy-env
requirements: requirements.txt
```

The repository is installed into that virtualenv in editable mode, so a Git pull immediately changes the Python source imported by Kalico. Moonraker can update Python requirements when the requirements file changes, then restart Klipper through `managed_services: klipper`.

## Initial installation is still required

The update manager does not replace the first installation:

```bash
cd ~
git clone https://github.com/MzTechnology97/cartographer3d-plugin-k2openhost.git
cd cartographer3d-plugin-k2openhost
./scripts/install.sh --klipper ~/klipper --klippy-env ~/klippy-env
```

After the editable install and loader are in place, normal source updates can be performed from Mainsail.

If a future release explicitly changes the loader/scaffolding or installation layout, release notes may ask for `./scripts/install.sh` to be run manually once.

## Kalico / Klipper updater

Current Moonraker detects the running Klipper source path and Python executable from the connected Klippy instance. The built-in `[update_manager klipper]` section is therefore different from a normal third-party extension.

Make sure the checkout itself is on the K2-OpenHost branch and tracks its remote:

```bash
cd ~/klipper
git remote set-url origin https://github.com/MzTechnology97/kalico-k2pro.git
git fetch origin
git checkout k2-pro-openhost
git branch --set-upstream-to=origin/k2-pro-openhost k2-pro-openhost
```

Then use only the supported updater override:

```ini
[update_manager klipper]
channel: dev
```

Do not add a second updater pointing at `~/klipper` under another name. Two update-manager entries managing the same source tree can conflict with Moonraker's path reservation and recovery logic.

## Unofficial remote warning

Moonraker's built-in Klipper updater is based around the official Klipper repository metadata. A K2-OpenHost Kalico fork may therefore be reported as an unofficial remote/branch anomaly.

This warning is distinct from a dirty/corrupt/invalid repository. In dev mode Moonraker resolves the current checkout's tracking remote and branch for normal fetch/pull operations. Verify the displayed branch and upstream before updating.

Do not use a hard recovery operation without first checking the recovery URL shown by Moonraker.

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

A normal K2-OpenHost installation should not modify tracked files inside the Cartographer repository. The loader is created in the Kalico checkout and excluded from its local Git status by the installer when necessary.

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

The expected paths for the standard K2-OpenHost installation are:

```text
~/cartographer3d-plugin-k2openhost
~/klippy-env
~/cartographer3d-plugin-k2openhost/requirements.txt
```

## If Mainsail says the repository is dirty

Run:

```bash
cd ~/cartographer3d-plugin-k2openhost
git status
```

Do not blindly use hard recovery if the local modifications are intentional. Commit, stash or manually reconcile them first.

## Update behaviour

A normal Cartographer update performs conceptually:

```text
fetch/pull repository
-> update requirements if requirements.txt changed
-> source is immediately visible through editable install
-> restart Klipper
```

It does not rerun the K2-OpenHost installation script.
