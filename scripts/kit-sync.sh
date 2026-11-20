#!/usr/bin/env bash
# Copy the kit-owned parts of Site Kit into existing client repos, so older sites get the latest skills and tools
# (/site-new and the step skills, scripts/start/ with the old-URL and Google listing tools, npm run live-check).
# Not copied, because each site's version has diverged: scripts/qa.mjs, Base.astro and the business block in
# site.config.ts. Port those by hand at launch (Site Kit GUIDE §6).
# Site files (pages, styles, content, site/*.md, workflows) are never touched.
#
#   scripts/kit-sync.sh REPO [REPO…]   e.g. lexlab studio-legale-pellegrini   (folders in ~/Developer)
#   scripts/kit-sync.sh --all          every Site Kit repo cloned in ~/Developer
#
# For each repo: a worktree at ~/Developer/wt/<repo>-kit-sync on branch chore/kit-sync, from origin's default
# branch (your own checkout and its uncommitted work stay as they are), then the copy. Review, commit and open a PR
# from the worktree. Source: ~/Developer/site-kit as it is on disk (pull it first).
set -euo pipefail

KIT="${KIT:-$HOME/Developer/site-kit}"
DEV="$HOME/Developer"
WT="$DEV/wt"
SKILLS=(site-new site-brief site-design site-build site-qa)

[[ -f "$KIT/.claude/skills/site-new/SKILL.md" ]] || { echo "No /site-new in $KIT: pull site-kit first." >&2; exit 1; }
repos=("$@")
if [[ "${1:-}" == --all ]]; then
  repos=()
  for d in "$DEV"/*/; do
    r=$(basename "$d")
    [[ "$r" == site-kit || "$r" == wt ]] && continue
    [[ -f "$d/.claude/skills/site-brief/SKILL.md" && -f "$d/astro.config.mjs" ]] && repos+=("$r")
  done
fi
(( ${#repos[@]} )) || { sed -n '2,10p' "$0"; exit 2; }

for r in "${repos[@]}"; do
  src="$DEV/$r"
  [[ -d "$src/.git" ]] || { echo "$r: not in $DEV, skipped"; continue; }
  echo "== $r"
  git -C "$src" fetch -q origin
  base=$(git -C "$src" symbolic-ref -q --short refs/remotes/origin/HEAD || echo origin/main)
  dst="$WT/$r-kit-sync"
  if [[ ! -d "$dst" ]]; then
    git -C "$src" worktree add -q -B chore/kit-sync "$dst" "$base"
  fi

  # 1. Skills and start scripts: the kit's version wins. Repos older than the kit's a11y/setup tools
  #    (no scripts/a11y.mjs) keep their own step skills, which match the commands they have; they only get /site-new.
  skills=("${SKILLS[@]}"); [[ -f "$dst/scripts/a11y.mjs" ]] || skills=(site-new)
  for s in "${skills[@]}"; do
    rm -rf "$dst/.claude/skills/$s"; mkdir -p "$dst/.claude/skills"
    cp -R "$KIT/.claude/skills/$s" "$dst/.claude/skills/$s"
  done
  rm -rf "$dst/scripts/start"; mkdir -p "$dst/scripts"; cp -R "$KIT/scripts/start" "$dst/scripts/start"
  # The live check only reads site.url and public/_redirects, so it works on any site.
  [[ -f "$KIT/scripts/live-check.mjs" ]] && cp "$KIT/scripts/live-check.mjs" "$dst/scripts/live-check.mjs"
  find "$dst/scripts/start" -name __pycache__ -prune -exec rm -rf {} +

  # 2. package.json scripts + playwright-core, settings allow-list: add what's missing, keep the site's own values.
  node - "$dst" "$KIT" <<'EOF'
const fs = require('fs'), [dst, kit] = process.argv.slice(2);
const read = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const pkg = read(`${dst}/package.json`), kpkg = read(`${kit}/package.json`);
pkg.scripts ??= {};
pkg.scripts['live-shots'] ??= kpkg.scripts['live-shots'];
if (kpkg.scripts['live-check']) pkg.scripts['live-check'] ??= kpkg.scripts['live-check'];
pkg.devDependencies ??= {};
pkg.devDependencies['playwright-core'] ??= kpkg.devDependencies['playwright-core'];
fs.writeFileSync(`${dst}/package.json`, JSON.stringify(pkg, null, 2) + '\n');
const sp = `${dst}/.claude/settings.json`;
if (fs.existsSync(sp)) {
  const s = read(sp), k = read(`${kit}/.claude/settings.json`);
  s.permissions ??= {}; s.permissions.allow ??= [];
  for (const rule of k.permissions.allow.filter((r) => /live-shots|scripts\/start/.test(r)))
    if (!s.permissions.allow.includes(rule)) s.permissions.allow.push(rule);
  fs.writeFileSync(sp, JSON.stringify(s, null, 2) + '\n');
}
EOF
  (cd "$dst" && npm install --package-lock-only --ignore-scripts --silent >/dev/null 2>&1) || echo "  package-lock not updated: run npm install in $dst"

  # 3. CLAUDE.md: the step list line points to /site-new.
  python3 -I - "$dst/CLAUDE.md" "$KIT/CLAUDE.md" <<'EOF'
import re, sys
dst, kit = sys.argv[1], sys.argv[2]
new = next(l for l in open(kit) if 'Start every new site with `/site-new`' in l)
t = open(dst).read()
t2 = re.sub(r'^.*(Work through the steps in order:|Start every new site with `/site-new`).*\n', new, t, count=1, flags=re.M)
if t2 == t: print('  CLAUDE.md: step line not found, add by hand:', new.strip()[:80])
open(dst, 'w').write(t2)
EOF
  git -C "$dst" add -A
  git -C "$dst" status -s | sed 's/^/  /'
done
echo
echo "Review each worktree in $WT, then commit (chore(kit): sync skills, start scripts and live check from Site Kit) and open a PR."
