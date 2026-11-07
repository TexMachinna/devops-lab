#!/usr/bin/env bash
# lab1-check.sh - verifies each stage of "Lab 1 - Ship a Container from a Pull Request"
#
# Usage (from the root of your devops-lab repo):
#   bash tools/lab1-check.sh <stage>     stage = 0..9 | bonus | all
#
# Optional environment variables:
#   PLATFORM_CONFIG_DIR   path to your platform-config clone (default: ../platform-config)
#   SKIP_DOCKER=1         skip checks that build and run containers
#   SKIP_SLOW=1           skip 'dotnet test' and other slow checks
#   ORDERS_DIR, TESTS_DIR, INV_DIR, PHP_DIR   override the default folder names
#
# Green = pass, red = fail (with a hint), yellow = skipped or a warning.
# The checker only reads your files and runs local builds; it never changes your repo
# or anything on GitHub.

set -u
export GIT_TERMINAL_PROMPT=0   # never stop to ask for GitHub credentials

ORDERS_DIR=${ORDERS_DIR:-src/orders-api}
TESTS_DIR=${TESTS_DIR:-tests/OrdersApi.Tests}
INV_DIR=${INV_DIR:-src/inventory-api}
PHP_DIR=${PHP_DIR:-src/supplier-portal}
PLATFORM_CONFIG_DIR=${PLATFORM_CONFIG_DIR:-../platform-config}
WF_DIR=.github/workflows
BREAKIT=docs/break-it.md
SKIP_DOCKER=${SKIP_DOCKER:-0}
SKIP_SLOW=${SKIP_SLOW:-0}

if [ -t 1 ]; then
  G=$'\e[32m'; R=$'\e[31m'; Y=$'\e[33m'; B=$'\e[1m'; D=$'\e[2m'; N=$'\e[0m'
else
  G=; R=; Y=; B=; D=; N=
fi

PASS=0; FAIL=0; SKIPPED=0
pass() { PASS=$((PASS + 1)); printf '  %s✔%s %s\n' "$G" "$N" "$1"; }
fail() { FAIL=$((FAIL + 1)); printf '  %s✘%s %s\n' "$R" "$N" "$1"; [ -n "${2:-}" ] && printf '    %shint: %s%s\n' "$D" "$2" "$N"; return 0; }
skip() { SKIPPED=$((SKIPPED + 1)); printf '  %s–%s %s %s(skipped: %s)%s\n' "$Y" "$N" "$1" "$D" "$2" "$N"; }
warn() { printf '  %s!%s %s\n' "$Y" "$N" "$1"; }
title() { printf '\n%sStage %s — %s%s\n' "$B" "$1" "$2" "$N"; }
have() { command -v "$1" >/dev/null 2>&1; }

# check "description" "hint" command...   -> pass/fail on the command's exit status
check() { local d=$1 h=$2; shift 2; if "$@" >/dev/null 2>&1; then pass "$d"; else fail "$d" "$h"; fi; }

