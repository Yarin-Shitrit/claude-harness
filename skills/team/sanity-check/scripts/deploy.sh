#!/usr/bin/env bash
# Deploy the full Keep stack for sanity checks: infra (Postgres + Kafka + Redis + Pusher) + 4 services.
# Each service loads its own <repo>/.env (validated/seeded from scripts/env-templates) so the dev
# environment matches what the app actually expects, and every Python service shares ONE Postgres DB
# so none silently falls back to SQLite or a split-brain "keep_bench".
#
#   ./deploy.sh --root <path>            # start everything (reuses existing Postgres data)
#   ./deploy.sh --root <path> --clean    # wipe Postgres/Kafka volumes first (deterministic clean run)
#   ./deploy.sh --root <path> --install  # force a dependency (re)install before launching
#   ./deploy.sh --root <path> --down     # stop all services + infra, then exit
#
# --root is the directory that CONTAINS the four keep-* repos. You can also set KEEP_ROOT instead of
# passing --root. If neither is given the script falls back to resolving siblings from its own location
# (only correct when run from inside a repo checkout, not from a global skill install).
#
# Flags may be combined. Dependencies are installed automatically on first run (poetry install where a
# venv is missing, npm install where node_modules is missing); use --install to force a reinstall.
# Logs + PIDs land in <repo-root>/.sanity-run/.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATES="$SCRIPT_DIR/env-templates"

# Ports the dev env owns. Gateway 8080, workflows 8081, event-handler health 8092 / metrics 8094, UI 3000.
NEEDED_PORTS="8080 8081 8092 8094 3000"

# Parse flags (order-independent). --root takes a value.
CLEAN=0; INSTALL=0; DOWN=0; ROOT_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean)   CLEAN=1 ;;
    --install) INSTALL=1 ;;
    --down)    DOWN=1 ;;
    --root)    shift; ROOT_ARG="${1:-}"; [[ -z "$ROOT_ARG" ]] && { echo "--root needs a path" >&2; exit 2; } ;;
    --root=*)  ROOT_ARG="${1#--root=}" ;;
    *) echo "unknown flag: $1 (use --root <path> / --clean / --install / --down)" >&2; exit 2 ;;
  esac
  shift
done

# Resolve the repo root: --root > KEEP_ROOT > sibling-of-script fallback.
if   [[ -n "$ROOT_ARG" ]];          then ROOT="$(cd "$ROOT_ARG" 2>/dev/null && pwd || true)"
elif [[ -n "${KEEP_ROOT:-}" ]];     then ROOT="$(cd "$KEEP_ROOT" 2>/dev/null && pwd || true)"
else ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"; fi
for r in keep-api-gateway keep-event-handler keep-workflows keep-ui; do
  [[ -d "${ROOT:-}/$r" ]] || {
    echo "Keep repos not found under: ${ROOT:-<unset>} (missing $r)." >&2
    echo "Pass --root <dir-containing-the-keep-*-repos> or set KEEP_ROOT." >&2
    exit 1
  }
done
echo "[root] using Keep repos at: $ROOT"

INFRA="$ROOT/keep-event-handler/docker-compose.infra.yml"
LOGDIR="$ROOT/.sanity-run"
PIDFILE="$LOGDIR/pids.txt"
mkdir -p "$LOGDIR"

# Shared defaults — used by services without a bundled .env (e.g. keep-workflows) and as a safety net.
# A per-service .env loaded at launch overrides these.
export DATABASE_CONNECTION_STRING="postgresql://keep:keep@localhost:5432/keep"
export KAFKA_BOOTSTRAP_SERVERS="localhost:29092"
export MESSAGING_TYPE="KAFKA"
export AUTH_TYPE="noauth"
# macOS only: gunicorn forks workers after the Python runtime has initialized
# Objective-C/native state, which triggers a SIGSEGV crash loop (workers boot
# then immediately segfault, taking the gateway down). Disabling the fork-safety
# guard avoids it; harmless / ignored on Linux.
export OBJC_DISABLE_INITIALIZE_FORK_SAFETY="YES"

