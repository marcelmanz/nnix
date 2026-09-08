.PHONY: format nixos nixos-nixbuild mlab nixos-nixbuild-mlab droid hm news sops android-mirror whatsapp-register azuracast-deploy azuracast-connect azuracast-report azuracast-clear-chat

lint: 
	@nix run .#ruff -- check --fix

format:
	@nix run .#ruff -- format
	@nix run .#oxfmt -- .
	alejandra .

nixos:
	sudo nixos-rebuild switch --flake .#nixos

hm:
	home-manager switch --flake .#work

news:
	@if [ -f /etc/NIXOS ]; then \
		echo "On NixOS news shows during 'make nixos'."; \
	else \
		home-manager news --flake .#work; \
	fi

nixos-nixbuild:
	sudo nixos-rebuild switch --flake .#nixos \
		--option builders "@/tmp/nixbuild-machines" \
		--option builders-use-substitutes true \
		--option max-jobs 0

mlab:
	@if ssh -q -o ConnectTimeout=5 root@mlab-local exit 2>/dev/null; then \
		nixos-rebuild switch  --flake .#mlab --target-host root@mlab-local; \
	else \
		nixos-rebuild switch  --flake .#mlab --target-host root@mlab; \
	fi
	@# pin the mlab closure as a local GC root. 
	@# reuses the toplevel just built above (instant), just adds the root.
	@mkdir -p $(HOME)/.cache/nix-roots
	@nix build .#nixosConfigurations.mlab.config.system.build.toplevel --out-link $(HOME)/.cache/nix-roots/mlab

nixos-nixbuild-mlab:
	sudo nixos-rebuild switch --flake .#mlab --target-host root@mlab-local; \
		--option builders "@/tmp/nixbuild-machines" \
		--option builders-use-substitutes true \
		--option max-jobs 0

# push only the azuracast public custom css/js to the live box, no full nixos rebuild.
# the css/js live in azuracast's settings db (applied via azuracast_cli in default.nix), so this
# just cats the local files into `azuracast:settings:set` over ssh. no container or radio restart
# needed - the public page picks the new css/js up on next load.
azuracast-deploy:
	@if ssh -q -o ConnectTimeout=5 root@mlab-local exit 2>/dev/null; then HOST=root@mlab-local; else HOST=root@mlab; fi; \
	echo "Pushing azuracast css/js to $$HOST..."; \
	scp hosts/mlab/azuracast/public/public.css hosts/mlab/azuracast/public/public.js $$HOST:/tmp/ && \
	ssh $$HOST 'podman exec azuracast azuracast_cli azuracast:settings:set public_custom_css "$$(cat /tmp/public.css)" && podman exec azuracast azuracast_cli azuracast:settings:set public_custom_js "$$(cat /tmp/public.js)" && rm -f /tmp/public.css /tmp/public.js' && \
	echo "azuracast css/js updated on $$HOST."

# two commands, both thin wrappers over the scripts in hosts/mlab/azuracast/:
#   azuracast-connect - ssh to the azuracast box (mlab-local/mlab autodetect);
#                       ARGS='sql "SELECT 1"' for ad-hoc queries
#   azuracast-report  - 1) music dir vs library/playlist sync  2) never-played tracks
azuracast-connect:
	@hosts/mlab/azuracast/connect $(ARGS)

azuracast-report:
	@hosts/mlab/azuracast/report

# chat history is in-memory only (see chat.py) - a service restart is all "clear the chat" needs.
azuracast-clear-chat:
	@hosts/mlab/azuracast/connect systemctl restart azuracast-chat

# a bit complex but its the only way to deploy to android that I (claude) found so the phone does not do the build
droid:
	nix build .#nixOnDroidConfigurations.default.activationPackage --impure
	nix copy --to "ssh://nix-on-droid@droid?remote-program=/data/data/com.termux.nix/files/home/.nix-profile/bin/nix-store" ./result
	rsync -avz --delete --exclude='.git' --rsync-path="/data/data/com.termux.nix/files/home/.nix-profile/bin/rsync" ./ droid:~/.config/nix-on-droid/
	ssh droid "/data/data/com.termux.nix/files/home/.nix-profile/bin/bash -l -c 'nix-on-droid switch --flake ~/.config/nix-on-droid#default'"

sops:
	@selected=$$(ls secrets/ | fzf); \
	if [ -n "$$selected" ]; then \
		sops secrets/$$selected; \
	fi

# bootstrap zip for a fresh nix-on-droid install, impure by upstream design
bootstrap:
	nix build --impure --no-link --print-out-paths --expr 'let f = builtins.getFlake (toString ./.); in import ./hosts/android/bootstrap.nix { pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux; nix-on-droid = f.inputs.nix-on-droid; system = "x86_64-linux"; targetSystem = "aarch64-linux"; sshKeyPath = ./hosts/android/ssh.pub; flakeSource = ./.; }'

android-mirror:
	@echo "Disconnecting stale ADB connections..."
	@adb disconnect 127.0.0.1:5555 2>/dev/null || true
	@echo "Starting SSH tunnel..."
	@ssh -N -L 5555:127.0.0.1:5555 -o ServerAliveInterval=15 -o ExitOnForwardFailure=yes root@mlab & \
	SSH_PID=$$!; \
	trap "echo '\nCleaning up...'; kill $$SSH_PID 2>/dev/null; adb disconnect 127.0.0.1:5555 2>/dev/null" EXIT INT TERM; \
	echo "Waiting for SSH port forward..."; \
	while ! nc -z 127.0.0.1 5555 2>/dev/null; do sleep 0.2; done; \
	echo "Connecting ADB..."; \
	until adb connect 127.0.0.1:5555 | grep -q "already connected to\|connected to"; do sleep 0.5; done; \
	adb -s 127.0.0.1:5555 wait-for-device; \
	scrcpy --no-audio -s 127.0.0.1:5555 --keyboard=uhid --mouse=sdk --max-fps 30

android-mirror-old:
	@echo "Starting SSH tunnel..."
	@ssh -N -L 5555:127.0.0.1:5555 root@mlab & \
	SSH_PID=$$!; \
	trap "echo '\nCleaning up...'; kill $$SSH_PID 2>/dev/null; adb disconnect 127.0.0.1:5555 2>/dev/null" EXIT INT TERM; \
	sleep 2; \
	echo "Connecting ADB to remote device..."; \
	adb connect 127.0.0.1:5555; \
	scrcpy --no-audio -s 127.0.0.1:5555

whatsapp-register:
	@adb connect 127.0.0.1:5555 | grep -q "already connected to\|connected to" \
		|| { echo "ADB connect failed — is 'make android-mirror' running?"; exit 1; }
	uv run --python python3 --with uiautomator2 python scripts/whatsapp-register.py
