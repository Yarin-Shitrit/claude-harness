#requires -Version 5.1
# Deploy the full Keep stack for sanity checks: infra (Postgres + Kafka + Redis + Pusher) + 4 services.
# Each service loads its own <repo>\.env (validated/seeded from scripts\env-templates) so the dev
# environment matches what the app actually expects, and every Python service shares ONE Postgres DB
# so none silently falls back to SQLite or a split-brain "keep_bench".
#
#   .\deploy.ps1 -KeepRoot <path>            # start everything (reuses existing Postgres data)
#   .\deploy.ps1 -KeepRoot <path> -Clean     # wipe Postgres/Kafka volumes first (deterministic clean run)
#   .\deploy.ps1 -KeepRoot <path> -Install   # force a dependency (re)install before launching
#   .\deploy.ps1 -KeepRoot <path> -Down      # stop all services + infra, then exit
#
# -KeepRoot is the directory that CONTAINS the four keep-* repos. You can also set $env:KEEP_ROOT instead.
# If neither is given the script falls back to resolving siblings from its own location (only correct when
# run from inside a repo checkout, not from a global skill install).
#
# Switches may be combined. Dependencies are installed automatically on first run (poetry install where a
# venv is missing, npm install where node_modules is missing); use -Install to force a reinstall.
# Logs + PIDs land in <repo-root>\.sanity-run\.
[CmdletBinding()]
param(
    [string]$KeepRoot,
    [switch]$Clean,
    [switch]$Install,
    [switch]$Down
)
$ErrorActionPreference = "Stop"
$Templates = Join-Path $PSScriptRoot "env-templates"

# Ports the dev env owns. Gateway 8080, workflows 8081, event-handler health 8092 / metrics 8094, UI 3000.
$NeededPorts = @(8080, 8081, 8092, 8094, 3000)

# Resolve the repo root: -KeepRoot > $env:KEEP_ROOT > sibling-of-script fallback.
if     ($KeepRoot)        { $Root = (Resolve-Path $KeepRoot).Path }
elseif ($env:KEEP_ROOT)   { $Root = (Resolve-Path $env:KEEP_ROOT).Path }
else                      { $Root = (Resolve-Path "$PSScriptRoot\..\..\..\..").Path }
foreach ($r in @("keep-api-gateway", "keep-event-handler", "keep-workflows", "keep-ui")) {
    if (-not (Test-Path (Join-Path $Root $r))) {
        throw "Keep repos not found under $Root (missing $r). Pass -KeepRoot <dir-containing-the-keep-*-repos> or set `$env:KEEP_ROOT."
    }
}
Write-Host "[root] using Keep repos at: $Root"

$Infra  = Join-Path $Root "keep-event-handler\docker-compose.infra.yml"
$LogDir = Join-Path $Root ".sanity-run"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$PidFile = Join-Path $LogDir "pids.txt"

# Shared defaults — used by services without a bundled .env (e.g. keep-workflows) and as a safety net.
# A per-service .env loaded at launch overrides these.
$env:DATABASE_CONNECTION_STRING = "postgresql://keep:keep@localhost:5432/keep"
$env:KAFKA_BOOTSTRAP_SERVERS    = "localhost:29092"
$env:MESSAGING_TYPE             = "KAFKA"
$env:AUTH_TYPE                  = "noauth"

function Stop-Services {
    if (Test-Path $PidFile) {
        Get-Content $PidFile | ForEach-Object {
            $procId = $_.Trim()
            if ($procId) { try { Stop-Process -Id ([int]$procId) -Force -ErrorAction SilentlyContinue } catch {} }
        }
        Remove-Item $PidFile -Force
    }
}

