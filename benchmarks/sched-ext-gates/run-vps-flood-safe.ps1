# Safe flood runner for 4 vCPU / 8GB VPS — one SSH command per phase (no mega-run).
# Usage: .\benchmarks\sched-ext-gates\run-vps-flood-safe.ps1 -Phase {recovery|gate|P1|P2|P3|P4|P5|aggregate|runall}

param(
    [ValidateSet('recovery','gate','P1','P2','P3','P4','P4b','P5','P5b-bpfland','P5b-lavd','P5b-rusty','P5b-flash','P5b-rustland','P5b-layered','P6-bpfland','P7-lavd','aggregate','global-aggregate','runall','deploy')]
    [string]$Phase = 'gate'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $Root
$Cooldown = 60

function Invoke-Phase([string]$Name) {
    Write-Host "=== Phase $Name ==="
    ssh -o ConnectTimeout=30 production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_SAFE_MODE=1; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh $Name"
    if ($LASTEXITCODE -ne 0) { throw "Phase $Name failed (exit $LASTEXITCODE)" }
    Write-Host "ssh_ok phase=$Name"
}

switch ($Phase) {
    'deploy' {
        ssh production-server "mkdir -p /opt/elite/src/benchmarks/sched-ext-gates /opt/elite/src/benchmarks/ebpf-gates /opt/elite/src/scripts/server /opt/elite/src/contrib /opt/elite/src/scripts/oneclick/results/our-goal"
        scp -r benchmarks/sched-ext-gates production-server:/opt/elite/src/benchmarks/
        scp -r benchmarks/ebpf-gates production-server:/opt/elite/src/benchmarks/
        scp scripts/server/sched-ext-vps-prep.sh production-server:/opt/elite/src/scripts/server/
        scp scripts/server/tier2-ftrace-kernel.sh production-server:/opt/elite/src/scripts/server/
        scp scripts/server/submit-rt-guard-upstream.sh production-server:/opt/elite/src/scripts/server/
        scp -r contrib/sched-ext production-server:/opt/elite/src/contrib/
        ssh production-server "chmod +x /opt/elite/src/benchmarks/sched-ext-gates/*.sh /opt/elite/src/benchmarks/ebpf-gates/*.sh /opt/elite/src/scripts/server/*.sh"
        Write-Host "DEPLOY_OK"
    }
    'recovery' { Invoke-Phase 'recovery' }
    'gate'     { Invoke-Phase 'gate' }
    'P1'       { Invoke-Phase 'P1' }
    'P2'       { Invoke-Phase 'P2' }
    'P3'       { Invoke-Phase 'P3' }
    'P4'       { Invoke-Phase 'P4' }
    'P4b'      { Invoke-Phase 'P4b' }
    'P5'       { Invoke-Phase 'P5' }
    'P5b-bpfland'  { ssh -o ConnectTimeout=30 production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_SAFE_MODE=0; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh P5b-bpfland" }
    'P5b-lavd'     { ssh -o ConnectTimeout=30 production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_SAFE_MODE=0; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh P5b-lavd" }
    'P5b-rusty'    { ssh -o ConnectTimeout=30 production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_SAFE_MODE=0; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh P5b-rusty" }
    'P5b-flash'    { ssh -o ConnectTimeout=30 production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_SAFE_MODE=0; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh P5b-flash" }
    'P5b-rustland' { ssh -o ConnectTimeout=30 production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_SAFE_MODE=0; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh P5b-rustland" }
    'P5b-layered'  { ssh -o ConnectTimeout=30 production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_SAFE_MODE=0; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh P5b-layered" }
    'P6-bpfland'   { ssh -o ConnectTimeout=30 production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_SAFE_MODE=0; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh P6-bpfland" }
    'P7-lavd'      { ssh -o ConnectTimeout=30 production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_SAFE_MODE=0; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh P7-lavd" }
    'aggregate' {
        ssh production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-flood-aggregate.sh"
        ssh production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src; bash /opt/elite/src/benchmarks/ebpf-gates/scx1202-matrix-verify.sh"
    }
    'global-aggregate' {
        ssh production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src; bash /opt/elite/src/benchmarks/ebpf-gates/global-ebpf-aggregate.sh"
    }
    'runall' {
        & $PSCommandPath -Phase deploy
        & $PSCommandPath -Phase recovery
        Start-Sleep -Seconds $Cooldown
        & $PSCommandPath -Phase gate
        foreach ($p in @('P1','P2','P3','P4','P5')) {
            Start-Sleep -Seconds $Cooldown
            & $PSCommandPath -Phase $p
        }
        Start-Sleep -Seconds $Cooldown
        & $PSCommandPath -Phase aggregate
    }
}
