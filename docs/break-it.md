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
build and test
- **What I changed:**
added both jobs to the ruleset condition for main

## Stage 4 — Docker by hand

### 4.1 A secret baked into the image

- **Symptom:**
There's a dummy secret backed-in a docker image
- **My guess:**
I intentionally left a docker secret backed in a .env file in my docker image
- **Confirmed with:**
docker run --rm <image name> cat .env
- **Cause:**
Left a secret in a .env file
- **Fix:**
Removed the secret from the .env file, and also added .env files to my .dockerignore file
- **Interview line:**
Secrets can be passed to images at runtime, but never backed inside the image itself

## Stage 5 — Multi-stage .NET image

### 5.1 Container started, but the browser can't reach it (`-p 5000:80`)

- **Symptom:**
Up, but curl returns Connection reset by peer
- **My guess:**
- **Confirmed with:**
docker logs (listening on 8080) versus docker port (80 mapped), also "ASPNETCORE_HTTP_PORTS=8080" in the app's JSON config (docker inspect image)
- **Cause:**
5000:80 forwarded to a port nothing was listening on
- **Fix:**
-p 5000:8080, the container-side port must match the app's port
- **Interview line:**
"Up doesn't mean reachable. I compare the port the app logs with the port mapping."

## Stage 6 — Drills

### 6.1 App dies at startup

- **Symptom:**
My dotnet app container isn't running
- **Status / code from `docker ps -a`:**
Exited (139)
- **My guess:**
Logs need to be checked in order to confirm what caused the error from (docker ps -a)
- **Confirmed with:**
docker logs <container>: got the following stack trace = Unhandled exception. System.InvalidOperationException: Crash drill: CRASH_ON_START is set
   at Program.<Main>$(String[] args) in /src/Program.cs:line 4
- **Cause:**
An env variable that I intentionally added to Program.cs, which caused the app to crash on startup
- **Fix:**
Either remove the env variable from the code, or don't pass the value to the variable at runtime. exit code 139, which is 139 - 128 = code 11/SEGV(segmentation fault) would have me chasing a memory bug, while the stack trace would point me towards the real issue
- **Interview line:**
Docker exit codes can tell us how a container died, but logs and stack traces reveal the actual cause, making them the first thing to check

### 6.2 Memory limit

- **Symptom:**
Container died as soon as I tried to run it
- **Status / code from `docker ps -a`:**
Exited (137), 137 - 128 = code 9 KILL
- **What `docker inspect` says:**
"OOMKilled": true
- **Cause:**
[docker run -m 64m --memory-swap 64m --name oom inventory-api:dev python -c "b = bytearray(512 * 1024 * 1024)"], swap limit was the same as the MBs assigned to the container, which means swap was off, and then an array of 512MB was passed to the container, causing it to crash the container since there was no space in memory for it. In this case, there where no logs from [docker logs], so my only troubleshooting clue was the exit code from docker
- **Fix:**
Don't exceed a container's memory limit
- **Interview line:**
A container's memory limit covers all its processes. Exceed it with no swap and the kernel OOM-kills it: 137 and OOMKilled=true, with no stack trace

### 6.3 App is up but unreachable