function Test-Healthy {
    param([string]$Url)
    try { $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3; return ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) }
    catch { return $false }
}
function Test-AllUp {
    return (Test-Healthy "http://localhost:8080/healthcheck") `
        -and (Test-Healthy "http://localhost:8081/healthcheck") `
        -and (Test-Healthy "http://localhost:8092/healthz") `
        -and (Test-Healthy "http://localhost:3000")
}

function Clear-Ports {  # kill listeners on the dev-env ports so a partial/stale run can't block us
    param([int[]]$Ports)
    foreach ($p in $Ports) {
        try {
            $conns = Get-NetTCPConnection -LocalPort $p -State Listen -ErrorAction SilentlyContinue
            foreach ($c in $conns) {
                Write-Warning "[ports] freeing :$p (pid $($c.OwningProcess))"
                Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

if ($Down) {
    Stop-Services
    docker compose -f $Infra down
    Write-Host "Torn down (services + infra)."
    exit 0
}

# --- Already-up / conflict handling ------------------------------------------
# If the stack is already fully healthy, reuse it (fast path). Otherwise the state is ambiguous
# (partial/stale): clear tracked PIDs and forcibly free the required ports, then start clean.
# A -Clean run always rebuilds, so it skips the reuse shortcut.
if ($Clean) {
    Stop-Services
    Write-Host "[clean] wiping infra volumes for a deterministic run..."
    docker compose -f $Infra down -v
    Clear-Ports $NeededPorts
} else {
    if (Test-AllUp) {
        Write-Host "Dev env already up — reusing it. UI: http://localhost:3000"
        exit 0
    }
    Write-Host "[start] dev env not fully healthy — clearing tracked PIDs and freeing required ports..."
    Stop-Services
    Clear-Ports $NeededPorts
}

# --- Env validation -----------------------------------------------------------
function Get-EnvVal {
    param([string]$Path, [string]$Key)
    if (Test-Path $Path) {
        $m = Select-String -Path $Path -Pattern "^$Key=(.*)$" | Select-Object -First 1
        if ($m) { return $m.Matches[0].Groups[1].Value.Trim() }
    }
    return $null
}
function Test-ServiceEnv {
    Write-Host "[env] validating service .env files..."
    foreach ($svc in @("keep-api-gateway", "keep-event-handler", "keep-ui")) {
        $dst = Join-Path $Root "$svc\.env"
        $src = Join-Path $Templates "$svc.env"
        if (-not (Test-Path $dst)) {
            if (Test-Path $src) {
                Copy-Item $src $dst
                Write-Warning "[env] $svc\.env missing — seeded from template. Review it (placeholder secrets!)."
            } else {
                Write-Warning "[env] $svc\.env missing and no template found."
            }
        }
    }
    $gw = Get-EnvVal (Join-Path $Root "keep-api-gateway\.env") "DATABASE_CONNECTION_STRING"
    $eh = Get-EnvVal (Join-Path $Root "keep-event-handler\.env") "DATABASE_CONNECTION_STRING"
    if ($gw -and $eh -and ($gw -ne $eh)) {
        Write-Warning "[env] gateway DB ($gw) != event-handler DB ($eh). They must match, or ingested alerts never appear in the UI."
    }
    $uiApi = Get-EnvVal (Join-Path $Root "keep-ui\.env") "API_URL"
    if ($uiApi -and ($uiApi -notlike "*:8080*")) {
        Write-Warning "[env] keep-ui API_URL=$uiApi does not point at the gateway (http://localhost:8080). Every UI request will hit the wrong port."
    }
    # Workflows run as a SEPARATE microservice (:8081). The UI middleware proxies
    # /backend/workflows/* to WORKFLOWS_API_URL, defaulting to :8082 (dead here),
    # so without it the workflows page hangs forever on its loader.
    $uiEnv = Join-Path $Root "keep-ui\.env"
    $uiLocal = Join-Path $Root "keep-ui\.env.local"
    $wfUrl = Get-EnvVal $uiLocal "WORKFLOWS_API_URL"
    if (-not $wfUrl) { $wfUrl = Get-EnvVal $uiEnv "WORKFLOWS_API_URL" }
    if (-not $wfUrl) {
        Add-Content -Path $uiEnv -Value "`nWORKFLOWS_API_URL=http://localhost:8081"
        Write-Warning "[env] keep-ui WORKFLOWS_API_URL was unset - added http://localhost:8081 to keep-ui\.env (workflows service, not the gateway)."
    }
    elseif ($wfUrl -notlike "*:8081*") {
        Write-Warning "[env] keep-ui WORKFLOWS_API_URL=$wfUrl does not point at the workflows service (http://localhost:8081). The workflows page will hang on its loader."
    }
}
Test-ServiceEnv

