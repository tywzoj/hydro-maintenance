# Hydro Maintenance Scripts

Utility scripts for HydroOJ maintenance tasks.

## Files

- `download-geoip.sh`: Download and install GeoLite2 City database with `curl`.
- `download-geoip-aria.sh`: Download and install GeoLite2 City database with `aria2c` (resume and parallel download support).
- `hydro-restic-backup.sh`: Run HydroOJ backup to a Restic repository.
- `update-official-addons.sh`: Install official public addon and optional private addon.
- `update-trusted-proxies.sh`: Update `trusted_proxies static` address lists in the Hydro Caddyfile.

## Requirements

- Bash
- HydroOJ CLI (`hydrooj`)
- For GeoIP scripts:
  - `yarn`
  - `curl` (for `download-geoip.sh`)
  - `aria2c` (for `download-geoip-aria.sh`)
- For backup script:
  - `restic`
- For trusted proxy updates:
  - Alibaba Cloud CLI (`aliyun`), configured with credentials for ESA
  - `jq`

Some scripts attempt to load `/root/.nix-profile/etc/profile.d/nix.sh` when required commands are missing in PATH.

## Environment Files

Environment files are optional and loaded only if present.

- `hydro-restic-backup.sh` reads `hydro-restic-backup.env`
  - Required vars:
    - `RESTIC_REPOSITORY`
    - `RESTIC_PASSWORD`
  - Optional vars:
    - `AWS_ACCESS_KEY_ID`
    - `AWS_SECRET_ACCESS_KEY`
    - `RESTIC_REPOSITORY_OPTIONS`
- `update-official-addons.sh` reads `update-official-addons.env`
  - Optional var:
    - `PRIVATE_ADDON_URL`

`.gitignore` ignores `*.env`, so local environment files are not committed.

## Usage

Run scripts from repository root:

```bash
bash download-geoip.sh
bash download-geoip-aria.sh
bash hydro-restic-backup.sh
bash update-official-addons.sh
bash update-trusted-proxies.sh
```

Or make them executable:

```bash
chmod +x *.sh
./download-geoip.sh
./download-geoip-aria.sh
./hydro-restic-backup.sh
./update-official-addons.sh
./update-trusted-proxies.sh
```

## Notes

- `update-official-addons.sh` always installs public addon:
  - `https://hydro.ac/hydroac-client.zip`
- Private addon is installed only when `PRIVATE_ADDON_URL` is set.
- `update-trusted-proxies.sh` first requests an Alibaba Cloud ESA origin protection
  IP whitelist update, then requests the current whitelist and combines its IPv4
  and IPv6 entries. It defaults to region `cn-hangzhou` and site ID
  `177345139939568`; set `REGION` or `SITE_ID` to override these values.
- The default target is `/root/.hydro/Caddyfile`. Set `CADDYFILE` to a different
  path when testing. Only `trusted_proxies static` directives inside `servers`
  blocks are updated; other addresses, directives, and comments are preserved.
