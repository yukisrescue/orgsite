# Unplanned finding: wildcard Worker route captured the authoring host

**Found:** 2026-09-07, between Tasks 2 and 3.

## Symptom

`https://control.yukisrescue.org/` returned 200 serving the production static
site, before any reverse proxy existed for it.

## Cause

The zone had two Worker routes:

```
*.yukisrescue.org/*   -> yukis-rescue-org
yukisrescue.org/*     -> yukis-rescue-org
```

The wildcard matched every subdomain, `control.` included. Cloudflare served
the Worker and never forwarded the request to the origin. The DSM reverse proxy
in Task 3 would have appeared correctly configured and remained unreachable.

Separately, `wrangler.jsonc` declared `www.yukisrescue.org` with
`custom_domain: true`, but the account had **no** custom domains registered —
production ran entirely on plain zone routes. Repo config and deployed reality
had drifted.

## Fix

Applied additively so `www` was never uncovered:

1. Created `www.yukisrescue.org/*` -> `yukis-rescue-org`
2. Verified `www` and apex still returned 200
3. Deleted `*.yukisrescue.org/*` (id `cef7a8dab8d5468e84d9ea8cd8c56dbe`)
4. Re-verified; `control.` began reaching the origin (DSM default page)
5. Updated `wrangler.jsonc` to declare the two plain routes

## Rollback

Recreate the wildcard route:

```
POST /zones/{zone_id}/workers/routes
{"pattern":"*.yukisrescue.org/*","script":"yukis-rescue-org"}
```

## Related finding

Zone SSL mode was `full`, not `full (strict)`. That is why `control.` returned
200 rather than 526 while presenting a mismatched origin certificate. Changing
it requires Zone Settings: Edit, deliberately not granted to any token, so it
is an owner dashboard action in Task 3 Step 4.

**Order matters:** bind the Origin CA certificate to the DSM rule *before*
switching to Full (strict), or `control.` returns 526 in the interval.
