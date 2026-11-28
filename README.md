# renovate

The central [Renovate](https://docs.renovatebot.com/) runner **and** shared
config preset for the homelab GitLab group.

One project, one schedule, one shared cache, and one group token autodiscover
and update every `homelab/*` repository that contains a `renovate.json`; no
repository runs its own `renovate:` job. This is the model recommended by the
upstream [renovate-runner](https://gitlab.com/renovate-bot/renovate-runner)
project.

This repo is the dependency-management twin of
[`ci-components`](https://source.example.com/homelab/ci-components): both are
shared hubs that the other homelab repos extend rather than copy.

## What's here

<!-- markdownlint-disable MD013 -->
| File | Role |
| --- | --- |
| `default.json` | The shared base preset every repo extends |
| `dockerfile-args.json` | Modular preset: annotated Dockerfile-`ARG` custom manager |
| `ci-components.json` | Modular preset: grouped + soaked `homelab/ci-components` pin bumps |
| `renovate.json` | This runner's own config (extends the preset + upstream) |
| `.gitlab-ci.yml` | The scheduled runner job, bot-side settings + config validation CI |
<!-- markdownlint-enable MD013 -->

## Quick start

To bring a `homelab/*` repo under Renovate, commit a `renovate.json` that
extends the shared preset:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["local>example-org/renovate"]
}
```

The next run (every 4 hours) picks it up; there is no onboarding MR.

Do not extend `gitlab>renovate-bot/renovate-runner` in a consumer repo. It
tracks the runner template and engine image, which only this repo has, and
it is fetched from gitlab.com: when gitlab.com rate-limits, every repo that
extends it is skipped for the whole run.

## The shared preset

`default.json` holds the config common to the whole homelab — commit/PR
conventions, scheduling, vulnerability alerts, the CI-image soak rules, and so
on. Every repo extends it from its own `renovate.json` (see Quick start).
Each repo then adds **only its own** `packageRules`, `customManagers`, and
dashboard text on top. Shared base + per-repo overrides — the same pattern as
a shared CI component: change the common policy once here, and every repo
inherits it on the next run.

CI files name hosts through variables (`component: $CI_SERVER_FQDN/...`,
images under `$HARBOR_HOST/...`). The preset's `registryAliases` resolve them
for Renovate (`$CI_SERVER_FQDN` → `source.example.com`, `$HARBOR_HOST` →
`registry.example.com`) so those pins stay tracked.

Rules needed by more than one repo (but not all) live in **modular presets**
next to `default.json`, composed per repo:

```json
{
  "extends": [
    "local>example-org/renovate",
    "local>example-org/renovate:dockerfile-args",
    "local>example-org/renovate:ci-components"
  ]
}
```

- `dockerfile-args` — the `# renovate:`-annotated Dockerfile `ARG` custom
  manager, extended by every repo with a CI image instead of each carrying
  its own copy.
- `ci-components` — the grouped, 3-day-soaked bump rule for the
  `homelab/ci-components` component pins.
- `ci-variables` — tracks `# renovate:`-annotated `*_IMAGE` and `*_VERSION`
  entries under `variables:` in `.gitlab-ci.yml`, which the gitlabci manager
  does not read. Every repo pins the shared CI base this way
  (`CI_IMAGE` or `CI_BASE_IMAGE`, `ci:latest@sha256:...`), so a new base
  arrives as a Renovate MR that runs the repo's pipeline on it first.

## Lanes: soak and automerge

Each repo puts its paths into one of five **lane presets**. A lane decides
how long an update waits after its release (the soak, per update type) and
which updates Renovate merges itself. Major updates are always manual.

| Lane | Soak (patch / minor / major) | Renovate merges |
| --- | --- | --- |
| `lane-fast` | 1d / 1d / 7d | patch, minor |
| `lane-standard` | 1d / 3d / 7d | patch, minor |
| `lane-careful` | 3d / 7d / 14d | patch |
| `lane-critical` | 7d / 14d / 21d | patch |
| `lane-manual` | 7d / 14d / 21d | nothing |

A lane takes one file glob as its argument; braces group several paths:

```json
"extends": [
  "local>example-org/renovate",
  "local>example-org/renovate:lane-careful({apps/user/{docuseal,opengist}/**,apps/infra/loki/**})"
]
```

Which lane? Ask what a bad release costs. A day of a missing search page:
fast. A rollback with nothing lost, or CI would have caught it: standard.
Data or alerts at risk: careful. Many things break at once but you still
press deploy: critical. The merge itself deploys something critical:
manual.

Rules that hold in every lane:

- Anything no lane covers gets the careful soak (`default.json`).
- Every repo's CI image (`.ci/docker/Dockerfile`) is in the standard lane,
  set in `default.json`: its MR builds and smoke-tests the image
  (`ci-image-test`), so a broken tool bump fails before merge.
- Renovate merges on its own run, never GitLab (`platformAutomerge: false`):
  GitLab CE's "Pipelines must succeed" ignores Renovate's
  `renovate/stability-days` status, so a GitLab-side merge skips the soak.
- GHCR and Quay publish no release dates, so their images cannot be soaked.
  With `internalChecksFilter: strict` Renovate would create no branch and
  only list the update on the Dependency Dashboard; instead the MR opens at
  once, and in careful, critical and manual it waits for a person.
- A repo's own `minimumReleaseAge` or `automerge` rules come after the lanes
  and win; a repo using lanes keeps none for the same paths.
- Automerged MRs are not assigned (`assignAutomerge: false`), so the MRs
  assigned to you are the ones that need you. The `manual-merge` label marks
  the same set.

## CI validation

Every MR/main push touching the JSON configs runs `validate:renovate-config`
(`renovate-config-validator --strict` in the pinned engine image) plus the
`scan-secrets` component. A broken preset here would break dependency updates
for the entire estate — local pre-commit can be bypassed; this gate cannot.

## How the runner works

- **Autodiscover**: `--autodiscover-filter=homelab/*` finds every project the
  `RENOVATE_TOKEN` can see that already has a `renovate.json`.
  `--onboarding=false` means no onboarding PRs for un-configured projects.
- **Schedule**: one pipeline schedule on this project, every 4 hours (cron
  `0 */4 * * *`, Europe/Berlin). Renovate merges green automerge MRs itself,
  on a run, so the cadence is also the longest a green MR waits. The
  `renovate` job runs on schedules only; kick the first run with the
  schedule's play button.
- **Engine pin**: `CI_RENOVATE_IMAGE` pins the Renovate engine to a specific
  minor tag (Renovate-tracked) so one version governs the whole homelab.
- **Internal hosts**: `RENOVATE_HOST_RULES` grants `allowInternal` to
  `https://registry.example.com` and `https://source.example.com`. Both
  resolve to private (10/8) addresses, which Renovate treats as internal;
  `allowInternal` is global-only, so it lives here, not in a repo
  `renovate.json`.
- **Cache**: the whole `renovate/cache/` tree is persisted between runs so
  datasource lookups (GitHub tags/releases) stay warm.

## Secrets

No CI/CD variables. The `renovate` job reads HashiCorp Vault
`kv/ci/renovate` at start (`scripts/vault-env.mjs`, an `id_tokens` login as
role `ci-renovate`) and exports:

- **`token`** → `RENOVATE_TOKEN`: the `renovate` group access token
  (Developer, `api`). Lets the bot read and update every `homelab/*` repo.
- **`github_com_token`** → `GITHUB_COM_TOKEN`: github.com read-only PAT.
  Raises the API limit from 60/hr to 5000/hr for datasource and changelog
  lookups.
- **`docker_hub_username`** / **`docker_hub_token`**: prepended to
  `RENOVATE_HOST_RULES` as the `docker.io` rule, against anonymous pull-rate
  limits.

## Post-upgrade commands

`postUpgradeTasks` defined in a repo's own `renovate.json` (proxmox-infra's
SHA256 refresh, argo-apps' vendored-chart refresh, helm-charts' `appVersion`
bump) run only because this runner
allow-lists them bot-side via `RENOVATE_ALLOWED_COMMANDS`. The allow-list is a
trusted setting that must live here, not in repo config.

## Troubleshooting

- **Job stuck pending**: the runner only serves `docker`-tagged jobs; this
  project's `default.tags: [docker]` handles that. A new project without the tag
  would hang.
- **A repo isn't being updated**: confirm it has a `renovate.json` extending
  `local>example-org/renovate`, and that the `renovate` group token can see it.
- **Verbose logs**: read the debug NDJSON artifact the upstream template
  writes for every run, or run `make lanes REPOS=homelab/<repo>` locally,
  which keeps its debug log in `.cache/lanes/dry-run.ndjson`.
- **Preview a config change**: `make lanes-local DIR=../<repo>` (see
  Develop); nothing reaches GitLab.

## Develop

```bash
make setup        # pre-commit hooks
make validate     # every preset through renovate-config-validator --strict
make lanes REPOS="homelab/argo-apps"   # lane report of repos as on GitLab
make lanes-local DIR=../argo-apps      # same for a working tree + these presets
```

The validator proves a preset parses, not what it does. `make lanes` runs a
read-only lookup dry run (`--dry-run=lookup`) with the engine version CI uses
and resolves every dependency through the engine's own package rules:
`.cache/lanes/lanes.tsv` lists file, dependency, update type, lane, soak,
automerge and the effective automerge (an automerge whose soak needs a
release date the registry does not publish never happens). `make
lanes-local` does the same for a checkout's working tree, uncommitted changes
included, with this checkout's presets served over loopback HTTP, so a preset
and a repo's `renovate.json` can be proven together before either is
committed. Both use your `glab` login (and `gh`, if present); no token is
printed.

## License

MIT, see [LICENSE](LICENSE).
