#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
REPO_SKILLS_DIR="${ROOT}/agents/skills"

SKILL_TARGETS=(
  "${CODEX_HOME:-${HOME}/.codex}/skills"
  "${HOME}/.claude/skills"
)

[[ -d "${REPO_SKILLS_DIR}" ]] || exit 0

for target_dir in "${SKILL_TARGETS[@]}"; do
  mkdir -p "${target_dir}"

  # Symlink repo-managed skills into the tool's skill directory.
  while IFS= read -r -d '' skill_dir; do
    skill_path="$(cd "${skill_dir}" && pwd -P)"

    case "${skill_path}" in
      "${ROOT}/"*)
        ln -sfn "${skill_path}" "${target_dir}/$(basename "${skill_path}")"
        ;;
      *)
        printf 'Skipping skill outside repo: %s\n' "${skill_dir}" >&2
        ;;
    esac
  done < <(find "${REPO_SKILLS_DIR}" -mindepth 1 -maxdepth 1 -type d -exec test -f '{}/SKILL.md' ';' -print0 | sort -z)

  # Remove stale symlinks that pointed to a previous repo's agents/skills/,
  # but only when they dangle, so other checked-out repos keep their links.
  while IFS= read -r -d '' existing_link; do
    link_target="$(readlink -f "${existing_link}")" || continue

    case "${link_target}" in
      "${REPO_SKILLS_DIR}/"*)
        ;;
      */agents/skills/*)
        if [[ ! -e "${existing_link}" ]]; then
          rm -f "${existing_link}"
        fi
        ;;
    esac
  done < <(find "${target_dir}" -mindepth 1 -maxdepth 1 -type l -print0 | sort -z)
done
