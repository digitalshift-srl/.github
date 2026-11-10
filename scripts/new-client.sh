#!/usr/bin/env bash
# DigitalShift client repo setup (macOS). Secrets live in the login Keychain (service "digitalshift-ci"),
# because org secrets don't reach private repos on GitHub Free.
#
#   scripts/new-client.sh store NAME          save the clipboard as secret NAME in the Keychain (checked first)
#   scripts/new-client.sh create REPO [DIR]   new private repo from Site Kit + settings, labels, secrets; clone to DIR
#   scripts/new-client.sh sync REPO|--all     copy the Keychain secrets to one repo, or to every Site Kit repo (after a rotation)
#   scripts/new-client.sh status              which secrets are in the Keychain
#   scripts/new-client.sh set REPO NAME       save the clipboard as a secret of one repo only (e.g. TURNSTILE_SECRET_KEY)
#   scripts/new-client.sh zoho REPO [ACCOUNTS] connect a site to Zoho CRM: Self Client ID, secret and code → tested keys
#
# NAME is one of: CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLAUDE_CODE_OAUTH_TOKEN SLACK_WEBHOOK_URL RESEND_API_KEY
# (shared by all sites). Per-site secrets go through `set`: TURNSTILE_SECRET_KEY, ZOHO_* (CRM), SG_* (SiteGround).
# SiteGround clients also need SG_SSH_KEY, SG_HOST, SG_USER, SG_PATH, plus hosting/target: siteground.
set -euo pipefail

ORG=digitalshift-srl
TEMPLATE=$ORG/site-kit
SERVICE=digitalshift-ci
SECRETS=(CLOUDFLARE_API_TOKEN CLOUDFLARE_ACCOUNT_ID CLAUDE_CODE_OAUTH_TOKEN SLACK_WEBHOOK_URL RESEND_API_KEY)
GIT_NAME=${GIT_NAME:-Andrea}

die() { echo "error: $*" >&2; exit 1; }
info() { echo "• $*"; }
kc_get() { security find-generic-password -s "$SERVICE" -a "$1" -w 2>/dev/null; }

