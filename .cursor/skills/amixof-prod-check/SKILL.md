---
name: amixof-prod-check
description: Check the live AMIXOF site in a real browser at 390px and 1360px, light and dark — status codes, console errors, horizontal scroll, Stoat/Revolt text, wordmark centring, with screenshots; optionally signed in. Use after every deploy or rollback, and when asked whether the live site looks or works right.
---

# Check what users see on www.amixof.com

```bash
node .cursor/skills/amixof-prod-check/scripts/prod-check.mjs                 # signed-out screens on the live site
node .cursor/skills/amixof-prod-check/scripts/prod-check.mjs --signed-in     # + home, friends, settings
node .cursor/skills/amixof-prod-check/scripts/prod-check.mjs --pages /login,/login/create
node .cursor/skills/amixof-prod-check/scripts/prod-check.mjs --base http://localhost:4173
```

Default pages: `/login`, `/login/auth`, `/login/create`, `/login/reset`, `/login/resend`.
Each runs at 390×844 (touch) and 1360×900, in light and dark colour scheme, with the service
worker blocked so you always get the newest bundle.

Checks per screen: HTTP status, no uncaught errors or console errors, no horizontal scroll, no
"Stoat"/"Revolt" in visible text or title, and on `/login` the `AMIXOF` wordmark renders and is
centred. Results and screenshots land in `.cursor/artifacts/prod-check-<ts>/` (`report.txt`).

## Signed-in mode

Needs a dedicated test account in `.cursor/amixof.env` (`AMIXOF_TEST_EMAIL`,
`AMIXOF_TEST_PASSWORD`). Never use a real person's account. If the instance has a captcha or the
account has MFA, sign-in will fail and the report says so. Then the signed-in screens are
**not verified**, and you must say that.

## Reading results

- **Look at the screenshots** for every screen you changed. A pass means the automated checks
  passed. The page can still look wrong.
- A console error that also happens on the previous image is pre-existing. Note it under "Found,
  not fixed", but do not roll back for it.
- A new failure caused by your deploy → `rollback.sh last` (see `amixof-rollback`), then fix
  forward. Do not roll back for failures that predate your deploy.
- First run on a machine: `pnpm install --frozen-lockfile` and
  `pnpm --filter client exec playwright install chromium`.

Put the summary line ("N passed, M failed") and any FAIL lines in your report under "Measured".