# --- workflow helpers --------------------------------------------------------
wf_files() { ls "$WF_DIR"/*.yml "$WF_DIR"/*.yaml 2>/dev/null; }
wf_has() { local f; f=$(wf_files); [ -n "$f" ] && grep -Eq -- "$1" $f; }
wf_count() { local f; f=$(wf_files); [ -z "$f" ] && { echo 0; return; }; grep -Eho -- "$1" $f | wc -l | tr -d ' '; }
wfcheck() { check "$1" "$3" wf_has "$2"; }   # wfcheck "description" "regex" "hint"

# --- docker helpers ----------------------------------------------------------
docker_ok() {
  [ "$SKIP_DOCKER" = 1 ] && return 1
  have docker && docker info >/dev/null 2>&1
}
CONTAINERS=()
cleanup() { local c; for c in "${CONTAINERS[@]:-}"; do [ -n "$c" ] && docker rm -f "$c" >/dev/null 2>&1; done; }
trap cleanup EXIT

# http_get URL -> prints body, fails on non-2xx (curl, else python)
http_get() {
  if have curl; then curl -fsS --max-time 3 "$1"
  else python3 - "$1" <<'PY'
import sys, urllib.request
print(urllib.request.urlopen(sys.argv[1], timeout=3).read().decode())
PY
  fi
}
# wait_http URL -> retries for ~20s, prints body of the first success
wait_http() { local i; for i in $(seq 1 20); do http_get "$1" 2>/dev/null && return 0; sleep 1; done; return 1; }

# run_image IMAGE CONTAINER_PORT NAME [extra docker args...] -> prints host port
run_image() {
  local img=$1 cport=$2 name=$3; shift 3
  docker rm -f "$name" >/dev/null 2>&1
  docker run -d --name "$name" -p "127.0.0.1::$cport" "$@" "$img" >/dev/null || return 1
  CONTAINERS+=("$name")
  docker port "$name" "$cport/tcp" | head -1 | sed 's/.*://'
}

# --- GitHub helpers ----------------------------------------------------------
SLUG=""
gh_ok() {
  have gh || return 1
  gh auth status >/dev/null 2>&1 || return 1
  [ -n "$SLUG" ] || SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
  [ -n "$SLUG" ]
}
owner_lc() { echo "${SLUG%%/*}" | tr '[:upper:]' '[:lower:]'; }
branch_rules() { gh api "repos/$SLUG/rules/branches/main" -q '[.[].type] | join(" ")' 2>/dev/null; }
ghcr_has() { gh api "/users/$(owner_lc)/packages/container/$1" >/dev/null 2>&1; }

# line number of the first line matching a regex (0 if none)
line_of() { local n; n=$(grep -nE -- "$1" "$2" 2>/dev/null | head -1 | cut -d: -f1); echo "${n:-0}"; }

# =============================================================================
stage0() {
  title 0 "Setup"
  check "git user.name is set" "git config --global user.name \"Your Name\"" test -n "$(git config user.name)"
  if [ -n "$(git config user.email)" ]; then
    pass "git user.email is set"
    case "$(git config user.email)" in
      *noreply*) pass "commit email is your GitHub noreply address" ;;
      *) warn "commit email isn't a noreply address; it will be public in this repo's history" ;;
    esac
  else
    fail "git user.email is set" "use the noreply address from GitHub Settings > Emails"
  fi
  check "inside a git repository" "run this from the root of devops-lab" git rev-parse --is-inside-work-tree
  check "origin points at GitHub" "gh repo create devops-lab --public --clone" sh -c 'git remote get-url origin | grep -q github.com'
  check ".gitignore exists" "dotnet new gitignore, then add .venv/ __pycache__/ .env" test -f .gitignore
  case "$PWD" in
    /mnt/*) warn "repo lives under $PWD; move it to ~/code for much faster builds" ;;
    *) pass "repo is on the Linux filesystem" ;;
  esac
  if have docker; then
    check "Docker daemon answers" "start Docker Desktop (WSL integration on) or: sudo service docker start" docker info
  else
    fail "docker is installed" "install Docker Desktop with WSL integration, or Docker Engine inside WSL"
  fi
  if have dotnet; then
    check ".NET SDK 10.x is installed" "install the 10.0 channel" sh -c 'dotnet --list-sdks | grep -q "^10\."'
  else
    fail ".NET SDK is installed" "Microsoft's dotnet-install.sh --channel 10.0"
  fi
  check "Python 3.12+ is installed" "sudo apt install python3 python3-venv python3-pip" \
    python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 12) else 1)'
  if have gh; then
    check "gh is logged in" "gh auth login" gh auth status
  else
    skip "GitHub CLI checks" "gh not installed; GitHub-side checks in later stages will be skipped"
  fi
}

stage1() {
  title 1 "Git flow and rulesets"
  check "$BREAKIT exists" "create it on branch stage-1/git-flow" test -f "$BREAKIT"
  check "tag v0.1.0 exists locally" "git tag -a v0.1.0 -m \"Lab 1 baseline\"" git rev-parse -q --verify refs/tags/v0.1.0
  check "tag v0.1.0 is on GitHub" "git push origin v0.1.0" sh -c 'git ls-remote --tags origin v0.1.0 | grep -q v0.1.0'
  if gh_ok; then
    check "at least one merged pull request" "open a PR with gh pr create --fill and squash-merge it" \
      sh -c "[ \"\$(gh pr list --repo $SLUG --state merged --limit 1 --json number -q length)\" -ge 1 ]"
    local rules; rules=$(branch_rules)
    case " $rules " in *" pull_request "*) pass "main requires a pull request" ;;
      *) fail "main requires a pull request" "Settings > Rules > Rulesets > New branch ruleset" ;; esac
    case " $rules " in *" non_fast_forward "*) pass "force pushes to main are blocked" ;;
      *) fail "force pushes to main are blocked" "tick 'Block force pushes' in the ruleset" ;; esac
  else
    skip "GitHub checks (merged PR, ruleset)" "gh missing or not logged in"
  fi
}

stage2() {
  title 2 "First CI workflow"
  local csproj; csproj=$(ls "$ORDERS_DIR"/*.csproj 2>/dev/null | head -1)
  check "API project exists in $ORDERS_DIR" "dotnet new webapi -n OrdersApi -o $ORDERS_DIR" test -n "$csproj"
  check "Program.cs maps /health" "app.MapGet(\"/health\", ...)" grep -q '"/health"' "$ORDERS_DIR/Program.cs"
  check "Program.cs maps /api/info" "return the environment name and Greeting" grep -q '"/api/info"' "$ORDERS_DIR/Program.cs"
  check "OrderMath.cs exists" "add the Total(unitPrice, quantity, discountPercent) method" test -f "$ORDERS_DIR/OrderMath.cs"
  local tproj; tproj=$(ls "$TESTS_DIR"/*.csproj 2>/dev/null | head -1)
  check "xUnit test project exists in $TESTS_DIR" "dotnet new xunit -n OrdersApi.Tests -o $TESTS_DIR" test -n "$tproj"
  check "test project references the API" "dotnet add $TESTS_DIR reference $ORDERS_DIR" grep -q 'ProjectReference' "${tproj:-/dev/null}"
  check "a solution file exists at the root" "dotnet new sln -n devops-lab; dotnet sln add ..." \
    sh -c 'ls *.sln *.slnx 2>/dev/null | grep -q .'
  wfcheck "a workflow checks out the code" 'uses: *actions/checkout@' "the runner starts empty (Module 1 §02)"
  wfcheck "a workflow sets up .NET" 'uses: *actions/setup-dotnet@' "actions/setup-dotnet with dotnet-version 10.0.x"
  wfcheck "a workflow runs dotnet test" 'dotnet test' "add a 'run: dotnet test' step"
  wfcheck "CI runs on pull requests" '^ *pull_request:?' "add pull_request under on:"
  if [ "$SKIP_SLOW" = 1 ]; then skip "dotnet test passes locally" "SKIP_SLOW=1"
  elif have dotnet; then
    check "dotnet test passes locally" "run dotnet test and read the first failure" dotnet test --nologo -v q
  else skip "dotnet test passes locally" "dotnet not installed"; fi
  if gh_ok; then
    case " $(branch_rules) " in *" required_status_checks "*) pass "main requires a status check" ;;
      *) fail "main requires a status check" "edit the ruleset: Require status checks to pass" ;; esac
  else skip "ruleset requires a status check" "gh missing or not logged in"; fi
}

stage3() {
  title 3 "Triggers, jobs, outputs and cache"
  wfcheck "manual trigger (workflow_dispatch)" 'workflow_dispatch' "Module 1 §03"
  wfcheck "change filtering (paths or paths-filter)" '(^ *paths:|dorny/paths-filter)' "Module 1 §03, Why paths matter"
  wfcheck "jobs chained with needs" '^ *needs:' "test should have needs: build"
  wfcheck "a value written to \$GITHUB_OUTPUT" 'GITHUB_OUTPUT' "echo \"tag=\${GITHUB_SHA::7}\" >> \"\$GITHUB_OUTPUT\""
  wfcheck "a job exposes outputs" '^ *outputs:' "Module 1 §04, Passing an image tag between jobs"
  wfcheck "dependencies are cached" '(actions/cache@|^ *cache: )' "Module 1 §06"
  wfcheck "test results uploaded as an artifact" 'actions/upload-artifact@' "dotnet test --logger trx, then upload TestResults"
  wfcheck "superseded runs are cancelled (concurrency)" 'cancel-in-progress: *true' "concurrency: group: ci-\${{ github.ref }}"
  check "Dependabot watches GitHub Actions versions" "create .github/dependabot.yml with package-ecosystem: github-actions" \
    grep -Eq 'package-ecosystem: *"?github-actions' .github/dependabot.yml
  if wf_has '(vars\.APP_NAME|secrets\.DEMO_SECRET)'; then pass "a variable or secret is used"
  else warn "no vars.APP_NAME / secrets.DEMO_SECRET found (step 7); fine if you removed it after the test"; fi
}

stage4() {
  title 4 "Docker by hand (Python)"
  local df="$INV_DIR/Dockerfile"
  check "$INV_DIR/app.py exists" "Flask app with /health and /api/items" test -f "$INV_DIR/app.py"
  check "app.py serves /health" "@app.get(\"/health\")" grep -q '/health' "$INV_DIR/app.py"
  check "requirements.txt pins versions" "flask==x.y.z and gunicorn==x.y.z" grep -q '==' "$INV_DIR/requirements.txt"
  check "tests exist (test_app.py)" "two tests with Flask's test client" test -f "$INV_DIR/test_app.py"
  check "Dockerfile exists" "Module 2 §03" test -f "$df"
  local req code pip
  req=$(line_of '^COPY +requirements' "$df"); pip=$(line_of '^RUN +pip install' "$df"); code=$(line_of '^COPY +\. ' "$df")
  if [ "$req" -gt 0 ] && [ "$pip" -gt "$req" ] && [ "$code" -gt "$pip" ]; then
    pass "fast order: requirements, pip install, then code"
  else fail "fast order: requirements, pip install, then code" "Module 2 §04, Rule of thumb"; fi
  if grep -Eq '^USER +' "$df" && ! grep -Eq '^USER +(root|0)( |$)' "$df"; then pass "runs as a non-root USER"
  else fail "runs as a non-root USER" "useradd --create-home appuser, then USER appuser"; fi
  check "EXPOSE 8000" "documents the port" grep -Eq '^EXPOSE +8000' "$df"
  check "binds 0.0.0.0" "gunicorn --bind 0.0.0.0:8000" grep -q '0\.0\.0\.0' "$df"
  check ".dockerignore exists" "Module 2 §03" test -f "$INV_DIR/.dockerignore"
  local p; for p in '.venv' '__pycache__' '.env'; do
    check ".dockerignore excludes $p" "add $p to $INV_DIR/.dockerignore" grep -qF "$p" "$INV_DIR/.dockerignore"
  done
  check ".gitignore excludes .env" "add .env to .gitignore" grep -Eq '(^|/)\.env$' .gitignore
  if ! docker_ok; then skip "build, run, /health and non-root user" "Docker not available or SKIP_DOCKER=1"; return; fi
  local img=lab1-check/inventory-api:check port uid
  if docker build -q -t "$img" "$INV_DIR" >/dev/null 2>&1; then pass "image builds"
  else fail "image builds" "docker build -t inventory-api:dev $INV_DIR and read the error"; return; fi
  port=$(run_image "$img" 8000 lab1-check-inv)
  if [ -n "$port" ] && wait_http "http://127.0.0.1:$port/health" >/dev/null; then pass "container answers /health"
  else fail "container answers /health" "docker logs lab1-check-inv (bind address? port?)"; fi
  uid=$(docker exec lab1-check-inv id -u 2>/dev/null)
  if [ -n "$uid" ] && [ "$uid" != 0 ]; then pass "process runs as uid $uid, not root"
  else fail "process doesn't run as root" "check the USER line"; fi
}

stage5() {
  title 5 "Multi-stage .NET image"
  local df="$ORDERS_DIR/Dockerfile"
  check "Dockerfile exists" "Module 2 §05" test -f "$df"
  check "at least two FROM stages" "a build stage and a final stage" sh -c "[ \$(grep -Ec '^FROM ' '$df') -ge 2 ]"
  check "build stage uses the SDK image" "FROM mcr.microsoft.com/dotnet/sdk:10.0 AS build" grep -Eiq '^FROM .*dotnet/sdk.* as ' "$df"
  check "final stage uses the aspnet runtime" "FROM mcr.microsoft.com/dotnet/aspnet:10.0" grep -Eq '^FROM .*dotnet/aspnet' "$df"
  check "only build output crosses stages (COPY --from)" "COPY --from=build /app/publish ." grep -Eq '^COPY +--from=' "$df"
  local req code
  req=$(line_of '^COPY +[^ ]*\.csproj' "$df"); code=$(line_of '^COPY +\. ' "$df")
  if [ "$req" -gt 0 ] && [ "$code" -gt "$req" ]; then pass ".csproj copied and restored before the code"
  else fail ".csproj copied and restored before the code" "COPY OrdersApi.csproj . then RUN dotnet restore, then COPY . ."; fi
  if grep -Eq '^USER +' "$df" && ! grep -Eq '^USER +(root|0)( |$)' "$df"; then pass "runs as a non-root USER"
  else fail "runs as a non-root USER" "USER \$APP_UID"; fi
  check ".dockerignore excludes bin/ and obj/" "**/bin and **/obj" sh -c "grep -q bin '$ORDERS_DIR/.dockerignore' && grep -q obj '$ORDERS_DIR/.dockerignore'"
  check "appsettings.Staging.json has a Greeting" "\"Greeting\": \"Hello from staging\"" grep -q Greeting "$ORDERS_DIR/appsettings.Staging.json"
  check "image records its commit (revision label)" "ARG GIT_SHA=unknown + LABEL org.opencontainers.image.revision=\$GIT_SHA" \
    grep -q 'org.opencontainers.image.revision' "$df"
  if ! docker_ok; then skip "build, run as Staging, label and size" "Docker not available or SKIP_DOCKER=1"; return; fi
  local img=lab1-check/orders-api:check sha port body label
  sha=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
  if docker build -q --build-arg GIT_SHA="$sha" -t "$img" "$ORDERS_DIR" >/dev/null 2>&1; then pass "image builds"
  else fail "image builds" "docker build -t orders-api:dev $ORDERS_DIR and read the error"; return; fi
  label=$(docker image inspect "$img" --format '{{ index .Config.Labels "org.opencontainers.image.revision" }}' 2>/dev/null)
  if [ "$label" = "$sha" ]; then pass "revision label = $sha"
  else fail "revision label matches the commit (got '$label')" "LABEL must use the GIT_SHA ARG declared in the final stage"; fi
  port=$(run_image "$img" 8080 lab1-check-orders -e ASPNETCORE_ENVIRONMENT=Staging)
  body=$([ -n "$port" ] && wait_http "http://127.0.0.1:$port/api/info")
  if echo "$body" | grep -q Staging; then pass "/api/info reports Staging when run as Staging"
  else fail "/api/info reports Staging when run as Staging" "docker logs lab1-check-orders; is the app on 8080?"; fi
  local mine sdk
  mine=$(docker image inspect "$img" --format '{{.Size}}' 2>/dev/null)
  sdk=$(docker image inspect mcr.microsoft.com/dotnet/sdk:10.0 --format '{{.Size}}' 2>/dev/null)
  if [ -z "$sdk" ]; then skip "image is smaller than the SDK image" "docker pull mcr.microsoft.com/dotnet/sdk:10.0 first"
  elif [ "$mine" -lt "$sdk" ]; then pass "image ($((mine / 1048576)) MB) is smaller than the SDK ($((sdk / 1048576)) MB)"
  else fail "image is smaller than the SDK image" "is the final stage FROM aspnet?"; fi
}

