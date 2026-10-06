#!/usr/bin/env bash
set -euo pipefail

EXTENSION_ROOTS=(
  "${HOME}/.vscode-server/extensions"
  "${HOME}/.vscode/extensions"
)

pick_latest_extension_dir() {
  local extension_glob="${1:?extension_glob}"
  local -a matches=()
  local root
  local dir

  for root in "${EXTENSION_ROOTS[@]}"; do
    if [[ ! -d "${root}" ]]; then
      continue
    fi
    while IFS= read -r -d '' dir; do
      matches+=("${dir}")
    done < <(find "${root}" -mindepth 1 -maxdepth 1 -type d -name "${extension_glob}" -print0)
  done

  if [[ "${#matches[@]}" -eq 0 ]]; then
    return 1
  fi

  printf '%s\n' "${matches[@]}" | sort -V | tail -n 1
}

pick_codex_bin() {
  local ext_dir
  ext_dir="$(pick_latest_extension_dir 'openai.chatgpt-*')" || return 1

  if [[ -x "${ext_dir}/bin/linux-x86_64/codex" ]]; then
    printf '%s\n' "${ext_dir}/bin/linux-x86_64/codex"
    return 0
  fi
  if [[ -x "${ext_dir}/bin/linux-arm64/codex" ]]; then
    printf '%s\n' "${ext_dir}/bin/linux-arm64/codex"
    return 0
  fi

  find "${ext_dir}" -type f -path '*/bin/linux-*/codex' -print | sort -V | tail -n 1
}

pick_claude_bin() {
  local ext_dir
  ext_dir="$(pick_latest_extension_dir 'anthropic.claude-code-*')" || return 1

  if [[ -x "${ext_dir}/resources/native-binary/claude" ]]; then
    printf '%s\n' "${ext_dir}/resources/native-binary/claude"
    return 0
  fi

  find "${ext_dir}" -type f -name 'claude' -path '*/native-binary/*' -print | sort -V | tail -n 1
}

upsert_link() {
  local binary_name="${1:?binary_name}"
  local target_path="${2:?target_path}"
  local link_path="/usr/local/bin/${binary_name}"

  if [[ ! -x "${target_path}" ]]; then
    echo "Skipping ${binary_name}: target is missing or not executable (${target_path})"
    return 1
  fi

  if ln -sfn "${target_path}" "${link_path}" 2>/dev/null; then
    :
  else
    sudo -n ln -sfn "${target_path}" "${link_path}" 2>/dev/null || {
      echo "Skipping ${binary_name}: no permission"
      return 1
    }
  fi

  echo "Linked ${link_path} -> ${target_path}"
}

codex_bin="$(pick_codex_bin || true)"
claude_bin="$(pick_claude_bin || true)"

if [[ -z "${codex_bin}" ]]; then
  echo "No installed OpenAI ChatGPT extension binary found for codex; leaving link unchanged."
else
  upsert_link "codex" "${codex_bin}" || true
fi

if [[ -z "${claude_bin}" ]]; then
  echo "No installed Claude Code extension binary found for claude; leaving link unchanged."
else
  upsert_link "claude" "${claude_bin}" || true
fi
