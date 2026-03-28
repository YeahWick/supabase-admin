# supabase-admin

A reusable GitHub Action for managing Supabase project configuration as code. Drop it into any repo to apply auth, PostgREST, network, and SSL settings via the [Supabase Management API](https://api.supabase.com/v1) — no CLI or SDK required.

## Quick start

### 1. Add config files to your repo

Create a `.supabase/` directory (or any directory you prefer) with the configs you want to manage:

```
your-repo/
  .supabase/
    auth.json          # Auth settings (providers, JWT expiry, MFA, etc.)
    postgrest.json     # PostgREST settings (exposed schemas, max rows, etc.)
    network.json       # Allowed CIDRs for database access
    ssl.json           # SSL enforcement settings
```

Only include the files you need — the action skips any that are missing.

### 2. Add your Supabase access token as a secret

Go to your repo's **Settings > Secrets and variables > Actions** and add:

| Secret | Description |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | Personal Access Token from [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens) |

### 3. Create a workflow

```yaml
# .github/workflows/apply-supabase-config.yml
name: Apply Supabase Config

on:
  push:
    branches: [main]
    paths:
      - '.supabase/**'
  workflow_dispatch:

jobs:
  apply:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: yeahwick/supabase-admin@main
        with:
          project_ref: abcdefghijklmnop       # your Supabase project ref
          config_dir: .supabase                # default, can be omitted
          supabase_token: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

That's it. Pushing changes to `.supabase/` will automatically apply them to your Supabase project.

## Action inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `project_ref` | Yes | — | Supabase project reference ID |
| `config_dir` | No | `.supabase` | Directory containing config JSON files |
| `supabase_token` | Yes | — | Supabase Personal Access Token |

## Config file reference

### `auth.json`

Auth settings applied via `PATCH /v1/projects/{ref}/config/auth`. Example:

```json
{
  "EXTERNAL_ANONYMOUS_USERS_ENABLED": true,
  "JWT_EXP": 3600,
  "MFA_MAX_ENROLLED_FACTORS": 10
}
```

### `postgrest.json`

PostgREST settings applied via `PATCH /v1/projects/{ref}/postgrest`. Example:

```json
{
  "db_schema": "public",
  "max_rows": 1000,
  "db_extra_search_path": "public,extensions"
}
```

### `network.json`

Network restrictions applied via `POST /v1/projects/{ref}/network-restrictions/apply`. Example:

```json
{
  "dbAllowedCidrs": ["0.0.0.0/0"]
}
```

### `ssl.json`

SSL enforcement applied via `PUT /v1/projects/{ref}/ssl-enforcement`. Example:

```json
{
  "requestedConfig": {
    "database": true
  }
}
```

## Multiple environments

Use separate workflows or matrix strategies to target different projects:

```yaml
jobs:
  apply:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        include:
          - env: staging
            project_ref: staging-ref-here
            config_dir: .supabase/staging
          - env: production
            project_ref: production-ref-here
            config_dir: .supabase/production
    steps:
      - uses: actions/checkout@v4
      - uses: yeahwick/supabase-admin@main
        with:
          project_ref: ${{ matrix.project_ref }}
          config_dir: ${{ matrix.config_dir }}
          supabase_token: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

## Using this repo directly

This repo also includes inspection and mutation workflows for centralized management of multiple Supabase projects. See the `.github/workflows/` directory and the `projects/` directory for per-project config examples.