function Ensure-Deps {
    foreach ($r in @("keep-api-gateway", "keep-event-handler", "keep-workflows")) {
        $cwd = Join-Path $Root $r
        $needs = $Install.IsPresent
        if (-not $needs) {
            Push-Location $cwd
            poetry env info -p *> $null
            if ($LASTEXITCODE -ne 0) { $needs = $true }
            Pop-Location
        }
        if ($needs) { Write-Host "[deps] poetry install ($r)..."; Push-Location $cwd; poetry install; Pop-Location }
    }
    $ui = Join-Path $Root "keep-ui"
    if ($Install.IsPresent -or -not (Test-Path (Join-Path $ui "node_modules"))) {
        Write-Host "[deps] npm install (keep-ui)..."; Push-Location $ui; npm install; Pop-Location
    }
}
Ensure-Deps

Write-Host "[infra] starting postgres + kafka + redis + pusher..."
docker compose -f $Infra up -d

Write-Host "[infra] waiting for postgres..."
$pgReady = $false
foreach ($i in 1..30) {
    docker compose -f $Infra exec -T postgres pg_isready -U keep *> $null
    if ($LASTEXITCODE -eq 0) { $pgReady = $true; break }
    Start-Sleep -Seconds 2
}
if (-not $pgReady) { throw "Postgres did not become ready in time" }

function Start-Svc {
    param([string]$Name, [string]$Repo, [string]$Exe, [string[]]$ArgList)
    $cwd = Join-Path $Root $Repo
    $out = Join-Path $LogDir "$Name.out.log"
    $err = Join-Path $LogDir "$Name.err.log"

    # Load this service's .env, remembering prior values so shared defaults survive for later services.
    $envPath = Join-Path $cwd ".env"
    $saved = @{}; $setKeys = @()
    if (Test-Path $envPath) {
        foreach ($line in Get-Content $envPath) {
            $t = $line.Trim()
            if (-not $t -or $t.StartsWith("#")) { continue }
            $idx = $t.IndexOf("="); if ($idx -lt 1) { continue }
            $k = $t.Substring(0, $idx).Trim(); $v = $t.Substring($idx + 1).Trim()
            $saved[$k] = [Environment]::GetEnvironmentVariable($k)
            Set-Item -Path "Env:$k" -Value $v
            $setKeys += $k
        }
    }

    $p = Start-Process -FilePath $Exe -ArgumentList $ArgList -WorkingDirectory $cwd `
        -RedirectStandardOutput $out -RedirectStandardError $err -PassThru -WindowStyle Hidden
    Add-Content $PidFile $p.Id

    foreach ($k in $setKeys) {
        if ($null -eq $saved[$k]) { Remove-Item -Path "Env:$k" -ErrorAction SilentlyContinue }
        else { Set-Item -Path "Env:$k" -Value $saved[$k] }
    }
    Write-Host "[$Name] pid $($p.Id) -> $out"
}

# Ports: gateway 8080, workflows 8081, event-handler health 8092 (from its .env), UI 3000.
Start-Svc "api-gateway" "keep-api-gateway" "poetry" `
    @("run","gunicorn","src.main:get_app","--bind","0.0.0.0:8080","--workers","1","-k","uvicorn.workers.UvicornWorker","-c","src/config/config.py")
Start-Svc "event-handler" "keep-event-handler" "poetry" @("run","python","-m","src.consumer_main")
Start-Svc "workflows" "keep-workflows" "poetry" `
    @("run","gunicorn","src.main:app","-w","4","-k","uvicorn.workers.UvicornWorker","--bind","0.0.0.0:8081")
Start-Svc "ui" "keep-ui" "npm.cmd" @("run","dev")

function Wait-Health {
    param([string]$Name, [string]$Url, [int]$Retries = 45)
    Write-Host "[$Name] waiting on $Url ..."
    foreach ($i in 1..$Retries) {
        try {
            $r = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 3
            if ($r.StatusCode -ge 200 -and $r.StatusCode -lt 500) { Write-Host "[$Name] healthy"; return $true }
        } catch {}
        Start-Sleep -Seconds 2
    }
    Write-Warning "[$Name] never became healthy — check $LogDir\$Name.err.log"
    return $false
}

$allOk = $true
$allOk = (Wait-Health "api-gateway"   "http://localhost:8080/healthcheck") -and $allOk
$allOk = (Wait-Health "workflows"     "http://localhost:8081/healthcheck") -and $allOk
$allOk = (Wait-Health "event-handler" "http://localhost:8092/healthz")     -and $allOk
$allOk = (Wait-Health "ui"            "http://localhost:3000")             -and $allOk

if ($allOk) { Write-Host "`nAll services up. UI: http://localhost:3000" }
else { Write-Warning "`nSome services failed — inspect $LogDir before running checks." }
