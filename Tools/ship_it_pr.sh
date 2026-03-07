#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  Tools/ship_it_pr.sh --title "PR title" [--body "text"] [--body-file path] [--commit-message "text"] [--base main]

Behavior:
  - Creates a codex/* branch if run from the base branch.
  - Requires a clean working tree except for already-staged changes.
  - Commits staged changes if present.
  - Pushes the branch, creates a GitHub PR, merges it with a merge commit, then fast-forwards local main.
EOF
}

die() {
  echo "error: $*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

slugify() {
  local value
  value="$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-+/-/g')"
  value="${value:0:40}"
  if [[ -z "$value" ]]; then
    value="ship-it"
  fi
  printf '%s' "$value"
}

next_branch_name() {
  local title="$1"
  local base="codex/$(slugify "$title")"
  local candidate="$base"
  local suffix=2

  while git show-ref --verify --quiet "refs/heads/$candidate" || git ls-remote --exit-code --heads origin "$candidate" >/dev/null 2>&1; do
    candidate="${base}-${suffix}"
    suffix=$((suffix + 1))
  done

  printf '%s' "$candidate"
}

title=""
body=""
body_file=""
commit_message=""
base_branch="main"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title)
      [[ $# -ge 2 ]] || die "--title requires a value"
      title="$2"
      shift 2
      ;;
    --body)
      [[ $# -ge 2 ]] || die "--body requires a value"
      body="$2"
      shift 2
      ;;
    --body-file)
      [[ $# -ge 2 ]] || die "--body-file requires a value"
      body_file="$2"
      shift 2
      ;;
    --commit-message)
      [[ $# -ge 2 ]] || die "--commit-message requires a value"
      commit_message="$2"
      shift 2
      ;;
    --base)
      [[ $# -ge 2 ]] || die "--base requires a value"
      base_branch="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

[[ -n "$title" ]] || die "missing required --title"
[[ -z "$body" || -z "$body_file" ]] || die "use either --body or --body-file, not both"

require_command git
require_command gh

git rev-parse --is-inside-work-tree >/dev/null 2>&1 || die "must be run inside a git repository"

current_branch="$(git branch --show-current)"
[[ -n "$current_branch" ]] || die "detached HEAD is not supported"

git fetch origin "$base_branch" --quiet

if ! git diff --quiet; then
  die "worktree has unstaged changes; stage only the files for this ship request first"
fi

if [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  die "worktree has untracked files; stage only the files for this ship request first"
fi

if [[ "$current_branch" == "$base_branch" ]]; then
  target_branch="$(next_branch_name "$title")"
  git checkout -b "$target_branch"
  current_branch="$target_branch"
fi

if ! git diff --cached --quiet; then
  if [[ -z "$commit_message" ]]; then
    commit_message="$title"
  fi
  git commit -m "$commit_message"
fi

ahead_count="$(git rev-list --count "origin/$base_branch..HEAD")"
[[ "$ahead_count" -gt 0 ]] || die "no commits to ship relative to origin/$base_branch"

git push -u origin "$current_branch"

existing_pr_url="$(gh pr list --head "$current_branch" --base "$base_branch" --state all --json url --jq '.[0].url' 2>/dev/null || true)"
existing_pr_state="$(gh pr list --head "$current_branch" --base "$base_branch" --state all --json state --jq '.[0].state' 2>/dev/null || true)"

if [[ -n "$existing_pr_url" ]]; then
  pr_url="$existing_pr_url"
  if [[ "$existing_pr_state" != "OPEN" ]]; then
    die "existing PR for $current_branch is not open: $pr_url"
  fi
else
  pr_create_args=(--base "$base_branch" --head "$current_branch" --title "$title")
  if [[ -n "$body_file" ]]; then
    [[ -f "$body_file" ]] || die "body file not found: $body_file"
    pr_create_args+=(--body-file "$body_file")
  elif [[ -n "$body" ]]; then
    pr_create_args+=(--body "$body")
  else
    pr_create_args+=(--fill)
  fi

  pr_url="$(gh pr create "${pr_create_args[@]}")"
fi

gh pr merge "$current_branch" --merge --delete-branch

git checkout "$base_branch"
git pull --ff-only origin "$base_branch"

if git show-ref --verify --quiet "refs/heads/$current_branch"; then
  git branch -d "$current_branch"
fi

echo "Merged PR: $pr_url"
