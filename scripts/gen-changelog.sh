#!/usr/bin/env bash
#
# gen-changelog.sh — draft the next CHANGELOG.md section for a FloMorphic release.
#
# FloMorphic is a WRAPPED product: this repo is the release marker (its git tag
# names the image), and the source lives in component repos that are NOT tagged
# per release. So a product changelog can't be produced by diffing this repo —
# it has to aggregate the commits landed in each component since the last
# release. There is no component tag to diff against either, so each release
# records the exact commit it baked from in releases/<version>.json, and the
# NEXT release diffs from those SHAs. That lock file is the offset.
#
# This script:
#   1. reads the newest releases/*.json (the last release's baked SHAs),
#   2. for each component, lists commits from that SHA to the local checkout's
#      current ref, grouped feat / fix / chore,
#   3. prints a Keep-a-Changelog section on stdout for you to paste + edit into
#      CHANGELOG.md, and writes the new offset lock for the version you name.
#
# It only READS git history — it never writes to CHANGELOG.md or tags anything.
#
# Usage:
#   scripts/gen-changelog.sh <new-version>            # e.g. v0.3.2
#   scripts/gen-changelog.sh <new-version> --write-lock   # also write releases/<v>.json
#
# Component checkouts are expected as siblings of this repo; override per repo:
#   API_DIR=../morph-api WAPP_DIR=../wapp scripts/gen-changelog.sh v0.3.2
#
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
releases_dir="$here/releases"

NEW_VERSION="${1:-}"
WRITE_LOCK=0
[ "${2:-}" = "--write-lock" ] && WRITE_LOCK=1

if [ -z "$NEW_VERSION" ]; then
  echo "usage: $0 <new-version> [--write-lock]   (e.g. $0 v0.3.2)" >&2
  exit 2
fi

# Local checkouts to read history from. Names here mirror the on-disk siblings;
# they are only used to READ commits, never as the source of truth for a build.
# The core repos sit beside this one (../); the shared SDKs sit one level up (../../).
API_DIR="${API_DIR:-$here/../flomorphic-api}"
WAPP_DIR="${WAPP_DIR:-$here/../flomorphic-wapp}"
PLUGINS_DIR="${PLUGINS_DIR:-$here/../builtin-plugins}"
PSDK_DIR="${PSDK_DIR:-$here/../../inflow-plugin-sdk}"
NSDK_DIR="${NSDK_DIR:-$here/../../node-plugin-sdk}"

# component key -> "on-disk dir|display name". Every FloMorphic repo whose commits
# should roll up into a product release goes here. A missing checkout is skipped
# with a warning, so this list can name repos not everyone has cloned.
declare -A COMPONENTS=(
  [api]="$API_DIR|morph-api"
  [wapp]="$WAPP_DIR|morph-wapp"
  [plugins]="$PLUGINS_DIR|builtin-plugins"
  [plugin-sdk]="$PSDK_DIR|inflow-plugin-sdk"
  [node-sdk]="$NSDK_DIR|node-plugin-sdk"
)
ORDER=(api wapp plugins plugin-sdk node-sdk)

# --- find the previous release lock (highest version-sorted *.json) -----------
prev_lock=""
if [ -d "$releases_dir" ]; then
  prev_lock="$(ls -1 "$releases_dir"/*.json 2>/dev/null | sort -V | tail -1 || true)"
fi

# Pull a component's baked SHA out of the previous lock. No jq dependency:
# the lock is small, flat JSON — grep the "<key>": { ... "sha": "..." } block.
sha_from_lock() { # $1=lockfile $2=component-key
  [ -f "$1" ] || return 0
  awk -v k="\"$2\"" '
    $0 ~ k"[[:space:]]*:" { inblk=1 }
    inblk && /"sha"/ {
      match($0, /"sha"[[:space:]]*:[[:space:]]*"[^"]+"/)
      s=substr($0, RSTART, RLENGTH); gsub(/.*"sha"[[:space:]]*:[[:space:]]*"/,"",s); gsub(/".*/,"",s)
      print s; exit
    }
    inblk && /}/ { inblk=0 }
  ' "$1"
}

group_commits() { # stdin: "<subject>" lines -> grouped markdown on stdout
  local feats fixes chores line
  feats=""; fixes=""; chores=""
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    case "$line" in
      feat*|impl*|add*|Add*|implement*|central*|present*) feats+="  - ${line}"$'\n' ;;
      fix*|Fix*|bug*|Bug*|survive*|Survive*|harden*)      fixes+="  - ${line}"$'\n' ;;
      *) chores+="  - ${line}"$'\n' ;;
    esac
  done
  [ -n "$feats" ]  && printf '  **Added / Changed**\n%s'   "$feats"
  [ -n "$fixes" ]  && printf '  **Fixed**\n%s'             "$fixes"
  [ -n "$chores" ] && printf '  **Maintenance**\n%s'       "$chores"
}

today="$(date +%Y-%m-%d)"

echo "## $NEW_VERSION — $today"
echo
if [ -n "$prev_lock" ]; then
  echo "_Since $(basename "$prev_lock" .json). Component commits baked into this release:_"
else
  echo "_First tracked release. Component HEADs recorded as the baseline offset._"
fi
echo

# lock body accumulator
lock_components=""
for key in "${ORDER[@]}"; do
  IFS='|' read -r dir name <<< "${COMPONENTS[$key]}"
  if [ ! -d "$dir/.git" ]; then
    echo "> _skipped ${name}: no checkout at ${dir}_" >&2
    continue
  fi
  head_sha="$(git -C "$dir" rev-parse HEAD)"
  short="$(git -C "$dir" rev-parse --short HEAD)"
  from="$(sha_from_lock "$prev_lock" "$key")"

  echo "### ${name}"
  if [ -n "$from" ]; then
    range="${from}..HEAD"
    subjects="$(git -C "$dir" log --no-merges --pretty='%s' "$range" 2>/dev/null || true)"
  else
    # No prior offset for this component: show the most recent commits as a hint,
    # not the whole history. The recorded SHA below becomes the real offset next time.
    range="last 5"
    subjects="$(git -C "$dir" log --no-merges --pretty='%s' -5 2>/dev/null || true)"
  fi
  if [ -z "$subjects" ]; then
    echo "  - _no new commits (${range})_"
  else
    printf '%s\n' "$subjects" | group_commits
  fi
  echo
  lock_components+="    \"$key\": { \"repo\": \"$name\", \"ref\": \"main\", \"sha\": \"$head_sha\", \"short\": \"$short\" },"$'\n'
done

# strip trailing comma from last component entry
lock_components="$(printf '%s' "$lock_components" | sed '$ s/,$//')"

lock_path="$releases_dir/${NEW_VERSION}.json"
lock_json=$(cat <<JSON
{
  "version": "$NEW_VERSION",
  "date": "$today",
  "image": "mehdishokohi/flomorphic:$NEW_VERSION",
  "components": {
$lock_components
  }
}
JSON
)

if [ "$WRITE_LOCK" -eq 1 ]; then
  mkdir -p "$releases_dir"
  printf '%s\n' "$lock_json" > "$lock_path"
  echo "> wrote offset lock: ${lock_path#$here/}" >&2
else
  echo "> offset lock for next release (pass --write-lock to save to ${lock_path#$here/}):" >&2
  printf '%s\n' "$lock_json" >&2
fi
