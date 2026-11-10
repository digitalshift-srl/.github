# digitalshift-srl/.github

Shared CI/CD for every DigitalShift client site. Client repos (made from the Site Kit template) only hold two short stubs, `pr.yml` and `deploy.yml`, which call the reusable workflows here. A fix made here reaches every repo without a sync PR.

Design and sources: `research/cicd-pipeline.md` in the DigitalShift playbook repo.

| Workflow | Called from | Does |
|---|---|---|
| `ci.yml` | `pr.yml` | Conventional-Commit PR title, gitleaks secret scan, build, Site Kit QA (`scripts/qa.mjs`), external link report (lychee), Lighthouse CI |
| `preview.yml` | `pr.yml` | Uploads `dist/` to Cloudflare Workers as a preview version (`pr-<n>-<site>.<sub>.workers.dev`, live site untouched) and comments the URL on the PR. Creates the Worker with a noindex placeholder if it doesn't exist yet |
| `claude-review.yml` | `pr.yml` | Claude reviews against Site Kit rules and posts comments. Advisory unless `blocking: true` |
| `notify-slack.yml` | `pr.yml` | Ready-for-review message: PR, preview, checks, review verdict |
| `deploy.yml` | `deploy.yml` | Approval gate, then production deploy to Cloudflare Workers (static assets) or SiteGround (rsync, port 18765). Slack on failure |

A missing secret skips its step with a notice, so a repo works before Cloudflare, Claude or Slack are connected.

## New client in one command

`scripts/new-client.sh` (macOS) keeps the five shared secrets in the login Keychain and copies them into each repo, because on GitHub Free org secrets don't reach private repos.

```sh
# once per Mac, and again after rotating a token: copy the value, then
scripts/new-client.sh store CLOUDFLARE_API_TOKEN      # checked live with Cloudflare
scripts/new-client.sh store CLOUDFLARE_ACCOUNT_ID
scripts/new-client.sh store CLAUDE_CODE_OAUTH_TOKEN
scripts/new-client.sh store SLACK_WEBHOOK_URL
scripts/new-client.sh store RESEND_API_KEY            # contact forms on Cloudflare
scripts/new-client.sh status

# each new client: private repo from Site Kit, squash-only, labels, secrets, cloned to ~/Developer/<name>
scripts/new-client.sh create casabella

# after rotating a token: push the new value to every client repo
scripts/new-client.sh sync --all

# one site's own secrets (copy the value first)
scripts/new-client.sh set casabella TURNSTILE_SECRET_KEY
scripts/new-client.sh set casabella SG_SSH_KEY         # SiteGround sites: also SG_HOST, SG_USER, SG_PATH
```

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

**6. Cloudflare.** Sites run on **Workers static assets**, not classic Pages. Since mid-2026 Cloudflare points new projects at Workers, and wrangler redirects `pages` commands there. Make one account (company email), then open *Workers & Pages* once in the dashboard: that creates the `<sub>.workers.dev` subdomain previews need. Create an API token scoped to *Account → Workers Scripts → Edit*, for that account only. Add the secrets `CLOUDFLARE_API_TOKEN` and `CLOUDFLARE_ACCOUNT_ID` per repo: on GitHub Free, org secrets don't reach private repos (confirmed in GitHub's docs). `scripts/new-client.sh` does this from the Keychain. No project to create by hand: the first PR preview creates the Worker (named like the repo) with a placeholder page. Each repo carries `wrangler.jsonc`; the workflows write a default one if it's missing. wrangler is pinned with the `wrangler-version` input. Custom domain at launch: add `"routes": [{ "pattern": "www.client.it", "custom_domain": true }]` to `wrangler.jsonc`. The zone must be in the same Cloudflare account. Rollback: `npx wrangler rollback --name <worker>` or Dashboard → Deployments.

**7. Claude review.** Install the Claude GitHub App on the org (`/install-github-app` in Claude Code, or github.com/apps/claude). Run `claude setup-token` and save the token as the secret `CLAUDE_CODE_OAUTH_TOKEN`. An `ANTHROPIC_API_KEY` works instead.

**8. Slack.** Create the channel `#site-reviews` and an incoming webhook, and save it as the secret `SLACK_WEBHOOK_URL`. Optional: the GitHub Slack app for review notifications.

**8b. Contact forms.** Site Kit's form works on both hosts (`hosting` in `src/site.config.ts`, matching `target:` in `deploy.yml`).
- Cloudflare: a Worker (`worker/`) sends through [Resend](https://resend.com) (free: 3,000 emails/month, 100/day, 3 domains). Verify one DigitalShift sending subdomain in Resend (DNS records on `send.digitalshift.info`) and send every client's form from it, with the visitor as Reply-To. Save the API key once: `new-client.sh store RESEND_API_KEY`. CI uploads it to each Worker with every preview and deploy.
- SiteGround: `form.php` uses SiteGround's own mail, from a mailbox on the client's domain.
- Both: one Cloudflare Turnstile widget per site (free, 20 widgets per account, 10 hostnames each). Add the client's domain and `info-digitalshift.workers.dev` (previews), put the site key in `form.turnstileSiteKey`, and the secret with `new-client.sh set <repo> TURNSTILE_SECRET_KEY`. CI uploads it to the Worker, or writes `form-secrets.php` next to `form.php` on SiteGround (never in git or in the release artifact).

**9. Managed settings.** In the claude.ai admin console, set `permissions.disableBypassPermissionsMode: "disable"`.

**10. Test on the pilot.**
- Open 2–3 real PRs and check the preview, the review comments and the Slack message.
- Merge one **without** approval: the gate must block the deploy and post to Slack.
- Approve, push one more commit, then merge: the gate must block (stale approval). Re-approve and re-run: it deploys.
- Tune the Lighthouse thresholds (`lighthouserc.json`) and the review prompt.

**11. Carsboutique (SiteGround).** In its repo, set `target: siteground` and `hosting: 'siteground'`. Make a key with `ssh-keygen -m PEM -t rsa -b 4096 -N ""` and import the public half in Site Tools → Devs → SSH Keys Manager. Add the secrets `SG_SSH_KEY`, `SG_HOST`, `SG_USER` and `SG_PATH` (`new-client.sh set`) (`SG_PORT` defaults to 18765). An rsync deploy isn't atomic: each deploy keeps `dist` as an artifact named `release-<sha>` for 30 days.

## Known limits

- The gate guards against mistakes and agents. It's not a security boundary: anyone with write access can edit a stub on `main`.
- On Free, CODEOWNERS only *requests* Andrea's review; it doesn't enforce it.
- gitleaks is pinned to `8.30.1` (input `gitleaks-version`), and the actions to their major tags. Check versions when tagging a release here.
- Previews on `workers.dev` are public to anyone who has the link (like Pages previews were). Put Cloudflare Access in front of them if a client needs them private.
- Not built yet: the weekly production health check (research §12), the Slack approve bot (v2), axe/Playwright accessibility tests and visual regression.
