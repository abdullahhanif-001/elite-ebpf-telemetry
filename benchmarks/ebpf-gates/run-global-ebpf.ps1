# run-global-ebpf.ps1 — orchestrate global eBPF verification (local + VPS phases).
param(
    [ValidateSet('inventory','line-audit','code-audit','telemetry','future-holes','holy-grail','aggregate',
                 'xray','tier1-deploy','tier1-runall','tier2-ftrace','tier3-phase','global-local','global-all')]
    [string]$Phase = 'global-local'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$EbpfGates = Join-Path $Root 'benchmarks\ebpf-gates'
$ScxGates = Join-Path $Root 'benchmarks\sched-ext-gates'
Set-Location $Root

function Invoke-Bash([string]$Script) {
    bash $Script
    if ($LASTEXITCODE -ne 0) { throw "Failed: $Script (exit $LASTEXITCODE)" }
}

switch ($Phase) {
    'inventory'      { Invoke-Bash (Join-Path $EbpfGates 'global-ebpf-inventory.sh') }
    'line-audit'     { Invoke-Bash (Join-Path $EbpfGates 'ebpf-line-audit.sh') }
    'code-audit'     { Invoke-Bash (Join-Path $EbpfGates 'code-audit-gate.sh') }
    'telemetry'      { Invoke-Bash (Join-Path $EbpfGates 'telemetry-probe-gate.sh') }
    'future-holes'   { Invoke-Bash (Join-Path $EbpfGates 'ebpf-future-holes.sh') }
    'holy-grail'     { Invoke-Bash (Join-Path $EbpfGates 'scx1202-matrix-verify.sh') }
    'aggregate'      { Invoke-Bash (Join-Path $EbpfGates 'global-ebpf-aggregate.sh') }
    'xray'           { ssh production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src; bash /opt/elite/src/scripts/oneclick/ebpf-xray-real-proof.sh" }
    'tier1-deploy'   { & (Join-Path $ScxGates 'run-vps-flood-safe.ps1') -Phase deploy }
    'tier1-runall'   {
        & (Join-Path $ScxGates 'run-vps-flood-safe.ps1') -Phase deploy
        & (Join-Path $ScxGates 'run-vps-flood-safe.ps1') -Phase recovery
        Start-Sleep -Seconds 60
        & (Join-Path $ScxGates 'run-vps-flood-safe.ps1') -Phase gate
        foreach ($p in @('P1','P2','P3','P4','P5')) {
            Start-Sleep -Seconds 60
            & (Join-Path $ScxGates 'run-vps-flood-safe.ps1') -Phase $p
        }
        Start-Sleep -Seconds 60
        & (Join-Path $ScxGates 'run-vps-flood-safe.ps1') -Phase aggregate
    }
    'tier2-ftrace'   { ssh production-server "bash /opt/elite/src/scripts/server/tier2-ftrace-kernel.sh" }
    'tier3-phase'    {
        param([string]$Name = 'P5b-bpfland')
        ssh production-server "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src FLOOD_SAFE_MODE=0; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-flood-phase.sh $Name"
    }
    'global-local'   {
        Invoke-Bash (Join-Path $EbpfGates 'global-ebpf-inventory.sh')
        Invoke-Bash (Join-Path $EbpfGates 'code-audit-gate.sh')
        Invoke-Bash (Join-Path $EbpfGates 'telemetry-probe-gate.sh')
        Invoke-Bash (Join-Path $EbpfGates 'ebpf-future-holes.sh')
        Invoke-Bash (Join-Path $EbpfGates 'scx1202-matrix-verify.sh')
    }
    'global-all'     {
        & $PSCommandPath -Phase global-local
        & $PSCommandPath -Phase tier1-deploy
        & $PSCommandPath -Phase tier1-runall
        & $PSCommandPath -Phase xray
        & $PSCommandPath -Phase aggregate
    }
}

Write-Host "GLOBAL_EBPF_PHASE_OK phase=$Phase"
