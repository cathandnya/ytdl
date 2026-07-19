#!/usr/bin/env bash
# End-to-end release: bump tag, build & notarize the DMG, and publish a GitHub Release.
#
# Usage:
#   ./scripts/release.sh <version>
#     e.g. ./scripts/release.sh 0.1.1
#
# Prerequisites:
#   - Environment (or edit the defaults below):
#       TEAM_ID           Apple team ID (10 chars, matches Local.xcconfig)
#       NOTARY_PROFILE    Keychain profile name  (default: AC_NOTARY)
#       GH_REPO           GitHub repo owner/name (default: derived from origin)
#   - `xcrun notarytool store-credentials $NOTARY_PROFILE` already run once.
#   - `gh auth status` succeeds.
#   - Working tree is clean and on the branch you want to release from.

set -euo pipefail

if [ $# -ne 1 ]; then
    echo "usage: $0 <version>" >&2
    echo "  e.g. $0 0.1.1" >&2
    exit 2
fi
VERSION="$1"
TAG="v$VERSION"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EXT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$EXT_DIR/.." && pwd)"
cd "$REPO_ROOT"

TEAM_ID="${TEAM_ID:?TEAM_ID must be set (10-char Apple team id)}"
NOTARY_PROFILE="${NOTARY_PROFILE:-AC_NOTARY}"
GH_REPO="${GH_REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"

DMG_PATH="$EXT_DIR/build/YTDLBridge.dmg"
NOTES_TMP=""

cleanup() {
    [ -n "$NOTES_TMP" ] && [ -f "$NOTES_TMP" ] && rm -f "$NOTES_TMP"
}
trap cleanup EXIT

echo "==> Pre-flight checks"

# Working tree must be clean.
if ! git diff --quiet HEAD -- 2>/dev/null || [ -n "$(git status --porcelain)" ]; then
    echo "error: working tree is dirty. Commit or stash first." >&2
    git status --short >&2
    exit 1
fi

# Tag must not already exist.
if git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
    echo "error: tag $TAG already exists locally" >&2
    exit 1
fi
if git ls-remote --tags origin "refs/tags/$TAG" | grep -q "$TAG"; then
    echo "error: tag $TAG already exists on origin" >&2
    exit 1
fi

# gh CLI must be authenticated.
if ! gh auth status > /dev/null 2>&1; then
    echo "error: gh CLI is not authenticated (run: gh auth login)" >&2
    exit 1
fi

# Notary profile must exist.
if ! xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" > /dev/null 2>&1; then
    echo "error: notarytool profile '$NOTARY_PROFILE' is not registered." >&2
    echo "  register with: xcrun notarytool store-credentials $NOTARY_PROFILE ..." >&2
    exit 1
fi

CURRENT_BRANCH="$(git symbolic-ref --short HEAD)"
echo "  team:        $TEAM_ID"
echo "  profile:     $NOTARY_PROFILE"
echo "  gh repo:     $GH_REPO"
echo "  branch:      $CURRENT_BRANCH"
echo "  tag:         $TAG"

echo "==> Ensuring current branch is up to date on origin"
git push origin "$CURRENT_BRANCH"

echo "==> Building notarized DMG"
(
    cd "$EXT_DIR"
    TEAM_ID="$TEAM_ID" NOTARY_PROFILE="$NOTARY_PROFILE" ./scripts/build_release.sh
)

if [ ! -f "$DMG_PATH" ]; then
    echo "error: expected DMG not produced at $DMG_PATH" >&2
    exit 1
fi

echo "==> Tagging $TAG"
git tag -a "$TAG" -m "$TAG"
git push origin "$TAG"

echo "==> Preparing release notes"
NOTES_TMP="$(mktemp)"
cat > "$NOTES_TMP" <<EOF
YTDL Bridge $TAG — a Safari Web Extension that downloads the current YouTube
tab to \`~/Downloads/\` via a local \`ytdl\` CLI.

## Install

1. Open \`YTDLBridge.dmg\` and drag **YTDLBridge** into \`/Applications\`.
2. Launch **YTDLBridge** once so Safari picks up the extension.
3. Enable **YTDL Bridge** in **Safari → Settings → Extensions** and allow it on
   every website.
4. Grant Full Disk Access when prompted (needed to read Safari's cookies).

## Prerequisites on the end-user's Mac

- Python 3.10+
- \`deno\` and \`ffmpeg\` (\`brew install deno ffmpeg\`)
- The \`ytdl\` CLI from this repo installed in a venv (\`pip install -e .\`)

See the [README](https://github.com/$GH_REPO#readme) for full setup.
EOF

echo "==> Creating GitHub Release"
gh release create "$TAG" \
    "$DMG_PATH" \
    --repo "$GH_REPO" \
    --title "$TAG" \
    --notes-file "$NOTES_TMP"

echo
echo "Released: https://github.com/$GH_REPO/releases/tag/$TAG"