stop_services() {
  if [[ -f "$PIDFILE" ]]; then
    while read -r pid; do [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true; done < "$PIDFILE"
    rm -f "$PIDFILE"
  fi
}

probe() { local code; code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$1" || echo 000)"; [[ "$code" -ge 200 && "$code" -lt 500 ]]; }
all_healthy() {
  probe "http://localhost:8080/healthcheck" \
    && probe "http://localhost:8081/healthcheck" \
    && probe "http://localhost:8092/healthz" \
    && probe "http://localhost:3000"
}

free_ports() {  # kill whatever is listening on the dev-env ports so a partial/stale run can't block us
  for p in $@; do
    local pids; pids="$(lsof -ti "tcp:$p" -sTCP:LISTEN 2>/dev/null || true)"
    if [[ -n "$pids" ]]; then
      echo "[ports] freeing :$p (killing $pids)" >&2
      kill $pids 2>/dev/null || true; sleep 1
      pids="$(lsof -ti "tcp:$p" -sTCP:LISTEN 2>/dev/null || true)"
      [[ -n "$pids" ]] && kill -9 $pids 2>/dev/null || true
    fi
  done
}

if [[ "$DOWN" == "1" ]]; then
  stop_services
  docker compose -f "$INFRA" down
  echo "Torn down (services + infra)."
  exit 0
fi

# --- Already-up / conflict handling ------------------------------------------
# If the stack is already fully healthy, reuse it (fast path — don't redeploy). Otherwise the state is
# ambiguous (partial/stale): clear our tracked PIDs and forcibly free the required ports, then start clean.
# A --clean run always rebuilds, so it skips the reuse shortcut.
if [[ "$CLEAN" == "1" ]]; then
  stop_services
  echo "[clean] wiping infra volumes for a deterministic run..."
  docker compose -f "$INFRA" down -v
  free_ports $NEEDED_PORTS
else
  if all_healthy; then
    echo "Dev env already up — reusing it. UI: http://localhost:3000"
    exit 0
  fi
  echo "[start] dev env not fully healthy — clearing tracked PIDs and freeing required ports..."
  stop_services
  free_ports $NEEDED_PORTS
fi

# --- Env validation -----------------------------------------------------------
# Each service needs its <repo>/.env. Seed a missing one from the bundled template so the run can
# proceed, but warn — the template carries placeholder secrets (e.g. OPENAI_API_KEY=sk-REPLACE_ME).
val_of() { grep -E "^$2=" "$1" 2>/dev/null | head -1 | cut -d= -f2-; }

validate_env() {
  echo "[env] validating service .env files..."
  for svc in keep-api-gateway keep-event-handler keep-ui; do
    local dst="$ROOT/$svc/.env" src="$TEMPLATES/$svc.env"
    if [[ ! -f "$dst" ]]; then
      if [[ -f "$src" ]]; then
        cp "$src" "$dst"
        echo "[env] $svc/.env missing — seeded from template. Review it (placeholder secrets!)." >&2
      else
        echo "[env] $svc/.env missing and no template found." >&2
      fi
    fi
  done
  # Every Python service must share ONE database, else ingested alerts never reach the UI.
  local gw eh
  gw="$(val_of "$ROOT/keep-api-gateway/.env" DATABASE_CONNECTION_STRING)"
  eh="$(val_of "$ROOT/keep-event-handler/.env" DATABASE_CONNECTION_STRING)"
  if [[ -n "$gw" && -n "$eh" && "$gw" != "$eh" ]]; then
    echo "[env] WARNING: gateway DB ($gw) != event-handler DB ($eh). They must match," >&2
    echo "      or alerts ingested via the gateway will never appear in the UI." >&2
  fi
  # The UI must call the gateway's real host:port (gateway binds 8080 here).
  local ui_api; ui_api="$(val_of "$ROOT/keep-ui/.env" API_URL)"
  if [[ -n "$ui_api" && "$ui_api" != *":8080"* ]]; then
    echo "[env] WARNING: keep-ui API_URL=$ui_api does not point at the gateway (http://localhost:8080)." >&2
    echo "      Every UI request will hit the wrong port and the app will look broken." >&2
  fi
  # Workflows run as a SEPARATE microservice (:8081). The UI middleware proxies
  # /backend/workflows/* to WORKFLOWS_API_URL, which DEFAULTS to :8082 — wrong
  # for this stack — so without it the workflows page hangs forever on its
  # loader (and any workflow check fails). Ensure it points at :8081.
  local ui_env="$ROOT/keep-ui/.env" ui_local="$ROOT/keep-ui/.env.local"
  local wf_url; wf_url="$(val_of "$ui_local" WORKFLOWS_API_URL)"
  [[ -z "$wf_url" ]] && wf_url="$(val_of "$ui_env" WORKFLOWS_API_URL)"
  if [[ -z "$wf_url" ]]; then
    [[ -f "$ui_env" ]] || touch "$ui_env"
    printf '\nWORKFLOWS_API_URL=http://localhost:8081\n' >> "$ui_env"
    echo "[env] keep-ui WORKFLOWS_API_URL was unset — added http://localhost:8081 to keep-ui/.env" >&2
    echo "      (workflows are served by the keep-workflows service on :8081, not the gateway)." >&2
  elif [[ "$wf_url" != *":8081"* ]]; then
    echo "[env] WARNING: keep-ui WORKFLOWS_API_URL=$wf_url does not point at the workflows service (http://localhost:8081)." >&2
    echo "      The workflows page will hang on its loader (the default proxy target :8082 is dead)." >&2
  fi
}
validate_env

ensure_deps() {
  for r in keep-api-gateway keep-event-handler keep-workflows; do
    if [[ "$INSTALL" == "1" ]] || ! ( cd "$ROOT/$r" && poetry env info -p >/dev/null 2>&1 ); then
      echo "[deps] poetry install ($r)..."; ( cd "$ROOT/$r" && poetry install )
    fi
  done
  if [[ "$INSTALL" == "1" || ! -d "$ROOT/keep-ui/node_modules" ]]; then
    echo "[deps] npm install (keep-ui)..."; ( cd "$ROOT/keep-ui" && npm install )
  fi
}
ensure_deps

echo "[infra] starting postgres + kafka + redis + pusher..."
docker compose -f "$INFRA" up -d

echo "[infra] waiting for postgres..."
pg_ready=0
for _ in $(seq 1 30); do
  if docker compose -f "$INFRA" exec -T postgres pg_isready -U keep >/dev/null 2>&1; then pg_ready=1; break; fi
  sleep 2
done
[[ "$pg_ready" == "1" ]] || { echo "Postgres did not become ready in time"; exit 1; }

start_svc() {  # name  repo  -- cmd...
  local name="$1" repo="$2"; shift 3
  (
    cd "$ROOT/$repo"
    set -a; [[ -f .env ]] && . ./.env; set +a   # load this service's .env (overrides shared defaults)
    nohup "$@" >"$LOGDIR/$name.out.log" 2>"$LOGDIR/$name.err.log" &
    echo $! >> "$PIDFILE"
  )
  echo "[$name] started -> $LOGDIR/$name.out.log"
}

# Ports: gateway 8080, workflows 8081, event-handler health 8092 (from its .env), UI 3000.
start_svc api-gateway   keep-api-gateway   -- poetry run gunicorn src.main:get_app \
            --bind 0.0.0.0:8080 --workers 1 -k uvicorn.workers.UvicornWorker -c src/config/config.py
start_svc event-handler keep-event-handler -- poetry run python -m src.consumer_main
start_svc workflows     keep-workflows     -- poetry run gunicorn src.main:app \
            -w 4 -k uvicorn.workers.UvicornWorker --bind 0.0.0.0:8081
start_svc ui            keep-ui            -- npm run dev

wait_health() {  # name  url  [retries]
  local name="$1" url="$2" retries="${3:-45}"
  echo "[$name] waiting on $url ..."
  for _ in $(seq 1 "$retries"); do
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 3 "$url" || echo 000)"
    if [[ "$code" -ge 200 && "$code" -lt 500 ]]; then echo "[$name] healthy"; return 0; fi
    sleep 2
  done
  echo "[$name] never became healthy — check $LOGDIR/$name.err.log" >&2
  return 1
}

ok=0
wait_health api-gateway   "http://localhost:8080/healthcheck" || ok=1
wait_health workflows     "http://localhost:8081/healthcheck" || ok=1
wait_health event-handler "http://localhost:8092/healthz"     || ok=1
wait_health ui            "http://localhost:3000"             || ok=1

if [[ "$ok" == "0" ]]; then echo -e "\nAll services up. UI: http://localhost:3000"
else echo -e "\nSome services failed — inspect $LOGDIR before running checks." >&2; fi