stage6() {
  title 6 "Break-it drills"
  check "$BREAKIT exists" "log every drill there" test -f "$BREAKIT"
  check "notes on exit code 137" "Out of memory drill" grep -q '137' "$BREAKIT"
  check "notes on OOMKilled" "docker inspect oom --format '{{.State.OOMKilled}}'" grep -qi 'oomkilled' "$BREAKIT"
  check "notes on the 0.0.0.0 bind" "Wrong bind address drill" grep -q '0\.0\.0\.0' "$BREAKIT"
  check "notes on the build context" "Wrong build context drill" grep -qi 'context' "$BREAKIT"
  check "notes on the crash on start" "Crash on start drill: record the exit code" grep -Eqi '(crash|exit code)' "$BREAKIT"
}

stage7() {
  title 7 "Image pipeline to GHCR"
  wfcheck "packages: write is granted" 'packages: *write' "on the image job only"
  wfcheck "uses docker/build-push-action" 'docker/build-push-action@' "Module 2 §09"
  wfcheck "uses docker/setup-buildx-action" 'docker/setup-buildx-action@' "needed for the gha cache"
  wfcheck "layer cache via type=gha" 'type=gha' "cache-from: type=gha and cache-to: type=gha,mode=max"
  wfcheck "pull requests build without pushing" 'push: *\$\{\{.*github\.event_name' "push: \${{ github.event_name != 'pull_request' }}"
  wfcheck "images are tagged by commit SHA" '(type=sha|GITHUB_SHA|github\.sha)' "docker/metadata-action with type=sha"
  if wf_has 'docker/metadata-action@'; then pass "tags and labels from docker/metadata-action"
  else warn "docker/metadata-action not found (step 3)"; fi
  wfcheck "tag pushes (v*) trigger a build" "tags: *\\[? *['\"]?v\\*" "on: push: tags: ['v*']"
  if gh_ok; then
    check "orders-api exists in GHCR" "merge to main, then check Packages on your profile" ghcr_has orders-api
  else skip "orders-api exists in GHCR" "gh missing or not logged in"; fi
}

