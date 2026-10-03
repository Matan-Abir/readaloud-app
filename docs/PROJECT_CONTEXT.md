# Project context (for a new AI agent)

ReadAloud is the application half of a **DevOps course final project**: a Flask
backend + Flutter Android client for listening to PDFs and asking an LLM about
them. The assignment is graded on the DevOps tooling around it, which lives in the
sibling `devops` repo.

**Read `devops/docs/HANDOFF.md` first** - it has the full status, remaining work,
constraints and next steps. Keep app changes minimal and in service of the
DevOps goals (containers, health/metrics endpoints, config via env vars).

App facts:
- Backend: `backend/app/` (auth.py, documents.py, llm.py, metrics.py, models.py,
  config.py); migrations in `backend/migrations`; tests in `backend/tests`.
- Config is entirely env vars (see `app/config.py`, `.env.example`).
- Real secrets are in the gitignored `.env`; never commit them.
- Mobile client: `mobile/lib`; API URL via `--dart-define=API_BASE_URL`.
