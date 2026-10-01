#!/usr/bin/env bash
# Push the workspace to GitHub without ever storing the token in the repository.
#
#   GH_TOKEN=ghp_xxx tools/push.sh                       # push to origin/main
#   GH_TOKEN=ghp_xxx tools/push.sh origin main           # explicit remote + branch
#
# The token is only used to build the push URL for this single command; it is
# written to .git/config (which .gitignore-adjacent tooling never commits) and
# never to a tracked file. Use a fine-grained token with "Contents: read/write"
# on the one repository, and revoke it when you are done.
set -euo pipefail

REMOTE="${1:-origin}"
BRANCH="${2:-main}"
shift $(( $# > 2 ? 2 : $# ))   # anything left over is passed straight to git push
REPO="${REPO:-daviddan-241/SENTINEL}"

if [ -z "${GH_TOKEN:-}" ]; then
  echo "GH_TOKEN is not set. Create a token with 'Contents: read and write' and run:"
  echo "  GH_TOKEN=ghp_xxx $0 $REMOTE $BRANCH"
  exit 1
fi

cd "$(dirname "$0")/.."

git remote get-url "$REMOTE" >/dev/null 2>&1 || git remote add "$REMOTE" "https://github.com/$REPO.git"
git remote set-url "$REMOTE" "https://x-access-token:${GH_TOKEN}@github.com/${REPO}.git"

echo "→ pushing $(git rev-parse --short HEAD) ($(git branch --show-current)) to $REPO:$BRANCH"
git push "$REMOTE" "HEAD:$BRANCH" "$@"

# leave the working copy with a clean, token-free remote again
git remote set-url "$REMOTE" "https://github.com/$REPO.git"
echo "✓ pushed — remote URL reset to https://github.com/$REPO.git"
