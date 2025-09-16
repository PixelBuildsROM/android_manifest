#!/usr/bin/env bash
# tools/prepare_a16.sh
# Bump manifests to Android 16, clean remote@revision, set PB project branches, optionally inject lynx repos.
# Usage:
#   tools/prepare_a16.sh [--tag android-16.0.0_r1] [--pb-branch a16]
#                        [--inject-lynx] [--local-manifests]
#                        [--lynx-only] [--strip-remote-revision]
#                        [--dry-run]
#
# Typical:
#   tools/prepare_a16.sh --tag android-16.0.0_r1 --pb-branch a16 --inject-lynx --local-manifests
#
set -euo pipefail

### Defaults
AOSP_TAG="android-16.0.0_r1"
PB_BRANCH="a16"
DO_INJECT_LYNX=0
WRITE_LOCAL_MANIFESTS=0
LYNX_ONLY=0
STRIP_REMOTE_REV=0
DRY_RUN=0

### PixelBuilds remote names to rebranch (edit if yours differ)
PB_REMOTES=(
  "pixelbuilds"
  "pixelbuilds-blobs-gitlab"
  "pixelbuilds-gitea"
  "pixelbuilds-devices"
)

### Lynx projects to inject (device/common/kernel)
LYNX_XML_CONTENT='<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project path="device/google/gs201"           name="device/google/gs201"           remote="aosp" />
  <project path="device/google/lynx"            name="device/google/lynx"            remote="aosp" />
  <project path="kernel/devices/google/lynx"    name="kernel/devices/google/lynx"    remote="aosp" />
</manifest>
'

usage() {
  sed -n '2,40p' "$0"
}

log() { echo ">> $*"; }
warn() { echo "!! $*" >&2; }
die() { echo "!! $*" >&2; exit 1; }

require_in_repo_root() {
  [[ -f "default.xml" || -f "manifest.xml" || -d ".repo" ]] || \
    warn "Not in manifest repo root (no default.xml/manifest.xml/.repo). Proceeding anyway."
}

backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  cp -n "$f" "$f.bak" || true
}

has_xmlstarlet=0
command -v xmlstarlet >/dev/null 2>&1 && has_xmlstarlet=1

### Parse args
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tag)                 AOSP_TAG="$2"; shift 2 ;;
    --pb-branch)           PB_BRANCH="$2"; shift 2 ;;
    --inject-lynx)         DO_INJECT_LYNX=1; shift ;;
    --local-manifests)     WRITE_LOCAL_MANIFESTS=1; shift ;;
    --lynx-only)           LYNX_ONLY=1; shift ;;
    --strip-remote-revision) STRIP_REMOTE_REV=1; shift ;;
    --dry-run)             DRY_RUN=1; shift ;;
    -h|--help)             usage; exit 0 ;;
    *)                     warn "Unknown arg: $1"; usage; exit 2 ;;
  esac
done

require_in_repo_root

manifest_files=()
# Find top-level XMLs (adjust if you store manifests in subfolders)
while IFS= read -r -d '' f; do manifest_files+=("$f"); done < <(find . -maxdepth 1 -type f -name '*.xml' -print0)

