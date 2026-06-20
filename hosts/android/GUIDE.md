# The Complete Nix-on-Droid Deployment Guide

## Phase 1: Automated Build & Temporary HTTPS Hosting

### 1. The Deployment Script

Create a script named `deploy-bootstrap.sh` in the root of your dotfiles.
This script will build the `--impure` zip, host it locally, and instantly expose it to the internet with a secure `https://` URL.

```bash
#!/usr/bin/env bash
set -e

# building custom bootstrap zip (explain --impure)
nix build .#android-bootstrap --impure

# staging file for hosting
mkdir -p /tmp/nix-bootstrap
# the app specifically looks for this filename based on your architecture
cp ./result /tmp/nix-bootstrap/bootstrap-aarch64.zip

# starting local python http server on port 8888
python3 -m http.server 8888 --directory /tmp/nix-bootstrap &
SERVER_PID=$!

# ensure the python server is killed when you exit the script (ctrl+c)
trap "kill $SERVER_PID" EXIT

# spawning temporary cloudflare tunnel
echo "look for the url ending in '.trycloudflare.com' below."
cloudflared tunnel --url http://localhost:8888
# pkill 8888 if it does not close
```

## Phase 2: Android App Initialization

With your temporary HTTPS tunnel active, initialize the Android app.

1. **Launch the App:** Open Nix-on-Droid.

2. **Set the Bootstrap URL:** `https://random-words.trycloudflare.com`

3. **Wait for Evaluation:** The app will download the zip, extract the basic Nix
   environment, and evaluate the default derivations. This downloads around 42
   MiB and can take 3–5 minutes.

4. **Completion:** It will drop you into a basic, unconfigured shell (`bash-5.2$`).
   You can now press `Ctrl+C` on your computer to close the temporary tunnel.

## Phase 3: Deploying Your Custom Flake

Remember to activate wakelock in the nix-on-droid notification snack:

```bash
nix-on-droid switch --flake github:marcelmanz/nnix#android
```

## Phase 4: Finalize & Connect

Your system is now built in the Nix store, but your current terminal session is still running the old environment.

### 1. Reload the Environment

The cleanest way to apply everything is to completely **force-close the Nix-on-Droid app** (swipe it away from your recent apps view) and reopen it. You should instantly be greeted by your custom Fish shell prompt.

### 2. Start the SSH Daemon

From your new shell, manually start the SSH server so you can connect from your PC:

```bash
sshd -p 8022
```

### 3. Find Your Phone's IP Address

TODO: Then explain how to setup OICD in the server to register in Tailscale anon
so we can setup the static ip of the phone.

### 4. Connect from Your Desktop

Jump onto your computer and SSH into the phone:

Setup in laptopt:

```nix
   "droid" = {
     hostname = "<tailscale_ip>";
     user = "root";
     identityFile = "~/.ssh/mlab_key";
     extraOptions = {
       IdentitiesOnly = "yes";
     };
   };
```

```bash
rsync -avz --delete --exclude='.git' ./ droid:~/.config/nix-on-droid/
ssh droid "nix-on-droid switch --flake ~/.config/nix-on-droid#default"
```
