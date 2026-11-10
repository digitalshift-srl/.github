# digitalshift-srl/.github

Shared CI/CD for every DigitalShift client site. Client repos (made from the Site Kit template) only hold two short stubs, `pr.yml` and `deploy.yml`, which call the reusable workflows here. A fix made here reaches every repo without a sync PR.

Design and sources: `research/cicd-pipeline.md` in the DigitalShift playbook repo.

| Workflow | Called from | Does |
|---|---|---|
| `ci.yml` | `pr.yml` | Conventional-Commit PR title, gitleaks secret scan, build, Site Kit QA (`scripts/qa.mjs`), external link report (lychee), Lighthouse CI |
| `preview.yml` | `pr.yml` | Uploads `dist/` to Cloudflare Pages as a branch preview and comments the URL on the PR |
| `claude-review.yml` | `pr.yml` | Claude reviews against Site Kit rules and posts comments. Advisory unless `blocking: true` |
| `notify-slack.yml` | `pr.yml` | Ready-for-review message: PR, preview, checks, review verdict |
| `deploy.yml` | `deploy.yml` | Approval gate, then production deploy to Cloudflare Pages or SiteGround (rsync, port 18765). Slack on failure |

A missing secret skips its step with a notice, so a repo works before Cloudflare, Claude or Slack are connected.

## Decisions (2026-11-10)

- **GitHub Free** for now. Nothing on Free blocks a merge into `main` of a private repo, so `deploy.yml` checks approval before deploying (research §11.1). Upgrade to Team when the hard merge rule is needed; the stubs don't change.
- **Org:** `digitalshift-srl`. **Approvers:** `andreagriffini` (the `approvers` input default in `deploy.yml`).
- **Andrea's own PRs: admin bypass.** The gate accepts a PR authored by an approver only when it carries the `admin-bypass` label, which a person adds by hand. Claude Code can't add it (Site Kit guard hook). The label matters because every PR an agent opens from Andrea's laptop is authored by Andrea. Without it, the agent's PRs would bypass review.
  **TODO before the pipeline is fully live:** replace the bypass with a partner's approval (add them to `approvers` and the `reviewers` team), or move to Team with a ruleset.
- **Pilot:** the DigitalShift site first, then CM Carsboutique (SiteGround target).

## Setup runbook

Every step below creates or changes something outside this laptop. Claude does each one only after Andrea confirms it.

**0. Tools.** `brew install gh`, then `gh auth login` (Andrea runs this).

**1. Org.** Create `digitalshift-srl` on the Free plan (github.com → Your organizations → New organization; web only). Create team `reviewers` with Andrea. Later, team `partners`.

**2. This repo.** Create `digitalshift-srl/.github` and push this folder.
- Recommended: **public**. It holds no secrets, and public reusable workflows can be called from private repos with no extra setting.
- If it stays private: Settings → Actions → General → Access → "Accessible from repositories in the 'digitalshift-srl' organization".
- `approvers` default in `deploy.yml`: `andreagriffini` (set 2026-11-10).

**3. Renovate.** Create `digitalshift-srl/renovate-config` (private is fine) from `../renovate-config`, then install the Renovate GitHub App on the org.

**4. Site Kit.** Create `digitalshift-srl/site-kit` (private) from `~/Developer/site-kit`, then tick *Template repository* in Settings.

**5. Pilot repo.** Create `digitalshift-srl/<site>` from the template. In it:
- create the label `admin-bypass`;
- in `.github/workflows/deploy.yml`, set `target` (`cloudflare` for the DigitalShift site, if that's where it will live).

**6. Cloudflare.** Make an account and an API token scoped to *Account → Cloudflare Pages → Edit* only. Create a Pages project named like the repo, with production branch `main` (dashboard → Workers & Pages → Create → Direct upload, or `npx wrangler pages project create <name> --production-branch main`). Add the secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID`, as org secrets or, if the Free plan doesn't share org secrets with private repos, per repo.

**7. Claude review.** Install the Claude GitHub App on the org (`/install-github-app` in Claude Code, or github.com/apps/claude). Run `claude setup-token` and save the token as the secret `CLAUDE_CODE_OAUTH_TOKEN`. An `ANTHROPIC_API_KEY` works instead.

**8. Slack.** Create the channel `#site-reviews` and an incoming webhook, and save it as the secret `SLACK_WEBHOOK_URL`. Optional: the GitHub Slack app for review notifications.

**9. Managed settings.** In the claude.ai admin console, set `permissions.disableBypassPermissionsMode: "disable"`.

**10. Test on the pilot.**
- Open 2–3 real PRs and check the preview, the review comments and the Slack message.
- Merge one **without** approval: the gate must block the deploy and post to Slack.
- Approve, push one more commit, then merge: the gate must block (stale approval). Re-approve and re-run: it deploys.
- Tune the Lighthouse thresholds (`lighthouserc.json`) and the review prompt.

**11. Carsboutique (SiteGround).** In its repo, set `target: siteground`. Make a key with `ssh-keygen -m PEM -t rsa -b 4096 -N ""` and import the public half in Site Tools → Devs → SSH Keys Manager. Add the secrets `SG_SSH_KEY`, `SG_HOST`, `SG_USER` and `SG_PATH` (`SG_PORT` defaults to 18765). An rsync deploy isn't atomic: each deploy keeps `dist` as an artifact named `release-<sha>` for 30 days.

## Known limits

- The gate guards against mistakes and agents. It's not a security boundary: anyone with write access can edit a stub on `main`.
- On Free, CODEOWNERS only *requests* Andrea's review; it doesn't enforce it.
- gitleaks is pinned to `8.24.0` (input `gitleaks-version`), and the actions to their major tags. Check versions when tagging a release here.
- Not built yet: the weekly production health check (research §12), the Slack approve bot (v2), axe/Playwright accessibility tests and visual regression.
