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

Auth settings applied via `PATCH /v1/projects/{ref}/config/auth`. Only include the fields you want to set — omitted fields are left unchanged.

| Field | Type | Description |
|---|---|---|
| `anonymous_users_enabled` | boolean | Allow anonymous sign-ins (users without email/password) |
| `disable_signup` | boolean | When `true`, new user registrations are blocked |
| `jwt_exp` | number | JWT token expiry time in seconds (e.g. `3600` = 1 hour) |
| `site_url` | string | The base URL of your app, used for redirect links in auth emails |
| `external.anonymous.enabled` | boolean | Enable the anonymous auth provider |
| `external.email.enabled` | boolean | Enable email/password sign-in |
| `external.email.double_confirm_changes` | boolean | Require confirmation when a user changes their email |
| `external.email.autoconfirm` | boolean | Skip email verification on signup (not recommended for production) |
| `mfa.enabled` | boolean | Enable multi-factor authentication |

Example:

```json
{
  "anonymous_users_enabled": true,
  "disable_signup": false,
  "jwt_exp": 3600,
  "site_url": "http://localhost:3000",
  "external": {
    "anonymous": { "enabled": true },
    "email": {
      "enabled": true,
      "double_confirm_changes": true,
      "autoconfirm": false
    }
  },
  "mfa": { "enabled": false }
}
```

### `postgrest.json`

PostgREST settings applied via `PATCH /v1/projects/{ref}/postgrest`. Controls how the auto-generated REST API behaves.

| Field | Type | Description |
|---|---|---|
| `db_schema` | string | Comma-separated list of schemas exposed through the REST API (e.g. `"public"`) |
| `max_rows` | number | Maximum number of rows returned per request. Limits unbounded queries |
| `db_extra_search_path` | string | Additional schemas added to the PostgreSQL `search_path` (e.g. `"public,extensions"`) |

Example:

```json
{
  "db_schema": "public",
  "max_rows": 1000,
  "db_extra_search_path": "public,extensions"
}
```

### `network.json`

Network restrictions applied via `POST /v1/projects/{ref}/network-restrictions/apply`. Controls which IPs can connect directly to your database.

| Field | Type | Description |
|---|---|---|
| `dbAllowedCidrs` | string[] | List of allowed CIDR ranges. An empty array `[]` means **allow all connections**. Add specific CIDRs like `"203.0.113.0/24"` to restrict access |

Example:

```json
{
  "dbAllowedCidrs": ["203.0.113.0/24", "10.0.0.0/8"]
}
```

### `ssl.json`

SSL enforcement applied via `PUT /v1/projects/{ref}/ssl-enforcement`. Controls whether database connections must use SSL.

| Field | Type | Description |
|---|---|---|
| `requestedConfig.database` | boolean | When `true`, all database connections must use SSL. Unencrypted connections are rejected |

Example:

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
