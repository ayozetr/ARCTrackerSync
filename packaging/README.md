# Linux packages

Unofficial packages for ARCTracker Sync. Upstream publishes Windows releases
only, so on Linux the app is built from source; these wrap that build so the
capture capability, the desktop entry and the icon are handled on install
instead of by hand.

## Why not an AppImage

AppImages mount their payload over FUSE, which is `ro,nosuid`:

```
Some.AppImage /tmp/.mount_XXXX fuse.Some.AppImage ro,nosuid,nodev,...
```

`nosuid` makes the kernel ignore file capabilities on anything inside that
mount, and `ro` rules out setting them at runtime. So a bundled binary can never
hold `CAP_NET_RAW`, and capture cannot work. Granting the capability to the
`.AppImage` itself does not help either — capabilities are recomputed on each
`exec`, and the inner binary has none. That leaves running the whole thing as
root, which loses access to the user's Wayland session.

Flatpak has the same problem for the same reason. A distro package is the
standard answer for a binary that needs a capability; it is how Wireshark ships
`dumpcap`.

## Building

```bash
packaging/build.sh          # .deb and .rpm
packaging/build.sh deb
```

The binary is compiled inside `rust:1-slim-bookworm` (Debian 12, glibc 2.36),
**not** against the host's libraries. A Rust binary needs at least the glibc it
was built against, so building on a rolling distro yields something that fails
to start on any stable one:

```
/usr/bin/arctracker-sync: version `GLIBC_2.43' not found
```

glibc 2.36 covers Debian 12+, Ubuntu 22.04+ and current Fedora. Podman is used
if present, otherwise Docker.

The `.rpm` needs `rpmbuild`, which the Rust image does not carry. Either add it
to the image or build that target on a host that has it; the `.deb` needs
nothing beyond the container.

For Arch, `packaging/arch/PKGBUILD` builds against the system toolchain — it is
for the local machine, not for redistribution, so pinning an old glibc would be
pointless.

## Installing

```bash
sudo apt install ./arctracker-sync_0.2.0_amd64.deb     # resolves dependencies
sudo dnf install ./arctracker-sync-0.2.0-1.x86_64.rpm
```

Use the package manager rather than `dpkg -i`, which does not fetch
dependencies and leaves the package unconfigured — meaning the capability is
never granted — until an `apt-get install -f` finishes the job.

## What the packages do at install time

`setcap cap_net_raw+ep` on `/usr/bin/arctracker-sync`. Capture opens an
`AF_PACKET` socket, which the kernel only allows with that capability; the
alternative is running the GUI as root. The `.rpm` declares it with `%caps` so
rpm records and verifies it, while the `.deb` applies it from `postinst` — a
capability shipped inside the archive would not survive transports that drop
extended attributes.

Both warn instead of failing silently if the capability cannot be set, which is
what happens on a `nosuid` mount or a filesystem without xattrs. Capture would
otherwise fail later with a permission error nobody can place.

Uninstalling leaves per-user data (`~/.config/sync`, `~/.local/share/sync`)
alone and says so, rather than deleting a user's files from a maintainer script.

## What users should know before installing

- The binary carries **CAP_NET_RAW** and reads packets on the network
  interface. It only ever looks at traffic on that machine.
- Sync works by decrypting the game's own TLS with the session keys the game
  writes to **`SSLKEYLOGFILE`**. Anyone who can read that file can decrypt every
  HTTPS session the game made while it existed, account token included. The app
  deletes the key log it manages when capture stops; one pointed at by a
  user-set `SSLKEYLOGFILE` is left alone, and is the user's to clean up.
- **Unofficial build.** It carries upstream's name and icon but is not from
  RaidTheory LLC and is not supported by them.
- PolyForm Noncommercial 1.0.0: free for noncommercial use, commercial use
  needs a separate licence. Redistributed copies must carry the licence.

## Running

Start the app **before** the game. Capture can only decrypt handshakes it
witnesses, so if the game is already running it has to be restarted — the most
common reason sync appears to hang at "looking for your account".
