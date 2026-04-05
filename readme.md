# supabase-admin

A reusable GitHub Action for managing Supabase project configuration as code. Drop it into any repo to apply auth, PostgREST, network, SSL, realtime, and storage settings, run SQL migrations, manage storage buckets and secrets, and deploy edge functions — all via the [Supabase Management API](https://api.supabase.com/v1). No CLI or SDK required.

## Quick start

### 1. Add config files to your repo

Create a `.supabase/` directory (or any directory you prefer) with the configs you want to manage:

```
your-repo/
  .supabase/
    auth.json            # Auth settings (providers, JWT expiry, MFA, etc.)
    postgrest.json       # PostgREST settings (exposed schemas, max rows, etc.)
    network.json         # Allowed CIDRs for database access
    ssl.json             # SSL enforcement settings
    realtime.json        # Realtime broadcast/presence settings
    storage-config.json  # Storage global settings (file size limits, image transforms)
    storage.json         # Storage bucket definitions
    secrets.json         # Secrets for edge functions / Postgres Vault
  migrations/
    001_create_todos.sql # SQL migration files (applied in sorted order)
    002_add_indexes.sql
  functions/
    hello-world/
      index.ts           # Edge function entry point
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
        id: supabase
        with:
          project_ref: abcdefghijklmnop       # your Supabase project ref
          config_dir: .supabase                # default, can be omitted
          schema_dir: .supabase/migrations     # optional: SQL migrations
          supabase_token: ${{ secrets.SUPABASE_ACCESS_TOKEN }}

      # Outputs are available for downstream steps
      - run: echo "Project URL: ${{ steps.supabase.outputs.project_url }}"
```

That's it. Pushing changes to `.supabase/` will automatically apply them to your Supabase project.

## Multi-project GitOps workflow

If you manage multiple Supabase projects in one repo, the included workflows give you a full GitOps loop with PR-time plan previews and `/supa-apply` apply commands.

### How it works

| Workflow | Trigger | What it does |
|---|---|---|
| `pr-plan.yml` | PR opened/updated touching `projects/**` | Posts a diff comment showing what would change |
| `pr-apply.yml` | `/supa-apply` comment on a PR | Applies changes immediately (write-access only) |
| `apply-on-merge.yml` | Push to `main` touching `projects/**` | Auto-applies on merge |

### Setup

#### 1. Add the workflows to your repo

Copy `.github/workflows/pr-plan.yml`, `pr-apply.yml`, and `apply-on-merge.yml` from this repo into your own.

#### 2. Add your Supabase access token

Go to **Settings > Secrets and variables > Actions** and add:

| Secret name | Value |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | Personal Access Token from [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens) |

#### 3. Set up a project directory

Create a directory under `projects/` for each Supabase project you want to manage. Add a `project.json` file for auto-discovery:

```
projects/
  my-app-production/
    project.json         # required for auto-discovery
    auth.json
    postgrest.json
    migrations/
      001_create_todos.sql
    functions/
      hello-world/
        index.ts
  my-app-staging/
    project.json
    auth.json
```

**`project.json`** — metadata used by the workflows:

```json
{
  "project_ref": "abcdefghijklmnop",
  "project_name": "my-app",
  "environment": "production"
}
```

| Field | Required | Description |
|---|---|---|
| `project_ref` | Yes | Supabase project reference ID (found in project settings) |
| `project_name` | No | Human-readable name shown in PR comments |
| `environment` | No | Environment label (e.g. `staging`, `production`) shown in PR comments |

### Usage

**Open a PR** that modifies any file under `projects/` — the plan workflow automatically posts a comment showing what would change:

```
## Supabase Plan: my-app (production)
> Planned for commit `a1b2c3d`

### Auth Config — ⚠️ changes detected
| Key | Current | Desired |
|-----|---------|---------|
| `jwt_exp` | `3600` | `7200` |

### PostgREST Config — no changes

---
Comment `/supa-apply` to apply these changes.
```

**Apply before merge** by commenting `/supa-apply` on the PR. Only collaborators with write access can trigger this. To apply a specific project only:

```
/supa-apply staging
```

**Apply on merge** happens automatically when the PR is merged to `main`.

## Action inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `mode` | No | `apply` | `"apply"` to configure an existing project, `"create"` to provision a new one first |
| `project_ref` | No* | — | Supabase project reference ID. *Required when mode is `apply` |
| `organization_id` | No* | — | Supabase organization ID. *Required when mode is `create` |
| `project_name` | No* | — | Name for the new project. *Required when mode is `create` |
| `region` | No | `us-east-1` | Region for the new project (only used with `create`) |
| `db_password` | No* | — | Database password. *Required when mode is `create` |
| `config_dir` | No | `.supabase` | Directory containing config JSON files |
| `schema_dir` | No | — | Directory containing `.sql` migration files |
| `secrets_file` | No | — | Path to JSON file with secrets to push |
| `secrets` | No | — | JSON string of secrets (e.g. `'{"KEY": "value"}'`). Supports `${{ secrets.X }}` expressions. Takes precedence over `secrets_file` |
| `functions_dir` | No | — | Directory containing edge function subdirectories |
| `supabase_token` | Yes | — | Supabase Personal Access Token |

## Action outputs

All outputs are available after the action runs, regardless of mode.

| Output | Description |
|---|---|
| `project_ref` | Supabase project reference ID |
| `project_url` | Project API URL (`https://<ref>.supabase.co`) |
| `anon_key` | Public anon API key |
| `service_role_key` | Service role API key (use carefully) |

Keys are automatically masked in workflow logs.

## Project creation

Use `mode: create` to provision a new Supabase project before applying config:

```yaml
- uses: yeahwick/supabase-admin@main
  id: create
  with:
    mode: create
    organization_id: org_abc123
    project_name: my-todo-app
    region: us-east-1
    db_password: ${{ secrets.DB_PASSWORD }}
    config_dir: .supabase
    schema_dir: .supabase/migrations
    supabase_token: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

The action creates the project, waits for all services to become healthy (up to 10 minutes), then applies any config files and migrations. The `project_ref` output is available for downstream steps.

You can also chain create and apply as separate steps:

```yaml
- uses: yeahwick/supabase-admin@main
  id: create
  with:
    mode: create
    organization_id: org_abc123
    project_name: my-todo-app
    db_password: ${{ secrets.DB_PASSWORD }}
    supabase_token: ${{ secrets.SUPABASE_ACCESS_TOKEN }}

- uses: yeahwick/supabase-admin@main
  with:
    project_ref: ${{ steps.create.outputs.project_ref }}
    config_dir: .supabase
    schema_dir: .supabase/migrations
    supabase_token: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

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

### `realtime.json`

Realtime settings applied via `PATCH /v1/projects/{ref}/config/realtime`. Controls broadcast, presence, and rate limits for the Realtime service.

Example:

```json
{
  "db_slot": "supabase_realtime_rls",
  "max_events_per_second": 100,
  "max_joins_per_second": 100,
  "max_channels_per_client": 100,
  "max_bytes_per_second": 100000
}
```

### `storage-config.json`

Global storage settings applied via `PATCH /v1/projects/{ref}/config/storage`. Controls global limits and features for the Storage service.

Example:

```json
{
  "fileSizeLimit": 52428800,
  "features": {
    "imageTransformation": {
      "enabled": true
    }
  }
}
```

### `storage.json`

Storage bucket definitions. Buckets are created if they don't exist, or updated if they do.

| Field | Type | Description |
|---|---|---|
| `buckets[].name` | string | Bucket name (must be unique) |
| `buckets[].public` | boolean | Whether files are publicly accessible without auth |
| `buckets[].file_size_limit` | number | Max file size in bytes |
| `buckets[].allowed_mime_types` | string[] | Allowed MIME types for uploads |

Example:

```json
{
  "buckets": [
    {
      "name": "avatars",
      "public": true,
      "file_size_limit": 5242880,
      "allowed_mime_types": ["image/png", "image/jpeg", "image/webp"]
    },
    {
      "name": "documents",
      "public": false,
      "file_size_limit": 10485760,
      "allowed_mime_types": ["application/pdf", "text/plain"]
    }
  ]
}
```

### `secrets.json`

Secrets pushed via `POST /v1/projects/{ref}/secrets`. These are available as environment variables in Edge Functions and in Postgres Vault.

**Option 1: Inline `secrets` input (recommended)** — Use the `secrets` input to pass a JSON string directly. GitHub Actions evaluates `${{ secrets.X }}` expressions in the `with:` block, so no extra step is needed:

```yaml
- uses: yeahwick/supabase-admin@main
  with:
    secrets: '{"STRIPE_SECRET_KEY": "${{ secrets.STRIPE_KEY }}", "RESEND_API_KEY": "${{ secrets.RESEND_KEY }}"}'
    supabase_token: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

**Option 2: `secrets_file`** — Generate a file at runtime and point `secrets_file` at it. Useful when you have many secrets or prefer to build the file dynamically:

```yaml
- name: Generate secrets file
  run: |
    cat > /tmp/secrets.json <<EOF
    {
      "STRIPE_SECRET_KEY": "${{ secrets.STRIPE_KEY }}",
      "RESEND_API_KEY": "${{ secrets.RESEND_KEY }}"
    }
    EOF

- uses: yeahwick/supabase-admin@main
  with:
    secrets_file: /tmp/secrets.json
    supabase_token: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

If both `secrets` and `secrets_file` are provided, `secrets` takes precedence.

## SQL migrations

Point `schema_dir` at a directory of `.sql` files. They are executed in sorted filename order via the `/database/query` endpoint.

```
.supabase/migrations/
  001_create_todos.sql
  002_add_indexes.sql
  003_add_profiles.sql
```

The action tracks applied migrations in a `public._supabase_admin_migrations` table (created automatically). Already-applied migrations are skipped, so you can safely re-run the workflow without side effects.

Each migration file can contain any valid SQL — `CREATE TABLE`, `ALTER TABLE`, RLS policies, indexes, functions, etc.

## Edge functions

Point `functions_dir` at a directory where each subdirectory is an edge function with an `index.ts` entry point:

```
.supabase/functions/
  hello-world/
    index.ts
  process-webhook/
    index.ts
    config.json
```

Functions are created or updated automatically. JWT verification is enabled by default.

### Per-function config

Add an optional `config.json` alongside `index.ts` to configure per-function settings:

```json
{
  "verify_jwt": false
}
```

| Field | Type | Default | Description |
|---|---|---|---|
| `verify_jwt` | boolean | `true` | When `false`, the function can be called without a valid JWT. Useful for webhooks and public endpoints |

## Zero-touch deployment example

With project creation, config management, migrations, and outputs, you can wire up a complete deploy pipeline with no hardcoded credentials:

```yaml
jobs:
  setup-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: yeahwick/supabase-admin@main
        id: supabase
        with:
          project_ref: ${{ vars.SUPABASE_PROJECT_REF }}
          config_dir: .supabase
          schema_dir: .supabase/migrations
          supabase_token: ${{ secrets.SUPABASE_ACCESS_TOKEN }}

      # Inject credentials at build time — nothing hardcoded in source
      - run: |
          sed -i "s|YOUR_PROJECT_REF|${{ steps.supabase.outputs.project_ref }}|g" frontend/app.js
          sed -i "s|your-anon-key-here|${{ steps.supabase.outputs.anon_key }}|g" frontend/app.js

      - uses: actions/upload-pages-artifact@v3
        with:
          path: frontend
      - uses: actions/deploy-pages@v4
```

The only remaining manual steps are:
- **One-time:** Add `SUPABASE_ACCESS_TOKEN` secret and `SUPABASE_PROJECT_REF` variable to the repo
- **One-time:** Enable GitHub Pages with "GitHub Actions" source

## Schemas and Row Level Security

The `db_schema` setting in `postgrest.json` controls which PostgreSQL schemas are exposed through the REST API. The `public` schema is the default and is where most tables live.

**`public` schema + RLS** is the standard Supabase pattern for user data. These work at different layers:

- **`db_schema`** controls which tables are *reachable* via the API
- **RLS policies** control which *rows* a user can access within those tables

Without RLS, any table in an exposed schema is fully readable/writable by anyone with the anon key. Always enable RLS on user-facing tables.

**Private schemas** (e.g. `internal`) are useful for data that should never be accessible via the API — audit logs, elevated-privilege functions, cache tables, or internal config. Since they aren't listed in `db_schema`, PostgREST won't route to them at all, so no RLS is needed as a gatekeeper.

| Schema | Exposed via API | RLS needed | Use for |
|---|---|---|---|
| `public` | Yes | Yes | User-facing tables (todos, profiles, etc.) |
| `internal` / `private` | No | No | Audit logs, admin functions, background jobs |

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

## PR workflows

When using this repo directly (with per-project configs in `projects/`), two PR workflows are included:

### Plan on PR (`pr-plan.yml`)

Automatically comments on PRs with a preview of changes when files under `projects/` are modified. This runs the action in `plan` mode to show what would change without applying anything.

### Apply from PR (`pr-apply.yml`)

Comment `/supa-apply` on a PR to apply changes from the PR branch to your Supabase projects. Only collaborators with **write** access or higher can trigger it.

```
/supa-apply              # Apply all changed projects
/supa-apply staging      # Apply only the project matching environment or name "staging"
```

The workflow discovers which `projects/` directories changed in the PR, reads each `project.json` for the project ref, and applies the config. Status and results are posted as PR comments.

## Using this repo directly

This repo also includes inspection and mutation workflows for centralized management of multiple Supabase projects. See the `.github/workflows/` directory and the `projects/` directory for per-project config examples.
