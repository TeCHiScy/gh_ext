#!/usr/bin/env bash


# chmod +x run-clean.sh
# gh extension install .

set -euo pipefail

VERSION="1.0.0"
REPO=""
STATUS=""
WORKFLOW=""
BEFORE=""
LIMIT=100
DRY_RUN=false
FORCE=false

usage() {
  cat <<EOF
gh run-clean v${VERSION} - Batch delete GitHub Actions workflow runs

USAGE:
  gh run-clean --repo <owner/repo> [flags]

FLAGS:
  -r, --repo <owner/repo>    Target repository (required)
  -s, --status <status>      Filter by status: completed|failure|cancelled|success|skipped
  -w, --workflow <name>      Filter by workflow name or filename
  -b, --before <YYYY-MM-DD>  Delete runs created before this date
  -l, --limit <number>       Max runs to fetch (default: 100, max: 500)
  -d, --dry-run              Preview runs to be deleted without deleting
  -f, --force                Skip confirmation prompt
  -h, --help                 Show this help
  -v, --version              Show version

EXAMPLES:
  gh run-clean -r owner/repo -s failure
  gh run-clean -r owner/repo -w build.yml -b 2026-01-01
  gh run-clean -r owner/repo -s cancelled --dry-run
  gh run-clean -r owner/repo -s completed --force
EOF
}

# ── Parse arguments ──
while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--repo)      REPO="$2"; shift 2 ;;
    -s|--status)    STATUS="$2"; shift 2 ;;
    -w|--workflow)  WORKFLOW="$2"; shift 2 ;;
    -b|--before)    BEFORE="$2"; shift 2 ;;
    -l|--limit)     LIMIT="$2"; shift 2 ;;
    -d|--dry-run)   DRY_RUN=true; shift ;;
    -f|--force)     FORCE=true; shift ;;
    -h|--help)      usage; exit 0 ;;
    -v|--version)   echo "gh-run-clean v${VERSION}"; exit 0 ;;
    *)              echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

if [[ -z "$REPO" ]]; then
  echo "Error: --repo is required"
  usage
  exit 1
fi

# ── Build gh run list command ──
LIST_ARGS=(run list --repo "$REPO" --json databaseId,displayTitle,status,conclusion,createdAt,event,workflowName --limit "$LIMIT")

if [[ -n "$STATUS" ]]; then
  LIST_ARGS+=(--status "$STATUS")
fi

if [[ -n "$WORKFLOW" ]]; then
  LIST_ARGS+=(--workflow "$WORKFLOW")
fi

echo "🔍 Fetching runs from ${REPO}..."
RUNS=$(gh "${LIST_ARGS[@]}")

# ── Filter by date if --before is set ──
if [[ -n "$BEFORE" ]]; then
  RUNS=$(echo "$RUNS" | jq --arg before "${BEFORE}T00:00:00Z" '[.[] | select(.createdAt < $before)]')
fi

COUNT=$(echo "$RUNS" | jq 'length')

if [[ "$COUNT" -eq 0 ]]; then
  echo "✅ No matching runs found. Nothing to delete."
  exit 0
fi

# ── Display summary ──
echo ""
echo "Found ${COUNT} run(s) to delete:"
echo "────────────────────────────────────────────────────────────"
echo "$RUNS" | jq -r '.[] | "  #\(.databaseId)  \(.conclusion // .status)\t\(.createdAt | split("T")[0])  \(.workflowName) - \(.displayTitle)"'
echo "────────────────────────────────────────────────────────────"
echo ""

# ── Dry run ──
if [[ "$DRY_RUN" == true ]]; then
  echo "🏁 Dry run complete. No runs were deleted."
  exit 0
fi

# ── Confirm ──
if [[ "$FORCE" != true ]]; then
  read -r -p "⚠️  Delete these ${COUNT} run(s)? [y/N] " confirm
  if [[ "$confirm" != [yY] ]]; then
    echo "Aborted."
    exit 0
  fi
fi

# ── Delete ──
echo ""
DELETED=0
FAILED=0
IDS=$(echo "$RUNS" | jq -r '.[].databaseId')

for id in $IDS; do
  if gh run delete "$id" --repo "$REPO" 2>/dev/null; then
    echo "  ✓ Deleted run #${id}"
    ((DELETED++))
  else
    echo "  ✗ Failed to delete run #${id}"
    ((FAILED++))
  fi
done

echo ""
echo "🏁 Done. Deleted: ${DELETED}, Failed: ${FAILED}"
