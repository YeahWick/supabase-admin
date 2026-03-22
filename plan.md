# Supabase IaC via GitHub Workflows - Implementation Plan

## Secret

| Secret Name | Description |
|---|---|
| `SUPABASE_ACCESS_TOKEN` | Personal Access Token (PAT) from supabase.com/dashboard/account/tokens |

## Architecture

All workflows use `curl` against `https://api.supabase.com/v1/` with the PAT in `Authorization: Bearer ${{ secrets.SUPABASE_ACCESS_TOKEN }}`. No CLI or SDK dependencies — just shell + jq. Workflows are `workflow_dispatch` so they can be triggered manually from the Actions tab (and later called from other workflows).

---

## Phase 1 — Inspection / Read-Only Workflows (MVP)

These workflows **read** state and output it. No mutations.

### 1. `list-projects.yml`
- **Endpoint:** `GET /v1/projects`
- **Output:** Table of projects (name, ref, region, status, created_at)
- **Use:** See all projects at a glance

### 2. `project-health.yml`
- **Input:** `project_ref` (workflow_dispatch input)
- **Endpoints:**
  - `GET /v1/projects/{ref}` — project details
  - `GET /v1/projects/{ref}/health` — service health
- **Output:** Project info + health status for each service

### 3. `inspect-auth-config.yml`
- **Input:** `project_ref`
- **Endpoint:** `GET /v1/projects/{ref}/config/auth`
- **Output:** Full auth config (providers, JWT expiry, MFA, etc.)

### 4. `inspect-postgrest-config.yml`
- **Input:** `project_ref`
- **Endpoint:** `GET /v1/projects/{ref}/postgrest`
- **Output:** PostgREST config (exposed schemas, max rows, role claim key, etc.)

### 5. `inspect-security.yml`
- **Input:** `project_ref`
- **Endpoints:**
  - `GET /v1/projects/{ref}/ssl-enforcement`
  - `GET /v1/projects/{ref}/network-restrictions`
  - `GET /v1/projects/{ref}/advisors/security`
  - `GET /v1/projects/{ref}/advisors/performance`
- **Output:** Security posture summary + advisor recommendations

### 6. `list-secrets.yml`
- **Input:** `project_ref`
- **Endpoint:** `GET /v1/projects/{ref}/secrets`
- **Output:** Secret names (values are masked by the API)

---

## Phase 2 — GitOps / Mutation Workflows

These workflows **apply desired state** from config files or inputs.

### 7. `apply-auth-config.yml`
- **Input:** `project_ref` + reads `config/auth.json` from repo
- **Endpoint:** `PATCH /v1/projects/{ref}/config/auth`
- **Flow:** Reads desired auth config from repo → diffs against current → applies patch
- **Use case:** Enable/disable providers, set JWT expiry, configure MFA, etc.

### 8. `apply-postgrest-config.yml`
- **Input:** `project_ref` + reads `config/postgrest.json` from repo
- **Endpoint:** `PATCH /v1/projects/{ref}/postgrest`
- **Flow:** Apply PostgREST settings (exposed schemas, max rows, etc.)

### 9. `apply-secrets.yml`
- **Input:** `project_ref` + reads `config/secrets.json` from repo
- **Endpoint:** `POST /v1/projects/{ref}/secrets`
- **Flow:** Upsert secrets from config into the project
- **Note:** Secret *values* should come from GitHub secrets, config only defines names/mapping

### 10. `apply-network-restrictions.yml`
- **Input:** `project_ref` + reads `config/network.json` from repo
- **Endpoints:**
  - `PATCH /v1/projects/{ref}/network-restrictions`
  - `POST /v1/projects/{ref}/network-restrictions/apply`
- **Flow:** Set allowed CIDRs for database access

### 11. `apply-ssl-enforcement.yml`
- **Input:** `project_ref` + reads `config/ssl.json` from repo
- **Endpoint:** `PUT /v1/projects/{ref}/ssl-enforcement`
- **Flow:** Enforce or relax SSL requirements

---

## Repo Structure

```
.github/
  workflows/
    list-projects.yml
    project-health.yml
    inspect-auth-config.yml
    inspect-postgrest-config.yml
    inspect-security.yml
    list-secrets.yml
    apply-auth-config.yml
    apply-postgrest-config.yml
    apply-secrets.yml
    apply-network-restrictions.yml
    apply-ssl-enforcement.yml
config/
  auth.json              # desired auth config
  postgrest.json         # desired PostgREST config
  secrets.json           # secret name → GitHub secret mapping
  network.json           # allowed CIDRs
  ssl.json               # SSL enforcement config
```

---

## Implementation Order

1. **Start with Phase 1** (read-only) — ship all 6 inspection workflows
2. **Add `config/` scaffolding** — example JSON files with comments
3. **Ship Phase 2** one workflow at a time, starting with `apply-auth-config.yml`

---

## Notes

- All workflows use `ubuntu-latest` runner, only need `curl` + `jq` (pre-installed)
- Rate limit: 120 req/min per project — not a concern for manual dispatch
- Mutation workflows should always **GET current → diff → PATCH** so the job summary shows what changed
- Sensitive output (API keys, secrets) is masked in logs via `::add-mask::`
