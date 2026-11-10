# Break-it log — Lab 1

What I broke on purpose, how I found out, and what I'd say about it in an interview.
Fill each entry **before** looking anything up: write your guess first, then confirm it.


**Entry format:**

- **Symptom:** what I saw (copy the exact error line)
- **My guess:** what I thought was wrong, before checking
- **Confirmed with:** the command or log line that proved it
- **Cause:** the real reason
- **Fix:** what I changed
- **Interview line:** one sentence I could say out loud

---

## Measurements

| What | Before | After | Notes |
| --- | --- | --- | --- |
| Stage 3: CI run, NuGet cache miss vs hit | | | |
| Stage 4: Python rebuild, slow order vs fast order | | | |
| Stage 5: image sizes (sdk / aspnet / mine) | | | |
| Stage 7: image job, cold vs warm layer cache | | | |

---

## Stage 0 — Setup

### 0.1 Docker daemon stopped

- **Symptom:**
Got the following message when I tried to do "docker ps": Cannot connect to the Docker daemon...
- **My guess:**
The docker service was stopped
- **Confirmed with:**
sudo systemctl is-active docker
- **Cause:**
I used sudo systemctl stop docker... to stop the service and see what would happen
- **Fix:**
sudo systemctl start docker
- **Interview line:**
If docker seems to be unresponsive, it's a good idea to check if the service is running by
checking its status, pull its logs and start the service again

## Stage 1 — Git flow

### 1.1 Direct push to `main`

- **Symptom:**
Can't push to main, or merge from a PR
- **My guess:**
I deliverately changed a value from a .cs test file so the condition couldn't be met and the test would fail
- **Confirmed with:**
Running 'dotnet test', which confirmed that one of the tests failed, also, the workflow dedicated to this task (cs.yml) reported the failure, and finally, the merge attempt triggered a message saying the branch policy prohibited the merge
- **Cause:**
Branch protection blocking merge attempts if a step in the designated workflow failed
- **Fix:**
Restore the correct value in the test .cs file and re-attempt the PR
- **Interview line:**
Branch protection + automated checks and rules that prohibit autmatic and unchecked merges to main (prod) is what makes the CI part of GitOps work

### 1.2 Why `--force-with-lease` and not `--force`
`--force` overwrites the remote branch no matter what; `--force-with-lease` only overwrites it if it's still where I last fetched it, so I can't silently delete a teammate's commits.

## Stage 2 — First CI workflow

### 2.1 A failing test on a pull request

- **Symptom:**
PR `breakit/stage2` showed `build` failed, but `gh pr merge --squash --delete-branch` still merged it, and the next run on `main` went red too.
- **My guess:**
The merge should have been blocked; something in branch protection was off.
- **Confirmed with:**
`gh run list --limit 5` (red PR run, then red `main` run), the ruleset JSON (`gh api repos/{owner}/{repo}/rulesets/<id>`), and the test log: `<Assert.Equal() Failure line>`.
- **Cause:**
The ruleset required a pull request but had no `required_status_checks` rule, so a red PR was still mergeable.
- **Fix:**
Added "Require status checks to pass" with the `build` check (GitHub Actions), fixed the test through a new PR, then repeated the drill; a red PR is now blocked.
- **Interview line:**
"Requiring a PR isn't enough; you have to require the CI check, and then prove it by trying to merge a red PR."

### 2.2 Workflow without `actions/checkout`

- **Symptom:**
The run failed at the restore step within seconds
- **My guess:**
The runner had no code to build.
- **Confirmed with:**
Step log: `<e.g. MSB1003: ... does not contain a project or solution file>`
- **Cause:**
Every job starts on a fresh, empty VM; without `actions/checkout` the repo is never downloaded.
- **Fix:**
Restored `- uses: actions/checkout@v6` as the first step.
- **Interview line:**
"Runners are ephemeral and start empty: checkout is always step one, and each job needs its own."

## Stage 3 — Triggers, jobs, outputs, cache

### 3.1 README-only PR never gets its required check

- **Symptom:**
After adding the dotnet paths to ci.yml for both push and pull, the action will get stuck when trying to merge a change outside said filters
- **My guess:**
Having the paths added to pull requests makes the branch policy to be respected, but since the action won't get triggered, it will stay stuck
- **Confirmed with:**
GitHub UI's error: Expected — Waiting for status to be reported
- **Cause:**
Paths added to the pull request section in ci.yml triggers
- **Fix:**
Removed the paths from the pull request section
- **Interview line:**
One must be cautious when it comes to path filtering for workflow triggers, and avoid repeating paths for both push and pulls, since this will trigger branch protection policies, but won't do the same for workflows, and thus the merge attempts will stay stuck.

### 3.2 Which job does the ruleset actually require?

- **What I found:**
- **What I changed:**

## Stage 4 — Docker by hand

### 4.1 A secret baked into the image

- **Symptom:**
- **My guess:**
- **Confirmed with:**
- **Cause:**
- **Fix:**
- **Interview line:**

## Stage 5 — Multi-stage .NET image

### 5.1 Container started, but the browser can't reach it (`-p 5000:80`)

- **Symptom:**
- **My guess:**
- **Confirmed with:**
- **Cause:**
- **Fix:**
- **Interview line:**

## Stage 6 — Drills

### 6.1 App dies at startup

- **Symptom:**
- **Status / code from `docker ps -a`:**
- **My guess:**
- **Confirmed with:**
- **Cause:**
- **Fix:**
- **Interview line:**

### 6.2 Memory limit

- **Symptom:**
- **Status / code from `docker ps -a`:**
- **What `docker inspect` says:**
- **Cause:**
- **Fix:**
- **Interview line:**

### 6.3 App is up but unreachable

- **Symptom:**
- **My guess:**
- **Confirmed with (from inside the container):**
- **Cause:**
- **Fix:**
- **Interview line:**

### 6.4 Build can't find a file

- **Symptom:**
- **My guess:**
- **Confirmed with:**
- **Cause:**
- **Fix:**
- **Interview line:**

### 6.5 Old code still running

- **Symptom:**
- **How I proved which commit was running:**
- **Cause:**
- **Fix:**
- **Interview line:**

## Stage 7 — Image pipeline to GHCR

### 7.1 Missing `packages: write`

- **Symptom:**
- **My guess:**
- **Confirmed with:**
- **Cause:**
- **Fix:**
- **Interview line:**

### 7.2 Pull request builds the image but doesn't push it

- **Log line that proves it:**

## Stage 8 — Reusable workflow and monorepo

### 8.1 PR touching only `inventory-api`

- **What ran, what was skipped:**

### 8.2 README-only PR (the 3.1 trap, revisited)

- **Result now, and why:**

### 8.3 A broken Python test

- **What `ci-ok` did, and why:**

### 8.4 Caller without `packages: write`

- **Symptom:**
- **Where it failed:**
- **Cause:**
- **Interview line:**

## Stage 9 — Hand-off to the config repo

### 9.1 `GITHUB_TOKEN` instead of the PAT

- **Symptom:**
- **My guess:**
- **Confirmed with:**
- **Cause:**
- **Fix:**
- **Interview line:**

### 9.2 Re-running `update-config` with nothing to change

- **What happened:**

### 9.3 Two merges back to back

- **What `concurrency` did:**

## Bonus — ACR with OIDC

### B.1 Tag push and the Azure login

- **Symptom (AADSTS error):**
- **My guess:**
- **Cause:**
- **Decision (second credential or no tag builds), and why:**
- **Interview line:**