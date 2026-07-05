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

Because AdGuard Home owns its own configuration, its DNS/web listen ports are set
inside AdGuard Home's own UI. Choose **high (non-privileged) ports** there — e.g.
DNS on `5353` and the admin UI on `3000` — so the service stays unprivileged.

## First-time setup

1. Install `os-adguardhome` (see below) and open `Services -> AdGuard Home`.
2. Enable the service and **Save**. (Run-as user defaults to `adguardhome`; leave
   it unless you have a specific reason to change it.)
3. Click **Open AdGuard Home** (the setup wizard listens on port `3000` by
   default) and complete the wizard. **In the wizard, set the DNS listen port to
   a high port such as `5353`** (not 53) and pick a non-privileged admin port
   (3000 is fine). AdGuard Home writes its config on finish.
4. If you later change AdGuard Home's admin port inside its own UI, update the
   plugin's *Web Interface Port* field so the link keeps working.

### Coexisting with Unbound (recommended topology)

Keep OPNsense's Unbound as the resolver on port 53 and place AdGuard Home in
front of it as the filtering layer. Nothing binds 53 except Unbound, and AdGuard
Home forwards to Unbound for actual resolution:

```
clients ──► AdGuard Home (:5353, filtering)  ──►  Unbound (127.0.0.1:53)  ──► internet
```

Configure, all in the respective web UIs (this plugin does not do it for you):

1. **AdGuard Home UI → Settings → DNS settings**
   - *DNS server / listen*: a high port, e.g. `5353` (never 53).
   - *Upstream DNS servers*: `127.0.0.1:53` (i.e. Unbound). Optionally set the
     bootstrap/fallback DNS to `127.0.0.1:53` as well.
2. **OPNsense → Services → Unbound DNS**
   - Leave Unbound listening on 53 for your clients. (Do **not** point Unbound
     back at AdGuard Home, or you create a resolution loop.)
3. **Point clients at AdGuard Home's filtering port.** Since AdGuard Home is on
   `5353`, either:
   - hand out AdGuard Home's IP as DNS to clients that can use a custom port, or
   - add a **Firewall → NAT → Port Forward** rule on your LAN that redirects
     DNS (`53`) to `127.0.0.1:5353` (AdGuard Home), so all client DNS is
     transparently filtered and Unbound is reached only as AdGuard's upstream.

The admin web port (default `3000`) can collide with the OPNsense GUI if you set
it to `80`/`443` — keep it on a free high port.

## Integrate the repo in OPNsense (automatic updates)

Create a pkg repository file on the firewall:

```sh
cat >/usr/local/etc/pkg/repos/adguardhome.conf <<'EOF'
adguardhome: {
  url: "https://daniel-k.github.io/opnsense-plugin-adguardhome/${ABI}",
  mirror_type: "none",
  signature_type: "none",
  enabled: yes
}
EOF
pkg update -f
```

Then install from the repo:

```sh
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
`freebsd-14_4-downloads-v1-...`

To force a fresh cache generation, bump the `v1` part (for example to `v2`),
commit, and push (keep both workflow files in sync). The first run after the
bump is expected to be slower (cold cache). The next runs should be faster
again.

When to refresh on purpose:

- after changing FreeBSD release in CI (for example `14.4` -> `14.5`)
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
