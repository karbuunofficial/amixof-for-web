# AMIXOF modifications

This program is a modified version of Stoat for Web.

- Upstream project: https://github.com/stoatchat/for-web
- Upstream commit: `4017c18bf8063bf0fd1a5d01d415871613f110f9` (release 0.15.3)
- Modified: 16 October 2026
- Operator: AMIXOF, https://www.amixof.com
- License: GNU Affero General Public License, version 3. The whole modified work is released under that license. See `LICENSE`.
- Warranty: there is no warranty for this program.

Upstream copyright notices stay in place, including:

```
Stoat Frontend
Copyright (C) 2026  Revolt Platforms Ltd
```

## What changed

User-facing product name, wordmark, manifest text, authentication copy, settings labels, support and legal links, and the places that previously sent people to Stoat donation, feedback, changelog, developer, or social pages. Technical protocol names are unchanged, including `/.well-known/stoat`, `Revolt.toml`, and the `isStoat` check that detects the official stoat.chat host.

The private Stoat brand-asset repository is not included. The build uses the fallback assets in this repository, with the wordmark replaced by the text AMIXOF. The logo is rendered with the `AmixofWordmark` Solid component (not `wordmark.svg?component-solid`, which drops SVG `<text>` and showed a blank mark).

The Stoat server images are not part of this repository and were not modified for this deployment.

## Build the web client that www.amixof.com serves

```bash
git clone --recurse-submodules https://github.com/karbuunofficial/amixof-for-web.git
cd amixof-for-web
docker build -t amixof-for-web:local .
```

The image serves the built client on port 5000. Placeholder `VITE_*` values are replaced when the container starts, using the same `docker/inject.js` entrypoint as upstream.

`packages/client/assets` is an optional upstream brand submodule and is not required. When it is absent, `packages/client/scripts/copyAssets.mjs` uses `packages/client/scripts/assets_fallback`.