- **Symptom:**
A container doesn't respond through its configured port
- **My guess:**
Wrong Dockerfile configuration, specifically the port being used by the app
- **Confirmed with (from inside the container):**
[docker exec <container name> python -c "import urllib.request; print(urllib.request.urlopen('https://127.0.0.1:8000/health').read())]
- **Cause:**
Dockerfile was intentionally configured to use 127.0.0.1 instead of its usual 0.0.0.0 port. This is the container's loopback port, and only connections within the container were allowed
- **Fix:**
Changed the port binding in the Dockerfile to use 0.0.0.0 as it should
- **Interview line:**
Running doesn't mean reachable. In containers, apps must bind 0.0.0.0, because 127.0.0.1 is the container's own loopback

### 6.4 Build can't find a file

- **Symptom:**
Can't build an image using docker build -f
- **My guess:**
Docker can't find the correct files
- **Confirmed with:**
Running docker -f with no files. I've also tried again with the right folder, but no more context
- **Cause:**
Missing context at the end of the command, ergo, docker couldn't find the right requirements.txt file
- **Fix:**
Pointed docker build -f to the right source context at the end of the command
- **Interview line:**
-f picks the recipe, the context picks the ingredients, and COPY only sees what's in the context

### 6.5 Old code still running

- **Symptom:**
Running container doesn't show the newest changes
- **How I proved which commit was running:**
By checking the image GHA property with [docker inspect stale --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}'] and comparing it against GitHub's most recent commits [git log --oneline -2]
- **Cause:**
The container is using the image version that was built before the changes
- **Fix:**
Re-built the image, ran the container again and now it has the newest changes + the correct GHA SHA
- **Interview line:**
When a fix doesn't show up, I check which image is actually running: its revision label or digest against the commit I expected

## Stage 7 — Lab registry, self-hosted runner and image pipeline

### 7.1 Runner offline during a merge

- **Symptom (job status and message):**
During the job that gets handled by my self-hosted runner, Git shows "Waiting for arunner to pick up
this job" and doesn't continue with the pipeline, nor fails or exits it.
- **My guess:**
My self-hosted runner might not be running
- **Confirmed with:**
Checking the runner's status through Git's GUI, in which the runner appeared as Offline
- **Cause:**
Runner was stopped locally
- **Fix:**
Started the runner (./svc.sh start)
- **Interview line:**
If a job that's supposed to be handled by a self-hosted runner is stopped, it's a good idea to check
its status trough Git's runner section to see if its online. If it isn't, checking its status locally
and troubleshoot is the best option

### 7.2 Registry down during a publish

- **Symptom (exact push error):**
Error: buildx failed with: failed to build: failed to solve: failed to push localhost:5000/orders-api:sha-33ad449: failed to do request: Head "https://localhost:5000/v2/orders-api/blobs/sha256:2134cabc5f328f9c3919aeef221f7171dbb93bbe2a41e7bc01281c2a6653d575": dial tcp 127.0.0.1:5000: connect: connection refused
- **My guess:**
Registry container is down
- **Confirmed with:**
Checked my containers and saw the registry one was stopped (docker ps)
- **Cause:**
Registry was intentionally stopped
- **Fix:**
Resumed the container and re-ran the pipeline, which finished successfully
- **Interview line:**
I separate build failures from push failures in the log. Connection refused on push is infrastructure, not the Dockerfile

### 7.3 Pull request: image-check ran, image-publish skipped

- **Where each job ran (runner name), and the log line that proves nothing was pushed:**
My first jobs, related to build checks, ran on a GitHub ephemeral VM, once those passed, the code
reach my self-hosted runner. Each job has a 'runner name:', for Git VMs it shows 'GitHub Actions...'
plus the VM's OS version, in this case 'ubuntu-24.04' (matching the 'ubuntu-latest' setup), and
my runner's name, in this case 'wsl-hosted-runner', along with my local machine's name

## Stage 8 — Reusable workflow and monorepo

### 8.1 PR touching only `inventory-api`

- **What ran, what was skipped:**
After the setup and changes made through 'ci-ok', the only jobs that ran were those related to inventory-api, shuch as inventory-test and inventory-image/check, the rest of the jobs that covered the .NET api were skipped as intended, since the PR didn't touch them.

### 8.2 README-only PR (the 3.1 trap, revisited)

- **Result now, and why:**
All the jobs where skipped besides the dorny one, which is the first job that tracks changes to the files. Since README.md isn't tied to any of the apis and it doesn't live under any of their folders, the pipeline worked as intended.

### 8.3 A broken Python test

- **What `ci-ok` did, and why:**

### 8.4 One runner, two queued publish jobs

- **What happened while the runner was stopped:**
- **What happened after it started again (order, timing):**
- **What this means for a team, and how teams solve it:**

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

## Bonus — Registry login and a hardened runner

### B.1 Wrong registry password

- **Symptom (the login step's error):**
- **My guess:**
- **Confirmed with:**
- **Cause:**
- **Fix:**
- **Interview line:**