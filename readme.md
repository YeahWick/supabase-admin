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

## Action inputs

| Input | Required | Default | Description |
|---|---|---|---|
| `mode` | No | `apply` | `"apply"` to configure an existing project, `"create"` to provision a new one first, or `"plan"` to preview changes without applying |
| `project_ref` | No* | — | Supabase project reference ID. *Required when mode is `apply`. In `plan` mode, leave empty to plan a new project. |
| `delete` | No | `false` | When `"true"`, plan/apply will destroy the project (`DELETE /v1/projects/<ref>`) and skip all config steps. Used by PR workflows when `delete: true` is set in `project.json`. |
| `organization_id` | No* | — | Supabase organization ID. *Required when mode is `create` |
| `project_name` | No* | — | Name for the new project. *Required when mode is `create` |
| `region` | No | `us-east-1` | Region for the new project (only used with `create`) |
| `db_password` | No* | — | Database password. *Required when mode is `create` |
| `config_dir` | No | `.supabase` | Directory containing config JSON files |
| `schema_dir` | No | — | Directory containing `.sql` migration files |
| `secrets_file` | No | — | Path to JSON file with secrets to push |
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

The file is a simple key-value JSON object with placeholder values. Because GitHub Actions does **not** interpolate `${{ secrets.X }}` expressions inside checked-in files, you must generate the secrets file at runtime in a prior step and point `secrets_file` at the generated path:

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

> **TODO:** A future `secrets` inline input will accept a JSON string directly in the `with:` block (where expressions are evaluated), removing the need for the extra generation step.

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
```

Functions are created or updated automatically. JWT verification is enabled by default.

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

## Using this repo directly

This repo also includes inspection and mutation workflows for centralized management of multiple Supabase projects. See the `.github/workflows/` directory and the `projects/` directory for per-project config examples.

### PR plan/apply lifecycle

When a project lives in `projects/<name>/`, the `pr-plan.yml` and `pr-apply.yml` workflows recognize three lifecycle states from `project.json`:

| State | `project_ref` | `delete` | Plan output |
|---|---|---|---|
| **Create** | `""` (empty) | (omitted) | All configs marked as new; project is provisioned on apply |
| **Update** | set, project exists | (omitted) | Diff of current vs desired |
| **Delete** | set | `true` | Destroy plan; project is deleted on apply |

Example `project.json` for deletion:

```json
{
  "project_ref": "abcdefghijklmnop",
  "project_name": "my-old-app",
  "environment": "staging",
  "delete": true
}
```
