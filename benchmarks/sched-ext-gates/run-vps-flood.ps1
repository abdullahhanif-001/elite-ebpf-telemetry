# PowerShell runner for rt-guard heavy flood
# Usage: .\benchmarks\sched-ext-gates\run-vps-flood.ps1 [-Phase deploy|build|flood|all]

param(
    [ValidateSet('deploy','build','flood','all')]
    [string]$Phase = 'all'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $Root

function Invoke-Vps([string]$Cmd) {
    ssh production-server $Cmd
}

switch ($Phase) {
    'deploy' {
        ssh production-server "mkdir -p /opt/elite/src/benchmarks/sched-ext-gates /opt/elite/src/scripts/server /opt/elite/src/contrib"
        scp -r benchmarks/sched-ext-gates production-server:/opt/elite/src/benchmarks/
        scp scripts/server/sched-ext-vps-prep.sh production-server:/opt/elite/src/scripts/server/
        scp -r contrib/sched-ext production-server:/opt/elite/src/contrib/
        Invoke-Vps "chmod +x /opt/elite/src/benchmarks/sched-ext-gates/*.sh /opt/elite/src/scripts/server/*.sh"
        Write-Host "DEPLOY_OK"
    }
    'build' {
        Invoke-Vps "export ELITE_SRC=/opt/elite/src; python3 /opt/elite/src/scripts/server/patch-scx-ftrace-bypass.py 2>/dev/null || true; bash /opt/elite/src/scripts/server/sched-ext-vps-prep.sh scx-build 2>&1 | tail -30"
        Invoke-Vps "ls -la /opt/scx/target/release/scx_bpfland /opt/scx/target/release/scx_lavd 2>/dev/null"
        Write-Host "BUILD_OK"
    }
    'flood' {
        Invoke-Vps "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_SOAK_SHORT_SEC=120 FLOOD_SOAK_LONG_SEC=600; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-heavy-flood.sh 2>&1 | tee /tmp/rt-guard-flood.log | tail -60"
    }
    'all' {
        & $PSCommandPath -Phase deploy
        & $PSCommandPath -Phase build
        & $PSCommandPath -Phase flood
    }
}
