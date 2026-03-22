# supabase-admin

Infrastructure as Code for managing Supabase projects via GitHub Actions workflows. No CLI or SDK required — just `curl` + `jq` against the [Supabase Management API](https://api.supabase.com/v1).

## How it works

All workflows authenticate with a Supabase Personal Access Token (PAT) stored as a GitHub Actions secret. Workflows are `workflow_dispatch` so they can be triggered manually from the Actions tab.

Per-project configuration lives under `projects/<project-name>/`. Mutation workflows read desired state from those files and apply it to the target project via the API.

## Setup

Add the following secret to your GitHub repository:

| Secret | Description |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | Personal Access Token from [supabase.com/dashboard/account/tokens](https://supabase.com/dashboard/account/tokens) |

## Workflows

### Inspection (read-only)

| Workflow | Input | What it does |
|---|---|---|
| `list-projects.yml` | — | Lists all projects (name, ref, region, status) |
| `project-health.yml` | `project_ref` | Shows project details and service health |
| `inspect-auth-config.yml` | `project_ref` | Dumps full auth config (providers, JWT, MFA) |
| `inspect-postgrest-config.yml` | `project_ref` | Dumps PostgREST config (schemas, max rows) |
| `inspect-security.yml` | `project_ref` | Shows SSL, network restrictions, and security/performance advisor recommendations |
| `list-secrets.yml` | `project_ref` | Lists Edge Function secret names (values are never exposed) |

### GitOps (mutation)

These workflows apply desired state from config files in this repo:

| Workflow | Config file | What it applies |
|---|---|---|
| `apply-auth-config.yml` | `projects/<name>/auth.json` | Auth settings (providers, JWT expiry, MFA, etc.) |
| `apply-postgrest-config.yml` | `projects/<name>/postgrest.json` | PostgREST settings (exposed schemas, max rows, etc.) |
| `apply-network-restrictions.yml` | `projects/<name>/network.json` | Allowed CIDRs for database access |
| `apply-ssl-enforcement.yml` | `projects/<name>/ssl.json` | SSL enforcement |

Each mutation workflow fetches the current state, shows a diff in the job summary, then applies the patch.

## Repo structure

```
.github/
  workflows/          # all workflows
projects/
  <project-name>/
    auth.json
    postgrest.json
    network.json
    ssl.json
    readme.md         # project notes
```

## Example project

`projects/supabase-example/` contains config for a todo app ([YeahWick/supabase-example](https://github.com/YeahWick/supabase-example)) using anonymous auth, PostgREST on the `public` schema, and Row Level Security for per-user isolation.
