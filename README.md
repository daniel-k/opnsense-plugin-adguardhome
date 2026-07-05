# opnsense-plugin-adguardhome

Builds two packages for OPNsense amd64:

- `adguardhome` (FreeBSD port package — the AdGuard Home daemon)
- `os-adguardhome` (OPNsense plugin with a web UI page)

The plugin provides a `Services -> AdGuard Home` page where you can:

- enable/disable the service
- tune runtime options (run-as user, config path, working directory, extra args)
- jump to the AdGuard Home admin interface

> **Important — who owns the configuration:** AdGuard Home manages its own
> configuration file (`AdGuardHome.yaml`) and rewrites it whenever you change
> settings in its web interface. Unlike some OPNsense services, this plugin does
> **not** template or overwrite that file. All DNS, filtering and blocklist
> configuration is done inside AdGuard Home's own admin UI. The plugin only
> manages the service (via `rc.conf`) and links out to that UI.

## Security model: least privilege, no privileged ports

This plugin is built to run AdGuard Home with **least privilege**:

- It runs as a **dedicated, unprivileged `adguardhome` system account** (nologin
  shell, no writable home outside its work directory), created automatically by
  the `adguardhome` package. It never runs as `root`.
- It is **not** granted the ability to bind privileged ports (< 1024). In
  particular it does **not** take DNS port 53 — OPNsense's own **Unbound**
  resolver keeps that.

The plugin manages the admin credentials and the web/DNS ports for you (see
below), keeping AdGuard Home on **high, non-privileged ports** so it runs
unprivileged and coexists with Unbound.

## First-time setup

The plugin **seeds `AdGuardHome.yaml` before the first start**, so AdGuard Home
never needs root and there is no setup wizard to click through:

1. Install `os-adguardhome` (see below) and open `Services -> AdGuard Home`.
2. Set the **Admin User** and **Admin Password**, and (optionally) adjust the
   **Web Interface Port** (default `3000`) and **DNS Port** (default `5353`).
3. Enable the service and **Save**.
4. Click **Open AdGuard Home**, log in with the credentials you just set, and
   configure filtering, upstreams, clients, etc. in AdGuard Home's own UI.

That's it — it runs as the unprivileged `adguardhome` user on the DNS port you
chose. Set **Upstream DNS = `127.0.0.1:53`** (Unbound) in AdGuard Home's UI, or
seed it that way (the default seed already points upstream at Unbound).

### What the plugin manages vs. what AdGuard Home manages

The plugin is the source of truth for four things and rewrites *only* those keys
in `AdGuardHome.yaml` on each Save (everything else is preserved byte-for-byte):

- **Admin user / password** — AdGuard Home has no UI to change these.
- **Web interface port** — AdGuard Home has no UI to change its own admin port.
- **DNS port** — also settable in AdGuard Home's UI, but the plugin re-asserts
  it on Save, so manage it here.

Everything else — filters, upstreams, clients, DHCP, rewrites, TLS, etc. — is
owned by AdGuard Home; configure it in AdGuard Home's own web UI. Leaving the
**Admin Password** field blank on a later Save keeps the current password.

> **Why AdGuard Home would otherwise need root:** on FreeBSD its *first* launch
> (before any config exists) hard-requires `uid 0` — `CanBindPrivilegedPorts()`
> is literally `getuid() == 0` on BSD (portacl/capabilities do not satisfy it).
> Seeding a config sidesteps that check entirely, which is how the plugin keeps
> AdGuard Home unprivileged from the very first start.

### Coexisting with Unbound

AdGuard Home runs on a high port (default `5353`), so it never fights Unbound for
port 53. There are two sane topologies — pick one. **AdGuard Home is a
*forwarder*, not a recursive resolver**, so whichever you choose, its upstream is
a real resolver; never point it at whatever forwards *into* it (that loops).

