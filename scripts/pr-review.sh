#!/usr/bin/env bash
# pr-review.sh — Interactive Renovate/PR review tool using gum
# Usage: ./scripts/pr-review.sh [--list]
#   --list  Non-interactive: prints PR list as JSON (for scripting/Claude)

set -euo pipefail

REPO="frankjuniorr/homelab-deploys"
LIST_MODE=false

[[ "${1:-}" == "--list" ]] && LIST_MODE=true

# ─── dependency check ────────────────────────────────────────────────────────

for cmd in gh jq glow; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "❌ '$cmd' not found. Please install it first." >&2
    exit 1
  fi
done

if ! $LIST_MODE && ! command -v gum >/dev/null 2>&1; then
  echo "❌ 'gum' not found. Install it or use --list for plain output." >&2
  exit 1
fi

# ─── fetch ───────────────────────────────────────────────────────────────────

fetch_prs() {
  gh pr list \
    --repo "$REPO" \
    --state open \
    --json number,title,author,body,url,labels,createdAt,mergeable,headRefName,baseRefName \
    --limit 50
}

# ─── list mode (non-interactive) ─────────────────────────────────────────────

if $LIST_MODE; then
  prs=$(fetch_prs)
  count=$(echo "$prs" | jq length)
  echo "=== Open PRs ($count) on $REPO ==="
  echo "$prs" | jq -r '.[] | [
    "  #\(.number)",
    "  Title:  \(.title)",
    "  Author: \(.author.login)",
    "  URL:    \(.url)",
    "  Body:\n\(.body // "(no description)")",
    "  ---"
  ] | .[]'
  exit 0
fi

# ─── helpers ─────────────────────────────────────────────────────────────────

header() {
  gum style \
    --border rounded \
    --border-foreground 212 \
    --padding "0 2" \
    --bold \
    --foreground 212 \
    "  PR Review · $REPO  "
}

pr_badge() {
  local author="$1"
  if echo "$author" | grep -qi "renovate"; then
    gum style --foreground 208 --bold "[renovate]"
  else
    gum style --foreground 75 "[$author]"
  fi
}

approve_pr() {
  local number="$1"
  gum spin --title "Approving PR #$number..." -- \
    gh pr review "$number" --approve --repo "$REPO"
  gum style --foreground 76 "✅  PR #$number approved."
}

merge_pr() {
  local number="$1"
  gum spin --title "Merging PR #$number..." -- \
    gh pr merge "$number" --squash --delete-branch --repo "$REPO"
  gum style --foreground 76 "🔀  PR #$number merged."
}

# ─── main interactive loop ────────────────────────────────────────────────────

main() {
  clear
  header
  echo ""

  gum style --foreground 240 "  Fetching PRs from $REPO …"
  local prs
  prs=$(fetch_prs)

  local count
  count=$(echo "$prs" | jq length)

  if [ "$count" -eq 0 ]; then
    gum style --foreground 240 "No open PRs found on $REPO."
    exit 0
  fi

  gum style --foreground 212 "$(gum style --bold "$count") open PR(s):"
  echo ""

  # Build plain-text choices for gum choose (no ANSI codes — gum strips them on return)
  local choices=()
  while IFS=$'\t' read -r number author title; do
    if echo "$author" | grep -qi "renovate"; then
      choices+=("#$number [renovate] $title")
    else
      choices+=("#$number [$author] $title")
    fi
  done < <(echo "$prs" | jq -r '.[] | "\(.number)\t\(.author.login)\t\(.title)"')

  choices+=("── Quit ──")

  while true; do
    echo ""
    local selected
    selected=$(printf '%s\n' "${choices[@]}" | gum choose --header "Select a PR to review:")

    [[ "$selected" == "── Quit ──" ]] && break

    # Extract PR number directly from the selected string
    local pr_number pr_data pr_title pr_url pr_body pr_head pr_base
    pr_number=$(echo "$selected" | grep -oP '(?<=#)\d+')

    pr_data=$(echo "$prs" | jq --argjson num "$pr_number" '.[] | select(.number == $num)')
    pr_title=$(echo "$pr_data" | jq -r '.title')
    pr_url=$(echo "$pr_data"   | jq -r '.url')
    pr_body=$(echo "$pr_data"  | jq -r '.body // "(no description)"')
    pr_head=$(echo "$pr_data"  | jq -r '.headRefName')
    pr_base=$(echo "$pr_data"  | jq -r '.baseRefName')

    clear
    gum style \
      --border rounded --border-foreground 75 \
      --padding "0 1" --width 80 \
      "$(gum style --bold --foreground 212 "#$pr_number · $pr_title")
$(gum style --foreground 240 "$pr_url")
$(gum style --foreground 33 "$pr_head") $(gum style --foreground 240 "→") $(gum style --foreground 76 "$pr_base")"
    echo ""
    echo "$pr_body" | glow -
    echo ""

    local action
    action=$(gum choose \
      --header "Action for #$pr_number:" \
      "✅  Approve" \
      "🔀  Merge (squash)" \
      "✅🔀  Approve & Merge" \
      "📄  View full body" \
      "🌐  Open in browser" \
      "⬅   Back to list")

    case "$action" in
      "✅  Approve")
        gum confirm "Approve PR #$pr_number?" && approve_pr "$pr_number" || true
        ;;
      "🔀  Merge (squash)")
        gum confirm "Merge PR #$pr_number?" && merge_pr "$pr_number" || true
        ;;
      "✅🔀  Approve & Merge")
        gum confirm "Approve and merge PR #$pr_number?" && {
          approve_pr "$pr_number"
          merge_pr   "$pr_number"
        } || true
        ;;
      "📄  View full body")
        echo "$pr_body" | glow --pager -
        ;;
      "🌐  Open in browser")
        xdg-open "$pr_url" &>/dev/null &
        gum style --foreground 240 "Opening $pr_url …"
        ;;
      "⬅   Back to list")
        clear
        header
        ;;
    esac
  done

  echo ""
  gum style --foreground 240 "Done."
}

main
