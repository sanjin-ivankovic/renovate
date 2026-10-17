# renovate

The central [Renovate](https://docs.renovatebot.com/) runner **and** shared
config preset for the homelab GitLab group.

One project, one schedule, one shared cache, and one group token autodiscover
and update every `homelab/*` repository that contains a `renovate.json`. This
replaces the per-repo `renovate:` jobs that previously each ran on their own
pipeline and schedule — the model recommended by the upstream
[renovate-runner](https://gitlab.com/renovate-bot/renovate-runner) project.

This repo is the dependency-management twin of
[`ci-components`](https://source.example.com/homelab/ci-components): both are shared
hubs that the other homelab repos extend rather than copy.

## What's here

| File | Role |
| --- | --- |
| `default.json` | The shared base preset every repo extends |
| `dockerfile-args.json` | Modular preset: annotated Dockerfile-`ARG` custom manager |
| `ci-components.json` | Modular preset: grouped + soaked `homelab/ci-components` pin bumps |
| `renovate.json` | This runner's own config (extends the preset + upstream) |
| `.gitlab-ci.yml` | The scheduled runner job, bot-side settings + config validation CI |

## The shared preset

`default.json` holds the config common to the whole homelab — commit/PR
conventions, scheduling, vulnerability alerts, the CI-image soak rules, and so
on. Every repo extends it from its own `renovate.json`:

```json
{
  "$schema": "https://docs.renovatebot.com/renovate-schema.json",
  "extends": ["local>example-org/renovate", "gitlab>renovate-bot/renovate-runner"]
}
```

Each repo then adds **only its own** `packageRules`, `customManagers`, and
dashboard text on top. Shared base + per-repo overrides — the same pattern as
a shared CI component: change the common policy once here, and every repo
inherits it on the next run.

Rules needed by more than one repo (but not all) live in **modular presets**
next to `default.json`, composed per repo:

```json
{
  "extends": [
    "local>example-org/renovate",
    "local>example-org/renovate:dockerfile-args",
    "local>example-org/renovate:ci-components",
    "gitlab>renovate-bot/renovate-runner"
  ]
}
```

- `dockerfile-args` — the `# renovate:`-annotated Dockerfile `ARG` custom
  manager (used by every repo with a CI image; previously copy-pasted).
- `ci-components` — the grouped, 3-day-soaked bump rule for the
  `homelab/ci-components` component pins.

## CI validation

Every MR/main push touching the JSON configs runs `validate:renovate-config`
(`renovate-config-validator --strict` in the pinned engine image) plus the
`scan-secrets` component. A broken preset here would break dependency updates
for the entire estate — local pre-commit can be bypassed; this gate cannot.

## How the runner works

- **Autodiscover**: `--autodiscover-filter=homelab/*` finds every project the
  `RENOVATE_TOKEN` can see that already has a `renovate.json`.
  `--onboarding=false` means no onboarding PRs for un-configured projects.
- **Schedule**: one daily pipeline schedule on this project (cron `0 3 * * *`,
  Europe/Berlin). The `renovate` job runs on schedules only; kick the first run
  with the schedule's play button.
- **Engine pin**: `CI_RENOVATE_IMAGE` pins the Renovate engine to a specific
  minor tag (Renovate-tracked) so one version governs the whole homelab.
- **Cache**: the whole `renovate/cache/` tree is persisted between runs so
  datasource lookups (GitHub tags/releases) stay warm.

## Required group CI/CD variables

Set under the `homelab` group (Settings → CI/CD → Variables, masked):

- **`RENOVATE_TOKEN`** — GitLab group access token (scopes: `api`, `read_user`,
  `write_repository`). Lets the bot read and update every `homelab/*` repo.
- **`RENOVATE_GITHUB_COM_TOKEN`** — github.com read-only PAT. Raises the API
  limit from 60/hr to 5000/hr for datasource + changelog lookups.
- **`DOCKER_HUB_USERNAME`** / **`DOCKER_HUB_TOKEN`** — Docker Hub auth (via
  `RENOVATE_HOST_RULES`) to avoid anonymous pull-rate limits.

## Post-upgrade commands

`postUpgradeTasks` defined in a repo's own `renovate.json` (e.g. proxmox-infra's
SHA256 refresh, helm-charts' `appVersion` bump) run only because this runner
allow-lists them bot-side via `RENOVATE_ALLOWED_COMMANDS`. The allow-list is a
trusted setting that must live here, not in repo config.

## Troubleshooting

- **Job stuck pending**: the runner only serves `docker`-tagged jobs; this
  project's `default.tags: [docker]` handles that. A new project without the tag
  would hang.
- **A repo isn't being updated**: confirm it has a `renovate.json` extending
  `local>example-org/renovate`, and that `RENOVATE_TOKEN` has access to it.
- **Verbose logs**: uncomment `LOG_LEVEL: debug` in `.gitlab-ci.yml` (the
  optional-settings block) while diagnosing, or read the debug NDJSON artifact
  the upstream template already writes.
- **Preview a config change**: uncomment `RENOVATE_DRY_RUN: full` to run without
  opening/updating PRs.