**Option A — Unbound in front (AdGuard as Unbound's upstream).** Clients keep
using Unbound on :53 (no NAT tricks); do local overrides in Unbound's UI; AdGuard
filters and forwards to a public resolver:

```
clients ──► Unbound :53 (overrides) ──► AdGuard Home :5353 (filter) ──► public DNS (e.g. Quad9)
```
- **Unbound → General/Query Forwarding**: forward to `127.0.0.1@5353` (AdGuard).
- **AdGuard UI → Settings → DNS**: *Upstream DNS* = a **public** resolver
  (e.g. `9.9.9.9`) — the plugin's seed default. **Not** `127.0.0.1:53` (loop).
- Note: AdGuard sees all queries as coming from Unbound, so per-client stats /
  filtering in AdGuard won't work in this layout.

**Option B — AdGuard in front (Unbound as the recursive resolver).** Gives
per-client filtering in AdGuard and true recursion in Unbound, but AdGuard must
receive client queries (it's on 5353, so you need a NAT redirect or to point
clients at it), and its upstream is Unbound:

```
clients ──► AdGuard Home :5353 (filter, per-client) ──► Unbound :53 (recursion) ──► internet
```
- **AdGuard UI → Settings → DNS**: *Upstream DNS* = `127.0.0.1:53` (Unbound).
- **Firewall → NAT → Port Forward**: redirect LAN DNS (`53`) to `127.0.0.1:5353`
  so client DNS is transparently filtered.
- Leave Unbound on 53 as the recursive resolver; don't point it back at AdGuard.

Either way, set the ports in the plugin (Web/DNS port fields); everything else —
including the upstream — is set in AdGuard Home's own UI. The admin web port
(default `3000`) can collide with the OPNsense GUI if set to `80`/`443` — keep it
on a free high port.

## Integrate the repo in OPNsense (automatic updates)

Create a pkg repository file on the firewall. **Note:** the OPNsense root shell
is `tcsh`, which does not support `<<EOF` here-documents. Either switch to a
POSIX shell first (`sh`) and paste the here-doc:

```sh
sh
cat > /usr/local/etc/pkg/repos/adguardhome.conf <<'EOF'
adguardhome: {
  url: "https://daniel-k.github.io/opnsense-plugin-adguardhome/${ABI}",
  mirror_type: "none",
  signature_type: "none",
  enabled: yes
}
EOF
exit
```

…or, to stay in `tcsh`, write it with a single `printf` (the single quotes keep
`${ABI}` literal so `pkg` — not the shell — expands it):

```sh
printf 'adguardhome: {\n  url: "https://daniel-k.github.io/opnsense-plugin-adguardhome/${ABI}",\n  mirror_type: "none",\n  signature_type: "none",\n  enabled: yes\n}\n' > /usr/local/etc/pkg/repos/adguardhome.conf
```

Then update and install from the repo:

```sh
pkg update -f
pkg install os-adguardhome
```

After this, `os-adguardhome` and `adguardhome` are eligible for normal update
flows (`pkg upgrade` and OPNsense firmware/plugin updates).

## Repository layout

- `ports/www/adguardhome`: FreeBSD port for `adguardhome` (installs the upstream
  prebuilt FreeBSD/amd64 binary and an rc script)
- `dns/adguardhome`: OPNsense plugin sources (`os-adguardhome`)
- `Mk`, `Templates`, `Scripts`, `Keywords`: OPNsense plugin build tooling

## Build locally (FreeBSD)

```sh
./scripts/build-packages.sh
```

By default this builds the release plugin package (`os-adguardhome`), even
though the OPNsense plugin tooling defaults to devel mode on master branches.

To intentionally build the devel plugin package (`os-adguardhome-devel`):

```sh
PLUGIN_DEVEL_MODE=devel ./scripts/build-packages.sh
```

Prerequisite: FreeBSD ports tree available at `/usr/ports` (for example:
`git clone --depth 1 https://git.FreeBSD.org/ports.git /usr/ports`).

Artifacts end up in `artifacts/All/`:

- `adguardhome-<version>.pkg`
- `os-adguardhome-<version>.pkg` (or `os-adguardhome-devel-<version>.pkg` when
  `PLUGIN_DEVEL_MODE=devel`)
- repository metadata (`packagesite.pkg`, `meta.conf`, ...)
- ABI marker (`artifacts/ABI`)

## Install manually on OPNsense (one-off)

1. Copy/download both packages to the firewall.
2. Install dependency first:
   ```sh
   pkg add ./adguardhome-<version>.pkg
   ```
3. Install plugin:
   ```sh
   pkg add ./os-adguardhome-<version>.pkg
   ```
   If you built with `PLUGIN_DEVEL_MODE=devel`, install
   `os-adguardhome-devel-<version>.pkg` instead.
4. Open `Services -> AdGuard Home` in the web UI and configure/save.

## CI

GitHub Actions is split into two workflows:

1. `.github/workflows/build.yml` (push/PR/manual): builds both packages on
   FreeBSD and uploads them as an artifact (no publishing)
2. `.github/workflows/release.yml` (GitHub release `published`): rebuilds both
   packages and publishes the pkg repository to GitHub Pages

Only explicit GitHub releases publish to Pages.

Both workflows use a GitHub Actions cache for:

- `/usr/ports/distfiles` (source tarballs/binaries fetched by ports)
- `/var/cache/pkg` (`pkg` download cache)

This reduces repeated network downloads on later runs. A new cache is populated
automatically after a cache miss.

### Refreshing the CI cache (important)

Cache key version is defined in both `.github/workflows/build.yml` and
`.github/workflows/release.yml` as:
`freebsd-14_3-downloads-v1-...`

To force a fresh cache generation, bump the `v1` part (for example to `v2`),
commit, and push (keep both workflow files in sync). The first run after the
bump is expected to be slower (cold cache). The next runs should be faster
again.

**Which FreeBSD `release:` to build on:** match the FreeBSD version of your
target OPNsense (check with `uname -K` / `freebsd-version` on the firewall — e.g.
`1403000` = 14.3). Building on a *newer* point release than the firewall makes
`pkg` reject the package (`Newer FreeBSD version for package ...`, needing
`IGNORE_OSVERSION=yes`) and can break OPNsense GUI plugin updates. Because the
ports tree HEAD may already flag your (older but still-running) release as EOL,
`scripts/build-packages.sh` passes `ALLOW_UNSUPPORTED_SYSTEM=yes` — safe here
since the port only installs a prebuilt static binary. When your OPNsense moves
to a newer FreeBSD, bump `release:` in both workflows accordingly.

When to refresh on purpose:

- after changing FreeBSD release in CI (for example `14.3` -> `14.4`)
- after major dependency/toolchain shifts that change many downloads
- when cache content appears stale/corrupt (unexpected fetch/checksum failures
  that disappear after retry)
- when download behavior regresses and logs show too many cache misses

### Release tag format

Releases must use this exact tag format:

`rel/adguardhome-v<ADGUARDHOME_PKGVER>+os-adguardhome-v<PLUGIN_PKGVER>`

Where:

- `ADGUARDHOME_PKGVER` = `DISTVERSION` + `_PORTREVISION` when `PORTREVISION > 0`
- `PLUGIN_PKGVER` = `PLUGIN_VERSION` + `_PLUGIN_REVISION` when
  `PLUGIN_REVISION > 0`

Example:

`rel/adguardhome-v0.107.77+os-adguardhome-v1.0`

The release workflow validates that the release tag matches the versions in the
repository at the tagged commit.

### Release helper tooling

Use `scripts/release.sh` to inspect versions, bump revisions, and create tags /
GitHub releases.

Show current versions and computed tag:

```sh
./scripts/release.sh show
```

Print only the computed tag:

```sh
./scripts/release.sh tag
```

Set explicit versions:

```sh
# Set upstream AdGuard Home version and reset PORTREVISION to 0
./scripts/release.sh set-adguardhome 0.107.78
# (then update ports/www/adguardhome/distinfo — run
#  `make -C ports/www/adguardhome makesum` on FreeBSD)

# Set upstream version + explicit PORTREVISION
./scripts/release.sh set-adguardhome 0.107.78 1

# Set plugin version + optional revision (default revision: 0)
./scripts/release.sh set-plugin 1.1
./scripts/release.sh set-plugin 1.1 2
```

Bump only packaging revisions:

```sh
./scripts/release.sh bump-adguardhome-revision
./scripts/release.sh bump-plugin-revision
```

Create release tag and release:

```sh
# Create local annotated tag from current versions
./scripts/release.sh create-tag

# Create and push tag in one step
./scripts/release.sh create-tag --push

# Create a GitHub release with the computed tag (requires gh CLI auth)
./scripts/release.sh create-gh-release
```

`create-gh-release` creates the GitHub release directly (and auto-generates
release notes by default), which triggers publishing to GitHub Pages.

Recommended release flow:

1. bump versions (`set-adguardhome`, `set-plugin`, or revision bump commands)
2. if the upstream version changed, refresh `distinfo`
   (`make -C ports/www/adguardhome makesum` on FreeBSD)
3. commit + push to `master`
4. create release (`./scripts/release.sh create-gh-release`)
5. wait for `.github/workflows/release.yml` to publish Pages

Published layout:

- `https://<owner>.github.io/<repo>/<ABI>/...`
- example ABI path for this build: `FreeBSD:14:amd64`

To enable publishing, set repository Pages source to **GitHub Actions**.

## Updating to a new AdGuard Home version

1. `./scripts/release.sh set-adguardhome <new-version>`
2. On FreeBSD: `make -C ports/www/adguardhome makesum` to refresh the SHA256/size
   in `ports/www/adguardhome/distinfo`. (Or update the `SHA256`/`SIZE` lines by
   hand from the release `checksums.txt` — the distinfo keys are prefixed with
   `adguardhome-<version>/`.)
3. Commit, then cut a release as above.

## License & attribution

This repository bundles code under several licenses:

- **Original code** — the `os-adguardhome` OPNsense plugin (`dns/adguardhome`)
  and the FreeBSD port glue (`ports/www/adguardhome`) — is licensed under the
  **BSD 2-Clause License** (see [`LICENSE`](LICENSE)).
- **OPNsense plugin build tooling** under `Mk/`, `Templates/`, `Scripts/` and
  `Keywords/` is Copyright (c) Franco Fichtner / Deciso B.V., **BSD 2-Clause**
  (see the headers in those files). It is reused unmodified.
- **AdGuard Home** (the `adguardhome` package) is a separate work by AdGuard
  Software Ltd., licensed under the **GNU General Public License v3.0**. This
  repository does not contain AdGuard's source; the port fetches AdGuard's
  **official, unmodified** FreeBSD/amd64 release binary at build time and
  repackages it. In line with GPLv3:
    - the binary is shipped unmodified, with its notices intact;
    - a copy of the license is installed at
      `/usr/local/share/licenses/adguardhome/LICENSE`;
    - the complete corresponding source for the exact version is available at
      <https://github.com/AdguardTeam/AdGuardHome> (the release tag matching
      `pkg info adguardhome`).

  The plugin only manages the AdGuard Home service and does not link or combine
  with its code (mere aggregation under GPLv3 §5), so the plugin's BSD license
  is unaffected.

> This project is community-maintained and is **not affiliated with, sponsored
> by, or endorsed by AdGuard**. "AdGuard" and "AdGuard Home" are trademarks of
> AdGuard Software Ltd., used here only to describe the packaged software.