check_value() { # NAME VALUE → exit 0 if plausible
  local name=$1 v=$2
  case "$name" in
    CLOUDFLARE_API_TOKEN)
      [[ "$(curl -s -H "Authorization: Bearer $v" https://api.cloudflare.com/client/v4/user/tokens/verify | jq -r '.result.status // empty')" == active ]] ;;
    CLOUDFLARE_ACCOUNT_ID) [[ "$v" =~ ^[0-9a-f]{32}$ ]] ;;
    CLAUDE_CODE_OAUTH_TOKEN) [[ "$v" == sk-ant-* && ${#v} -gt 40 ]] ;;
    SLACK_WEBHOOK_URL) [[ "$v" == https://hooks.slack.com/services/* ]] ;;
    RESEND_API_KEY) [[ "$v" == re_* && ${#v} -gt 20 ]] ;;
    TURNSTILE_SECRET_KEY) [[ "$v" =~ ^0x[0-9A-Za-z_-]{20,}$ ]] ;;
    ZOHO_CLIENT_ID) [[ "$v" =~ ^1000\.[A-Z0-9]{20,}$ ]] ;;
    ZOHO_CLIENT_SECRET|ZOHO_REFRESH_TOKEN) [[ ${#v} -gt 20 ]] ;;
    SG_SSH_KEY|SG_HOST|SG_USER|SG_PORT|SG_PATH) [[ -n "$v" ]] ;;
    *) return 1 ;;
  esac
}

cmd_store() {
  local name=${1:-}
  [[ " ${SECRETS[*]} " == *" $name "* ]] || die "NAME must be one of: ${SECRETS[*]}"
  local v; v=$(pbpaste | tr -d '[:space:]')
  [[ -n "$v" ]] || die "clipboard is empty"
  check_value "$name" "$v" || die "the clipboard doesn't look like a valid $name (nothing saved)"
  # -U updates an existing item. The value is briefly visible to `ps` on this Mac only.
  security add-generic-password -U -s "$SERVICE" -a "$name" -l "DigitalShift CI: $name" -w "$v"
  info "$name saved in the Keychain."
}

cmd_set() { # REPO NAME: one repo's own secret, straight from the clipboard (not kept in the Keychain)
  local repo=${1:-} name=${2:-} v
  [[ -n "$repo" && -n "$name" ]] || die "set REPO NAME"
  gh repo view "$ORG/$repo" >/dev/null 2>&1 || die "$ORG/$repo not found"
  if [[ "$name" == SG_SSH_KEY ]]; then v=$(pbpaste); else v=$(pbpaste | tr -d '[:space:]'); fi
  [[ -n "$v" ]] || die "clipboard is empty"
  check_value "$name" "$v" || die "the clipboard doesn't look like a valid $name (nothing saved)"
  printf '%s' "$v" | gh secret set "$name" -R "$ORG/$repo"
  info "$repo: $name set"
}

clip_wait() { # PROMPT → the clipboard after Enter, without spaces
  read -r -p "$1, then press Enter " _ </dev/tty
  pbpaste | tr -d '[:space:]'
}

cmd_zoho() { # REPO [ACCOUNTS]: swaps the Self Client code for a refresh token, tests it, saves the three secrets
  local repo=${1:-} acc=${2:-https://accounts.zoho.eu} id sec code r rt
  [[ -n "$repo" ]] || die "zoho REPO [ACCOUNTS URL, default https://accounts.zoho.eu]"
  gh repo view "$ORG/$repo" >/dev/null 2>&1 || die "$ORG/$repo not found"
  echo "In the Zoho API console (api-console.zoho.eu) open your Self Client."
  id=$(clip_wait "Copy the Client ID");         check_value ZOHO_CLIENT_ID "$id" || die "that isn't a Client ID (1000.…)"
  sec=$(clip_wait "Copy the Client Secret");    [[ ${#sec} -gt 20 ]] || die "that isn't a Client Secret"
  echo "Generate Code tab: scope ZohoCRM.modules.leads.CREATE,ZohoCRM.modules.leads.UPDATE, 10 minutes, any description."
  code=$(clip_wait "Click Create, copy the code"); [[ "$code" == 1000.* ]] || die "that isn't a code (1000.…)"
  r=$(curl -s -X POST "$acc/oauth/v2/token" --data-urlencode "grant_type=authorization_code" \
    --data-urlencode "client_id=$id" --data-urlencode "client_secret=$sec" --data-urlencode "code=$code")
  rt=$(jq -r '.refresh_token // empty' <<<"$r")
  [[ -n "$rt" ]] || die "Zoho refused the code: $(jq -r '.error // .' <<<"$r") (codes expire in minutes and work once: generate a new one)"
  r=$(curl -s -X POST "$acc/oauth/v2/token" --data-urlencode "grant_type=refresh_token" \
    --data-urlencode "client_id=$id" --data-urlencode "client_secret=$sec" --data-urlencode "refresh_token=$rt")
  [[ -n "$(jq -r '.access_token // empty' <<<"$r")" ]] || die "the refresh token doesn't work: $(jq -r '.error // .' <<<"$r")"
  info "Zoho accepted the keys ($(jq -r '.api_domain' <<<"$r"))"
  printf '%s' "$id" | gh secret set ZOHO_CLIENT_ID -R "$ORG/$repo"
  printf '%s' "$sec" | gh secret set ZOHO_CLIENT_SECRET -R "$ORG/$repo"
  printf '%s' "$rt" | gh secret set ZOHO_REFRESH_TOKEN -R "$ORG/$repo"
  printf '' | pbcopy
  info "$repo: ZOHO_CLIENT_ID, ZOHO_CLIENT_SECRET, ZOHO_REFRESH_TOKEN set (clipboard cleared)"
}

cmd_status() {
  for n in "${SECRETS[@]}"; do
    if kc_get "$n" >/dev/null; then echo "  ✓ $n"; else echo "  ✗ $n   (scripts/new-client.sh store $n)"; fi
  done
}

sync_repo() { # REPO
  local repo=$1 n
  for n in "${SECRETS[@]}"; do
    if kc_get "$n" >/dev/null; then
      kc_get "$n" | gh secret set "$n" -R "$ORG/$repo" && info "$repo: $n set"
    else
      echo "  ! $repo: $n not in Keychain, skipped" >&2
    fi
  done
}

settings_and_labels() { # REPO
  local repo=$1
  gh api -X PATCH "repos/$ORG/$repo" -F allow_squash_merge=true -F allow_merge_commit=false -F allow_rebase_merge=false \
    -F delete_branch_on_merge=true -f squash_merge_commit_title=PR_TITLE -f squash_merge_commit_message=PR_BODY >/dev/null
  info "$repo: squash merges only, branches deleted after merge"
  gh label create admin-bypass -R "$ORG/$repo" --force --color B60205 \
    --description "Andrea's own PR: deploy without a second approval (people only, never the agent)" >/dev/null
  gh label create dependencies -R "$ORG/$repo" --force --color 0366D6 --description "Renovate updates" >/dev/null
  gh label create needs-review -R "$ORG/$repo" --force --color FBCA04 --description "Major update: review before merging" >/dev/null
  info "$repo: labels admin-bypass, dependencies, needs-review"
}

cmd_create() {
  local repo=${1:-} dir=${2:-$HOME/Developer/${1:-}}
  [[ "$repo" =~ ^[a-z0-9][a-z0-9-]{1,49}$ ]] || die "REPO: lowercase letters, digits and dashes, max 50 (it becomes the Worker name)"
  gh repo view "$ORG/$repo" >/dev/null 2>&1 && die "$ORG/$repo already exists"
  [[ -e "$dir" ]] && die "$dir already exists"
  local missing=0 n; for n in "${SECRETS[@]}"; do kc_get "$n" >/dev/null || missing=1; done
  [[ $missing == 0 ]] || { cmd_status; die "store the missing secrets first"; }

  gh repo create "$ORG/$repo" --private --template "$TEMPLATE" --description "Client site ($repo)" >/dev/null
  info "created $ORG/$repo from $TEMPLATE"
  for _ in $(seq 1 30); do gh api "repos/$ORG/$repo/commits" --jq length >/dev/null 2>&1 && break; sleep 2; done
  settings_and_labels "$repo"
  sync_repo "$repo"
  gh repo clone "$ORG/$repo" "$dir" -- -q
  git -C "$dir" config user.name "$GIT_NAME"
  git -C "$dir" config user.email "$(gh api user --jq '"\(.id)+\(.login)@users.noreply.github.com"')"
  info "cloned to $dir"
  cat <<EOF

Done. Next:
  cd "$dir" && npm install && claude      then /site-brief
  First PR creates the Worker "$repo" and posts a preview link.
  SiteGround client? Set target: siteground in .github/workflows/deploy.yml and add SG_* secrets.
EOF
}

cmd_sync() {
  local target=${1:-}; [[ -n "$target" ]] || die "sync REPO or sync --all"
  if [[ "$target" == --all ]]; then
    gh repo list "$ORG" --limit 200 --json name,isTemplate,templateRepository \
      --jq '.[] | select(.templateRepository.name == "site-kit") | .name' | while read -r r; do sync_repo "$r"; done
  else
    sync_repo "$target"
  fi
}

for c in gh jq security pbpaste; do command -v "$c" >/dev/null || die "needs $c (macOS, gh and jq)"; done
case "${1:-}" in
  store) shift; cmd_store "$@" ;;
  create) shift; cmd_create "$@" ;;
  sync) shift; cmd_sync "$@" ;;
  set) shift; cmd_set "$@" ;;
  zoho) shift; cmd_zoho "$@" ;;
  status) cmd_status ;;
  *) sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
