format:
	alejandra .

nixos:
	sudo nixos-rebuild switch --flake .#nixos

nixos-nixbuild:
	sudo nixos-rebuild switch --flake .#nixos \
		--option builders "@/tmp/nixbuild-machines" \
		--option builders-use-substitutes true \
		--option max-jobs 0

vps:
	nixos-rebuild switch  --flake .#vps --target-host root@vps

mlab:
	@if ssh -q -o ConnectTimeout=5 root@mlab-local exit 2>/dev/null; then \
		nixos-rebuild switch  --flake .#mlab --target-host root@mlab-local; \
	else \
		nixos-rebuild switch  --flake .#mlab --target-host root@mlab; \
	fi

nixos-nixbuild-mlab:
	sudo nixos-rebuild switch --flake .#mlab --target-host root@mlab-local; \
		--option builders "@/tmp/nixbuild-machines" \
		--option builders-use-substitutes true \
		--option max-jobs 0

# a bit complex but its the only way I (claude) found so the phone does not do the build
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
