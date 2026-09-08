# Task 13 — backups (exercised 2026-09-08)

## What is backed up

| Item | Where it lives | In backup? |
|---|---|---|
| Database (pages, users, settings, theme customisations) | `wordpress_wp_db` volume | **yes** — `db-*.sql.gz` |
| Media library | `wordpress_wp_uploads` volume | **yes** — `content-*.tar.gz` |
| Themes | `wordpress_wp_themes` volume | **yes** — `content-*.tar.gz` |
| mu-plugins, compose, scripts | this repo | in git |
| Static export | `site/` in this repo | in git, and regenerable |
| `.env` secrets | node2 only | **no** — recreate from `~/workspace/yukis/tokens.yml` |

`.env` is deliberately excluded. Putting live credentials in a backup on a
network share widens their exposure for no gain, since every value in it can be
regenerated from the credential files on the operator machine.

## Schedule and location

Daily at **03:30 UTC**, to `/media/assets/server/backup/wordpress` on the NAS
(NFS from the Synology). Retention **14 days**; only `*.gz` files are pruned, so
anything else left in that directory is untouched.

Runs as a `mariadb:11` container that reaches the database over the compose
network and mounts the content volumes read-only. It is **not** given the docker
socket: a backup job should not be able to control the host's containers.

It runs as uid 1000 because NFS `root_squash` would otherwise map root to
nobody and the writes would silently fail.

A container loop rather than a systemd timer, for the same reason as the
publisher: node2 has no passwordless sudo, and a container moves to a VPS while
host units do not.

## Integrity checks

The script refuses to report success unless:

- `gzip -t` passes on the database dump
- `tar tzf` passes on the content archive
- the database dump is at least 10 KiB

The size floor exists because a failed dump can still exit 0 and leave a
plausible-looking file. A backup script that writes a corrupt archive and
reports success is worse than none, because it removes the pressure to check.

Measured first run: database 491 KiB, content 13.4 MiB.

## Restore — exercised, not assumed

```bash
ssh node2.lan
cd /opt/wordpress
./restore.sh /media/assets/server/backup/wordpress/db-<stamp>.sql.gz \
             /media/assets/server/backup/wordpress/content-<stamp>.tar.gz
```

It verifies both archives before destroying anything, then prompts for the word
`RESTORE`. `ASSUME_YES=1` skips the prompt for automation.

**Verified 2026-09-08** by the only method that actually proves anything:

1. Took a backup
2. Created a page **after** it, as a marker
3. Restored
4. Confirmed the marker was **gone** — so the database really was replaced
5. Confirmed the four real pages, four users, active theme and media library
   were all intact
6. Confirmed WordPress still served all four pages, and that a static export
   still ran correctly afterwards
7. Confirmed production was unaffected throughout

## What a restore does not cover

The database and content only. After restoring onto fresh volumes you must also:

1. Recreate `.env` from `~/workspace/yukis/tokens.yml`
2. Run `./kickoff.sh` (which fixes volume ownership)
3. Run `wp eval-file /tmp/ss-configure.php` — Simply Static's configuration
   lives in `wp_options` and reverts to defaults that produce a broken export

Step 3 is the one that will be forgotten. Without it the export silently
produces the wrong site; see `task-08-simply-static.md`.
