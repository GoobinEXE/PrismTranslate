#!/usr/bin/env bash
#
# publish-community.sh — Exporta árvore Community para GoobinEXE/PrismTranslate (público).
#
# Nunca faça `git push community main` directamente a partir do branch privado —
# use sempre este script para filtrar ficheiros de mantenedor e Pro.
#
# USO:
#   ./scripts/publish-community.sh
#   ./scripts/publish-community.sh --tag v1.0.4
#   ./scripts/publish-community.sh --dry-run
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXCLUDES_FILE="$REPO_ROOT/scripts/community-excludes.txt"
COMMUNITY_GITIGNORE="$REPO_ROOT/scripts/community-gitignore"
STAGING_DIR="$REPO_ROOT/.community-publish/PrismTranslate"
COMMUNITY_REMOTE="${COMMUNITY_REMOTE:-community}"
DRY_RUN=0
TAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --tag) TAG="${2:?--tag requires a value}"; shift 2 ;;
    -h|--help)
      sed -n '2,12p' "$0"
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -t 1 ]]; then
  GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; RED=$'\033[0;31m'; RESET=$'\033[0m'
else
  GREEN=""; YELLOW=""; RED=""; RESET=""
fi

info()  { echo "${GREEN}==>${RESET} $*"; }
warn()  { echo "${YELLOW}aviso:${RESET} $*"; }
die()   { echo "${RED}erro:${RESET} $*" >&2; exit 1; }

[[ -f "$EXCLUDES_FILE" ]] || die "Missing $EXCLUDES_FILE"
[[ -f "$COMMUNITY_GITIGNORE" ]] || die "Missing $COMMUNITY_GITIGNORE"

if ! git -C "$REPO_ROOT" remote get-url "$COMMUNITY_REMOTE" &>/dev/null; then
  die "Remote '$COMMUNITY_REMOTE' not found. Run: git remote add community https://github.com/GoobinEXE/PrismTranslate.git"
fi

COMMUNITY_URL="$(git -C "$REPO_ROOT" remote get-url "$COMMUNITY_REMOTE")"

# Block accidental publish with uncommitted Prism/source changes (allow .community-publish).
if ! git -C "$REPO_ROOT" diff-index --quiet HEAD --; then
  die "Working tree has uncommitted changes. Commit or stash before publishing."
fi

mkdir -p "$(dirname "$STAGING_DIR")"

if [[ ! -d "$STAGING_DIR/.git" ]]; then
  info "Cloning community repo into $STAGING_DIR"
  git clone "$COMMUNITY_URL" "$STAGING_DIR"
else
  info "Updating community clone"
  git -C "$STAGING_DIR" fetch "$COMMUNITY_REMOTE"
  git -C "$STAGING_DIR" checkout main
  git -C "$STAGING_DIR" pull "$COMMUNITY_REMOTE" main
fi

info "Syncing filtered tree to community staging"
RSYNC_EXCLUDES=(
  --exclude '.git'
  --exclude '.community-publish'
  --exclude 'build/'
  --exclude 'DerivedData/'
  --exclude 'Secrets.xcconfig'
  --exclude '.DS_Store'
)

while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$line" ]] && continue
  RSYNC_EXCLUDES+=(--exclude "$line")
done < "$EXCLUDES_FILE"

if [[ "$DRY_RUN" -eq 1 ]]; then
  rsync -a --delete --dry-run "${RSYNC_EXCLUDES[@]}" "$REPO_ROOT/" "$STAGING_DIR/"
  info "Dry run complete — no changes written."
  exit 0
fi

rsync -a --delete "${RSYNC_EXCLUDES[@]}" "$REPO_ROOT/" "$STAGING_DIR/"
cp "$COMMUNITY_GITIGNORE" "$STAGING_DIR/.gitignore"

pushd "$STAGING_DIR" >/dev/null

# Remove excluded paths that may linger from older community commits.
while IFS= read -r line || [[ -n "$line" ]]; do
  line="${line%%#*}"
  line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  [[ -z "$line" ]] && continue
  rm -rf "$line" 2>/dev/null || true
done < "$EXCLUDES_FILE"

git add -A
if git diff --cached --quiet; then
  info "Community repo already up to date — nothing to commit."
else
  COMMIT_MSG="chore: sync from Prisma-Tradutor (private)"
  git commit -m "$COMMIT_MSG"
  info "Pushing to $COMMUNITY_REMOTE main"
  git push "$COMMUNITY_REMOTE" main
fi

if [[ -n "$TAG" ]]; then
  if git rev-parse "$TAG" >/dev/null 2>&1; then
    warn "Tag $TAG already exists locally; pushing to remote."
  else
    git tag -a "$TAG" -m "Prism Translate Community $TAG"
  fi
  git push "$COMMUNITY_REMOTE" "$TAG"
  info "Tagged and pushed $TAG"
fi

popd >/dev/null
info "Community publish complete."
