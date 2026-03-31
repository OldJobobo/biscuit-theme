#!/usr/bin/env bash
set -euo pipefail

BUMP_KIND="${1:-patch}"
if [[ $# -gt 0 ]]; then
  shift
fi

if [[ ! "$BUMP_KIND" =~ ^(patch|minor|major)$ ]]; then
  echo "Invalid bump kind: '$BUMP_KIND' (expected: patch|minor|major)" >&2
  exit 1
fi

read_pkg_field() {
  local field="$1"
  node -e "const p=require('./package.json'); console.log(p['$field'] || '')"
}

CURRENT_VERSION="$(read_pkg_field version)"
PUBLISHER="$(read_pkg_field publisher)"
NAME="$(read_pkg_field name)"
EXT_ID="${PUBLISHER}.${NAME}"

if [[ -z "$CURRENT_VERSION" || -z "$PUBLISHER" || -z "$NAME" ]]; then
  echo "Missing required package.json fields (version/publisher/name)." >&2
  exit 1
fi

echo "Checking Marketplace version for ${EXT_ID}..."

SHOW_OUTPUT="$(
  vsce show "${EXT_ID}" --json "$@" 2>&1 || true
)"

if [[ -z "$SHOW_OUTPUT" ]]; then
  echo "Could not read Marketplace version. Aborting to avoid an unintended publish." >&2
  echo "Run manually: vsce publish ${CURRENT_VERSION}  OR  vsce publish ${BUMP_KIND}" >&2
  exit 1
fi

if [[ "$SHOW_OUTPUT" == *" ERROR "* ]] || [[ "$SHOW_OUTPUT" == *"getaddrinfo"* ]]; then
  echo "Could not reach the VS Code Marketplace while checking ${EXT_ID}." >&2
  echo "$SHOW_OUTPUT" >&2
  echo "Run manually once connectivity is working: vsce publish ${CURRENT_VERSION} --no-yarn --no-dependencies" >&2
  exit 1
fi

PUBLISHED_VERSION="$(
  printf '%s' "$SHOW_OUTPUT" | node -e '
    const fs = require("fs");
    const input = fs.readFileSync(0, "utf8").trim();
    if (!input || input === "undefined") {
      process.exit(0);
    }
    let data;
    try {
      data = JSON.parse(input);
    } catch {
      process.exit(0);
    }
    const semver = (v) => typeof v === "string" && /^\d+\.\d+\.\d+(-[\w.-]+)?$/.test(v);
    const pick = (obj) => {
      if (!obj || typeof obj !== "object") return "";
      if (semver(obj.version)) return obj.version;
      if (Array.isArray(obj.versions) && obj.versions.length > 0) {
        const first = obj.versions[0];
        if (typeof first === "string" && semver(first)) return first;
        if (first && semver(first.version)) return first.version;
      }
      if (semver(obj.latestVersion)) return obj.latestVersion;
      if (semver(obj.publishedVersion)) return obj.publishedVersion;
      return "";
    };
    process.stdout.write(pick(data));
  '
)"

if [[ -z "$PUBLISHED_VERSION" ]]; then
  echo "Could not parse published version from Marketplace response for ${EXT_ID}. Aborting." >&2
  echo "Raw response:" >&2
  printf '%s\n' "$SHOW_OUTPUT" >&2
  echo "Run manually if needed: vsce publish ${CURRENT_VERSION} --no-yarn --no-dependencies" >&2
  exit 1
fi

echo "Local version:       ${CURRENT_VERSION}"
echo "Marketplace version: ${PUBLISHED_VERSION}"

VSCE_FLAGS=(--no-yarn --no-dependencies)

if [[ "$CURRENT_VERSION" != "$PUBLISHED_VERSION" ]]; then
  echo "Detected manual/local version change. Publishing current version as-is..."
  exec vsce publish "${CURRENT_VERSION}" "${VSCE_FLAGS[@]}" "$@"
fi

echo "No version change detected. Publishing with automatic ${BUMP_KIND} bump..."
exec vsce publish "${BUMP_KIND}" "${VSCE_FLAGS[@]}" "$@"
