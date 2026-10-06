# Conventions

This file defines conventions specific to this repo's structure and usage.

## Repo Structure

- `src/` is the production application codebase. It can be its own git repository.
- `tmp/` is scratch space. Use it for experiments, spikes, and throwaway work. Do not rely on its contents persisting.
- `agents/` contains agent context documents, skills, and scripts. Keep it organized by purpose.

## Agent Documentation

- Add detail to the appropriate sub-document rather than expanding `AGENTS.md`.
- Update `AGENTS.md` when the repo structure or key workflows change.

## Git

- Work on branches and merge via pull request.
- Conventional commits (`feat:`, `fix:`, `docs:`, `chore:`), one logical change per commit.
- Semantic versioning; keep `src/CHANGELOG.md` current.

## Safety

- Never put secrets or private data in a box, test task or commit: box contents go to Meta's servers.