stage8() {
  title 8 "Reusable workflow, monorepo and PHP"
  local rw=""; [ -n "$(wf_files)" ] && rw=$(grep -l 'workflow_call' $(wf_files) </dev/null 2>/dev/null | head -1)
  check "a reusable workflow (on: workflow_call)" "Module 1 §07" test -n "$rw"
  check "the reusable workflow declares inputs" "app-name and context" grep -Eq '^ *inputs:' "${rw:-/dev/null}"
  local callers; callers=$(wf_count 'uses: *\./\.github/workflows/')
  if [ "$callers" -ge 2 ] || { [ "$callers" -ge 1 ] && wf_has '^ *matrix:'; }; then pass "both apps call it ($callers caller(s))"
  else fail "both apps call the reusable workflow" "uses: ./.github/workflows/build-image.yml, once per app or with a matrix"; fi
  wfcheck "per-job change detection" '(dorny/paths-filter@|git diff --name-only)' "a changes job with dorny/paths-filter"
  if wf_has 'dorny/paths-filter@[0-9a-f]{40}'; then pass "third-party action pinned to a commit SHA"
  elif wf_has 'dorny/paths-filter@'; then warn "dorny/paths-filter is pinned to a tag; pin it to a full commit SHA"; fi
  wfcheck "gate job runs even after failures (always())" 'if: *(\$\{\{ *)?always\(\)' "ci-ok: needs every job, if: always()"
  wfcheck "gate job inspects needs results" 'needs\.\*\.result|needs\.[A-Za-z0-9_-]+\.result' "contains(needs.*.result, 'failure')"
  wfcheck "Python tests use setup-python with a pip cache" 'actions/setup-python@' "cache: pip"
  wfcheck "pip cache points at the app's requirements" 'cache-dependency-path' "cache-dependency-path: $INV_DIR/requirements*.txt"
  local compose; compose=$(ls "$PHP_DIR"/compose.yaml "$PHP_DIR"/compose.yml "$PHP_DIR"/docker-compose.yml 2>/dev/null | head -1)
  check "PHP compose file exists" "Module 2 §08" test -n "$compose"
  check "nginx.conf forwards PHP to FPM" "fastcgi_pass php:9000;" grep -q 'fastcgi_pass' "$PHP_DIR/nginx.conf"
  check "src/index.php exists" "echo \"<?php phpinfo();\" > $PHP_DIR/src/index.php" test -f "$PHP_DIR/src/index.php"
  if [ -n "$compose" ] && docker_ok; then
    check "compose file is valid" "docker compose -f $compose config" docker compose -f "$compose" config -q
  else skip "compose file is valid" "Docker not available or no compose file"; fi
  if gh_ok; then
    check "inventory-api exists in GHCR" "merge a change under $INV_DIR" ghcr_has inventory-api
  else skip "inventory-api exists in GHCR" "gh missing or not logged in"; fi
}