if [[ ${#manifest_files[@]} -eq 0 ]]; then
  warn "No top-level *.xml manifests found; searching recursively (may catch vendor XMLs)"
  while IFS= read -r -d '' f; do manifest_files+=("$f"); done < <(find . -type f -name '*.xml' -print0)
fi

log "Found ${#manifest_files[@]} manifest file(s)."

### Step 1: Strip invalid revision on <remote> (optional or auto when bumping)
strip_remote_revision() {
  local f="$1"
  backup_file "$f"
  if (( has_xmlstarlet )); then
    xmlstarlet ed -L -d "//remote/@revision" "$f"
  else
    # sed fallback: remove revision="..." only on <remote ...>
    sed -i -E 's#(<remote[^>]*)([[:space:]]+revision="[^"]*")#\1#g' "$f"
  fi
}

### Step 2: Bump <default ... revision="refs/tags/..."> to the desired AOSP tag
bump_default_tag() {
  local f="$1"
  backup_file "$f"
  if (( has_xmlstarlet )); then
    # Update existing default revision
    if xmlstarlet sel -t -c "//default/@revision" "$f" >/dev/null 2>&1; then
      xmlstarlet ed -L -u "//default/@revision" -v "refs/tags/${AOSP_TAG}" "$f"
    else
      # Insert if missing (appending revision attribute)
      xmlstarlet ed -L -i "//default" -t attr -n "revision" -v "refs/tags/${AOSP_TAG}" "$f"
    fi
  else
    # Replace refs/tags/android-*; if no match, inject revision attribute
    if grep -qE '(<default[^>]*revision="refs/tags/android-[^"]+")' "$f"; then
      sed -i -E "s#(revision=\")refs/tags/android-[^\"]+#\1refs/tags/${AOSP_TAG}#g" "$f"
    else
      # Add revision attribute before closing '>'
      sed -i -E 's#(<default[^>]*)(>)#\1 revision="refs/tags/'"$AOSP_TAG"'"\2#' "$f"
    fi
  fi
}

### Step 3: Force PB projects to PB_BRANCH
set_pb_branch_for_projects() {
  local f="$1" r
  backup_file "$f"
  if (( has_xmlstarlet )); then
    for r in "${PB_REMOTES[@]}"; do
      # If project has a different/missing revision, set it to PB_BRANCH where remote matches
      xmlstarlet ed -L -u "//project[@remote='${r}']/@revision" -v "${PB_BRANCH}" "$f" || true
      # If some project lacks revision entirely, add it
      # (xmlstarlet -u won't add new attributes if missing; so we insert if absent)
      while IFS= read -r path; do
        xmlstarlet ed -L -i "//project[@remote='${r}' and @path='${path}' and not(@revision)]" \
          -t attr -n "revision" -v "${PB_BRANCH}" "$f" || true
      done < <(xmlstarlet sel -t -m "//project[@remote='${r}' and not(@revision)]" -v "@path" -n "$f")
    done
  else
    for r in "${PB_REMOTES[@]}"; do
      # Replace existing revision
      sed -i -E "s#(<project[^>]*remote=\"${r}\"[^>]*)(revision=\"[^\"]*\")#\1revision=\"${PB_BRANCH}\"#g" "$f"
      # Insert revision if missing
      sed -i -E "s#(<project[^>]*remote=\"${r}\"[^>]*)>#\1 revision=\"${PB_BRANCH}\">#g" "$f"
    done
  fi
}

### Step 4: Inject lynx repos (device/google/gs201, device/google/lynx, kernel/devices/google/lynx)
inject_lynx_to_file() {
  local f="$1"
  backup_file "$f"
  # Only inject if they don't already exist
  needs_inject=0
  grep -q 'path="device/google/gs201"'        "$f" || needs_inject=1
  grep -q 'path="device/google/lynx"'         "$f" || needs_inject=1
  grep -q 'path="kernel/devices/google/lynx"' "$f" || needs_inject=1

  if (( needs_inject )); then
    log "Injecting lynx entries into $f"
    # Append just before closing </manifest>
    awk -v block="$LYNX_XML_CONTENT" '
      BEGIN{printed=0}
      /<\/manifest>/ && !printed {print block; printed=1}
      {print}
    ' "$f" > "$f.new"
    mv "$f.new" "$f"
  else
    log "Lynx entries already present in $f"
  fi
}

### Step 5: Write .repo/local_manifests/lynx.xml (optional)
write_local_lynx_manifest() {
  mkdir -p .repo/local_manifests
  local dest=".repo/local_manifests/lynx.xml"
  if [[ -f "$dest" ]]; then
    backup_file "$dest"
  fi
  printf '%s\n' "$LYNX_XML_CONTENT" > "$dest"
  log "Wrote $dest"
}

### Dry-run wrapper
run_or_preview() {
  local fn="$1" file="$2"
  if (( DRY_RUN )); then
    echo "DRY: would $fn on $file"
  else
    "$fn" "$file"
  fi
}

### Execute
log "AOSP tag: ${AOSP_TAG}"
log "PB branch: ${PB_BRANCH}"
log "Inject lynx: $DO_INJECT_LYNX, Write local_manifests: $WRITE_LOCAL_MANIFESTS, Lynx-only: $LYNX_ONLY"
log "Strip remote@revision: $STRIP_REMOTE_REV, Dry-run: $DRY_RUN"
(( has_xmlstarlet )) && log "xmlstarlet: found" || log "xmlstarlet: not found (using sed fallbacks)"

if (( STRIP_REMOTE_REV || LYNX_ONLY == 0 )); then
  for f in "${manifest_files[@]}"; do
    if (( STRIP_REMOTE_REV )); then
      run_or_preview strip_remote_revision "$f"
    fi
    if (( LYNX_ONLY == 0 )); then
      run_or_preview bump_default_tag "$f"
      run_or_preview set_pb_branch_for_projects "$f"
    fi
  done
fi

if (( DO_INJECT_LYNX )); then
  # Prefer injecting into top-level default.xml if present, else first file
  target="default.xml"
  [[ -f "$target" ]] || target="${manifest_files[0]}"
  run_or_preview inject_lynx_to_file "$target"
fi

if (( WRITE_LOCAL_MANIFESTS )); then
  if (( DRY_RUN )); then
    echo "DRY: would write .repo/local_manifests/lynx.xml"
  else
    write_local_lynx_manifest
  fi
fi

log "Done."
log "Review changes with: git status && git diff --stat"
