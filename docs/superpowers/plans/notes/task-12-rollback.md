# Task 12 — end-to-end publish and rollback (exercised 2026-09-07)

## Go-live

`www.yukisrescue.org` switched from the hand-written static pages to the
WordPress-generated export. Verified independently of the pipeline's own
report: all four pages return 200 with correct titles, the organisation footer
renders, and every asset resolves.

## Rollback procedure

**Measured: 11 seconds**, verified live in both directions.

```bash
# On node2. Find the publish commit to undo:
docker exec yukis-publisher git -C /repo log --oneline -5

# Revert it and redeploy:
docker exec yukis-publisher git -C /repo revert --no-edit <sha>
docker exec -e REPO_DIR=/repo yukis-publisher /deploy.sh

# Push so the remote matches what is deployed:
docker exec yukis-publisher git -C /repo push origin main
```

Roll forward is the same command against the revert commit.

`deploy.sh` verifies production actually serves the new build before reporting
success, so a rollback that did not take effect fails loudly rather than
appearing to work.

## Why this matters

Designers publish to production unreviewed. The preview/promotion gate is
deferred to a later sprint, so **rollback speed is the mitigation** for a bad
publish. It has now been exercised rather than assumed.

## Deploy path

GitHub Actions is disabled account-wide on the repository owner, so `deploy.sh`
runs on node2. `.github/workflows/deploy.yml` is retained and does the same
thing; when Actions is reinstated, drop the `deploy.sh` call from
`watch-export.sh` and the workflow takes over unchanged.

## Faults found during this task

Three, all of which presented as success:

1. **BusyBox `find` has no `-printf`.** The watcher's change detection was
   empty on every tick, so it silently never published and logged nothing.
   Fixed with `findutils` plus a startup assertion.

2. **Git "dubious ownership" on the bind-mounted repo.** `git status` failed,
   returned empty, and `publish.sh` read that as "no changes to publish" and
   exited 0 — deploying an uncommitted tree while the audit trail was never
   written. Fixed with `safe.directory`, and `publish.sh` now proves git works
   before trusting its output. Regression test added.

3. **No credential helper and no divergence handling** in the publisher, so
   every push failed. `publish.sh` now rebases onto the remote first, since
   humans commit docs and config while the publisher commits `site/`.

Fault 2 is the one worth remembering: the pipeline reported a clean run while
doing the wrong thing.

## Known benign message

`fatal: unable to write credential store: Resource busy` appears on push. The
credential file is mounted read-only on purpose; git only wants to cache an
approval it does not need. The push succeeds.