stage9() {
  title 9 "Hand-off to the config repo"
  wfcheck "uses the CONFIG_REPO_TOKEN secret" 'secrets\.CONFIG_REPO_TOKEN' "a fine-grained PAT limited to platform-config"
  wfcheck "checks out the config repo" 'repository: *[^ ]*platform-config' "actions/checkout with repository: <owner>/platform-config"
  wfcheck "updates the tag with kustomize" 'kustomize edit set image' "Module 1 §08"
  wfcheck "commits only when something changed" 'git diff --cached --quiet' "the guard from Module 1 §08"
  wfcheck "config updates are serialized (concurrency)" 'concurrency: *config' "concurrency: config-repo on the update job"
  wfcheck "commit message links to the run" 'actions/runs/\$\{\{ *github\.run_id' "\${{ github.server_url }}/\${{ github.repository }}/actions/runs/\${{ github.run_id }}"
  local pc=$PLATFORM_CONFIG_DIR app="$PLATFORM_CONFIG_DIR/apps/orders-api"
  if [ ! -d "$pc/.git" ]; then
    fail "platform-config clone found at $pc" "clone it next to devops-lab, or set PLATFORM_CONFIG_DIR"; return
  fi
  pass "platform-config clone found at $pc"
  check "base deployment exists" "apps/orders-api/base/deployment.yaml" test -f "$app/base/deployment.yaml"
  local o; for o in dev stg prd; do
    check "overlay $o exists" "apps/orders-api/overlays/$o/kustomization.yaml" test -f "$app/overlays/$o/kustomization.yaml"
  done
  local devk="$app/overlays/dev/kustomization.yaml"
  if grep -Eq 'newTag: *["'\'']?latest' "$devk" 2>/dev/null; then fail "dev overlay pins a real tag" "never deploy latest"
  else check "dev overlay pins a tag" "images: - name/newName/newTag" grep -q 'newTag:' "$devk"; fi
  if have kubectl; then
    check "dev overlay renders" "kubectl kustomize $app/overlays/dev" kubectl kustomize "$app/overlays/dev"
  elif have kustomize; then
    check "dev overlay renders" "kustomize build $app/overlays/dev" kustomize build "$app/overlays/dev"
  else skip "dev overlay renders" "install kubectl"; fi
  check "CI has committed to platform-config" "git -C $pc pull first; author must be ci-bot" \
    sh -c "git -C '$pc' log --author=ci-bot --oneline | grep -q ."
}

