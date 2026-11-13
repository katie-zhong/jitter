#!/usr/bin/env bash
# PostToolUse hook (Edit|Write): auto-fix and format the file Claude just changed.
#   *.ts / *.tsx / *.js / *.mjs -> eslint --fix, then prettier --write (from the nearest package with node_modules)
#   *.py                       -> ruff check --fix, then ruff format (from the nearest pyproject.toml, via uv)
# Never blocks: a missing toolchain (e.g. before `pnpm install`) is a silent no-op.
set -u

file="$(jq -r '.tool_response.filePath // .tool_input.file_path // empty')"
[ -n "$file" ] && [ -f "$file" ] || exit 0

# Walk up from the file to find the nearest directory containing $1.
nearest() {
  local dir
  dir="$(cd "$(dirname "$file")" && pwd)"
  while [ "$dir" != "/" ]; do
    [ -e "$dir/$1" ] && { printf '%s' "$dir"; return 0; }
    dir="$(dirname "$dir")"
  done
  return 1
}

case "$file" in
  *.ts|*.tsx|*.js|*.mjs|*.cjs)
    command -v pnpm >/dev/null || exit 0
    pkg="$(nearest node_modules/.bin/eslint)" || exit 0
    (cd "$pkg" && pnpm exec eslint --fix "$file") >&2 || true
    if [ -x "$pkg/node_modules/.bin/prettier" ]; then
      (cd "$pkg" && pnpm exec prettier --write --log-level warn "$file") >&2 || true
    fi
    ;;
  *.py)
    command -v uv >/dev/null || exit 0
    proj="$(nearest pyproject.toml)" || exit 0
    (cd "$proj" && uv run ruff check --fix "$file" && uv run ruff format "$file") >&2 || true
    ;;
esac
exit 0
