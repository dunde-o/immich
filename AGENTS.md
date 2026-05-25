# AGENTS.md

## Purpose

This repository is a fork of Immich used for custom Docker image builds. Agents
and maintainers must preserve a clean upstream mirror while keeping operational
changes isolated, reviewable, and rollback-friendly.

## Repository Rules

- Treat `main` as an upstream mirror of `immich-app/immich`.
- Do not commit custom runtime changes directly to `main`.
- Start operational work from an upstream release tag, not from moving `main`.
- Use release branches named `custom/v1.XX.Y`; if upstream uses another major
  version, keep the same shape, for example `custom/v2.0.1`.
- Keep documentation-only work on `docs/<topic>` branches.
- Keep custom diffs small. Avoid unrelated formatting, dependency churn, or
  broad refactors.
- Do not commit secrets, `.env` files, database dumps, media backups, build
  outputs, container layers, or local machine state.
- When implementation, deployment, Docker, script, environment, or operational
  behavior changes, update the relevant documentation in the same work item.
  Start from `README.custom-docker-workflow.md` for this repository's custom
  Docker and deployment workflow.

## Work Verification Rules

- Do not present guesses as confirmed facts. Verify behavior directly from the
  running UI, logs, tests, screenshots, or relevant source code before claiming
  that a change fixed a problem.
- When direct verification is not possible, clearly tell the user what could not
  be checked, why it could not be checked, and what assumption is being used
  before continuing.
- If a UI issue depends on a specific browser state, route, media item, or
  deployment image, confirm that the running environment is using the intended
  commit or image digest before treating the issue as resolved.

## Security And Environment Rules

- Never commit user personal identifiers, personal information, secrets,
  credentials, tokens, PATs, server details, hostnames, IP addresses, external
  service details, or other information that is not internal to this project.
- Do not write real secret values into markdown, scripts, compose files, env
  files, examples, commit messages, issue text, logs, screenshots, or test
  artifacts. Use placeholders such as `<github-id>` and `<token>` instead.
- Token values must live only in the runtime environment or an approved secret
  manager. They must not be stored in repo files, `.env` files, shell history,
  checked-in config, or generated artifacts.
- Use `GHCR_TOKEN` for GitHub Container Registry login and image push/pull
  workflows. This is the preferred token variable for custom Docker image
  publishing.
- Use `GITHUB_PAT` only when a generic GitHub personal access token is required
  for manual GitHub API or git operations. Do not use `GITHUB_TOKEN` for local
  documentation or environment setup because GitHub Actions reserves that name
  for its built-in workflow token.
- Before committing, inspect staged changes for accidental personal data,
  hostnames, IPs, usernames, tokens, credentials, and external service details.
  Remove them before the commit exists.

## Custom Docker Workflow

1. Fetch upstream tags.
2. Create `custom/v1.XX.Y` from the matching upstream tag.
3. Apply the minimum custom patch set.
4. Build fork-owned images with immutable custom tags.
5. Deploy those exact tags to staging.
6. Back up production database, media, deployed compose file, `.env`, and current
   image digests.
7. Promote the same tags to production only after staging passes.
8. Keep previous production tags and backups ready for rollback.

## Docker Tag Rules

- Use fixed tags such as `custom-v1.XX.Y` or `custom-v1.XX.Y-r2`.
- Use explicit acceleration suffixes when needed, such as
  `custom-v1.XX.Y-cuda`.
- Never deploy mutable tags such as `latest`, `main`, or `release`.
- Never move a tag that has been used in staging or production. Publish a new
  `-rN` tag instead.
- Record image digests for every staged and production deployment.

## Deployment Safety Rules

- Staging is mandatory before production.
- Production backup is mandatory before upgrade or rollback.
- Do not rebuild between staging and production; promote the same image tags.
- Do not run an older Immich image against a newer migrated database unless the
  release notes explicitly state that it is safe.
- If rollback crosses a database migration boundary, restore the matching
  database backup before starting the older image set.

## Verification Checklist

Before declaring operational work complete, verify:

- Branch is based on the intended upstream release tag.
- Custom diff is intentional and narrow.
- Docker tags are fixed custom tags.
- Image digests are recorded.
- Staging smoke checks passed: login, upload, timeline, thumbnails, video, and
  machine-learning jobs if enabled.
- Production backup path is documented.
- Rollback command path and previous image tags are documented.

See `README.custom-docker-workflow.md` for the detailed runbook.