stagebonus() {
  title bonus "ACR with OIDC login"
  wfcheck "logs in with azure/login" 'azure/login@' "Module 2 §09, Azure version"
  wfcheck "requests an OIDC token (id-token: write)" 'id-token: *write' "on the calling job"
  wfcheck "Azure IDs come from variables" 'vars\.AZURE_CLIENT_ID' "none of them is a secret"
  wfcheck "logs Docker in to ACR" 'az acr login' "az acr login --name <acrname>"
  if [ -z "$(wf_files)" ]; then fail "no stored ACR or Azure password" "no workflows found yet"
  elif wf_has 'secrets\.[A-Z_]*(ACR|AZURE)[A-Z_]*(PASS|SECRET|PWD)'; then
    fail "no stored ACR or Azure password" "OIDC needs no password; delete that secret"
  else pass "no stored ACR or Azure password"; fi
}

# =============================================================================
main() {
  local arg=${1:-}
  if [ -z "$arg" ]; then sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; exit 2; fi
  [ -d .git ] || warn "no .git here: run this from the root of devops-lab"
  case "$arg" in
    [0-9]) "stage$arg" ;;
    bonus) stagebonus ;;
    all) local s; for s in 0 1 2 3 4 5 6 7 8 9 bonus; do "stage$s"; done ;;
    *) echo "unknown stage '$arg' (use 0-9, bonus or all)"; exit 2 ;;
  esac
  printf '\n%s%d passed%s, %s%d failed%s, %s%d skipped%s\n' "$G" "$PASS" "$N" "$R" "$FAIL" "$N" "$Y" "$SKIPPED" "$N"
  [ "$FAIL" -eq 0 ]
}
main "$@"
