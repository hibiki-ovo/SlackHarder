#!/bin/bash
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
repository="hibiki-ovo/SlackHarder"
version="${1:-0.1.0}"
if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Usage: bash scripts/publish.sh [major.minor.patch]" >&2
    exit 1
fi
release_tag="v$version"

gh auth status
staging_directory="$(mktemp -d)"
trap 'rm -rf "$staging_directory"' EXIT
checkout="$staging_directory/SlackHarder"
gh repo clone "$repository" "$checkout"
if git -C "$checkout" rev-parse --verify "refs/tags/$release_tag" >/dev/null 2>&1; then
    echo "Tag $release_tag already exists; use a new version." >&2
    exit 1
fi
if ! git -C "$checkout" rev-parse --verify HEAD >/dev/null 2>&1; then
    git -C "$checkout" symbolic-ref HEAD refs/heads/main
fi

# Preserve existing remote files and history; copy only the project's source files.
rsync -a --exclude='.git' --exclude='.build' --exclude='.swiftpm' \
    --exclude='dist' --exclude='.DS_Store' "$project_root/" "$checkout/"
git -C "$checkout" add .
if ! git -C "$checkout" diff --cached --quiet; then
    git -C "$checkout" commit -m "Release SlackHarder $release_tag"
fi
branch="$(git -C "$checkout" symbolic-ref --short HEAD)"
git -C "$checkout" push origin "HEAD:refs/heads/$branch"
git -C "$checkout" tag "$release_tag"
git -C "$checkout" push origin "refs/tags/$release_tag"
echo "Release build: https://github.com/$repository/actions"
