# Radicle on mlab

mlab runs a Radicle seed node. Public repos are browsable at
https://git.marcel.cool and served to peers on `ssh.marcel.cool:8776`.

- Node ID: `z6MkhWXzth9QTkmC34zcJ83BfEyzwBcKHUqN3GavcGWPkMBj`
- Seeding policy: `block`, mlab only hosts repos it is told to seed.
- Only use public repos. The 1.x node protocol is unencrypted and
  unauthenticated, see the links next to `radicle-node` in
  `permittedInsecurePackages` in `flake.nix`.

## Pieces

| Where                        | What                                                         |
| ---------------------------- | ------------------------------------------------------------ |
| `default.nix`                | radicle-node + radicle-httpd (port from `proxy.nix`)         |
| `default.nix`                | radicle-search + Meilisearch, repo search on git.marcel.cool |
| `radicle.pub`                | node public key                                              |
| `secrets/mlab.yaml`          | `radicle_node_key`, the node private key (sops)              |
| `../proxy.nix`               | `git.marcel.cool`: explorer UI + httpd API/git routes        |
| `home/terminal-packages.nix` | `rad` CLI (`radicle-node`)                                   |
| `home/terminal.nix`          | `radit`, seeds the current repo on mlab                      |
| `home/gui.nix`               | `radicle-desktop`, GUI for issues/patches/comments           |
| dots `.bashrc`               | `rad` wrapper: `rad init` is public + radit reminder         |

## New laptop

1. Apply the Nix config.
2. Copy `~/.radicle/keys/radicle` and `radicle.pub` from an existing laptop
   (same identity), or run `rad auth` and add the new key as a delegate per
   repo with `rad id update --delegate did:key:...`.
3. Connect to mlab and start the node:

   ```sh
   rad config edit   # node.connect: ["z6MkhWXz...@ssh.marcel.cool:8776"]
   rad node start
   rad node status   # mlab should show as connected
   ```

SSH access to mlab is only needed for `radit`.

## Publish a repo

```sh
rad init     # public, via the dots wrapper
radit        # mlab seeds it, shows up on git.marcel.cool
```

Push to Codeberg and Radicle with one `git push`:

```sh
git remote set-url --add --push origin ssh://git@codeberg.org/marcelmanz/<repo>.git
git remote set-url --add --push origin "$(git remote get-url --push rad)"
```

Clone over HTTPS: `git clone https://git.marcel.cool/<rid-without-rad:>.git`

## Day to day

```sh
git push                                   # or `git push rad main`
rad issue open / list / comment <id> -m ""
rad patch show <id>
rad patch comment <revision-id> -m ""
rad patch review <id> --accept -m ""
rad sync --announce                        # after working offline
```

git.marcel.cool is read-only; write from the CLI or `radicle-desktop`.

## On mlab

```sh
sudo rad-system ls                         # seeded repos
sudo rad-system seed <rid>                 # what radit does
sudo rad-system follow <did> --alias <name>
journalctl -u radicle-node -u radicle-httpd
```

## Rotating the node key

```sh
ssh-keygen -t ed25519 -N "" -C "" -f /tmp/radicle
```

Put the private key in `secrets/mlab.yaml` as `radicle_node_key`, the public
key in `radicle.pub` (no comment), deploy. The Node ID changes, so update
`node.connect` on every laptop.
