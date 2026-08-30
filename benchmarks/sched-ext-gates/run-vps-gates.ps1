# PowerShell VPS gate runner (Windows dev machine)
# Usage: .\benchmarks\sched-ext-gates\run-vps-gates.ps1 [-Phase baseline|connect|repro|pass|prep]

param(
    [ValidateSet('baseline','connect','repro','pass','prep','deploy')]
    [string]$Phase = 'connect'
)

$ErrorActionPreference = 'Stop'
$Root = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
Set-Location $Root

function Invoke-Vps {
    param([string]$Cmd)
    ssh contabo-server $Cmd
}

switch ($Phase) {
    'deploy' {
        ssh contabo-server "mkdir -p /opt/elite/src/benchmarks /opt/elite/src/scripts/contabo /opt/elite/src/contrib"
        scp -r benchmarks/sched-ext-gates contabo-server:/opt/elite/src/benchmarks/
        scp scripts/contabo/sched-ext-vps-prep.sh contabo-server:/opt/elite/src/scripts/contabo/
        scp scripts/contabo/apply-rt-watchdog-patch.sh contabo-server:/opt/elite/src/scripts/contabo/
        scp scripts/contabo/patch-sched-ext-makefile.py contabo-server:/opt/elite/src/scripts/contabo/
        scp -r contrib/sched-ext contabo-server:/opt/elite/src/contrib/
        Invoke-Vps "chmod +x /opt/elite/src/benchmarks/sched-ext-gates/*.sh /opt/elite/src/scripts/contabo/*.sh"
        Write-Host "DEPLOY_OK"
    }
    'baseline' {
        Invoke-Vps @"
hostname=\$(hostname); kernel=\$(uname -r);
k=/boot/config-\$(uname -r);
grep -q '^CONFIG_SCHED_CLASS_EXT=y' \$k 2>/dev/null && echo sched_ext=YES || echo sched_ext=NO;
swapon --show; nproc; free -h | head -2
"@
    }
    'connect' {
        $out = Invoke-Vps @"
hostname=\$(hostname);
k=/boot/config-\$(uname -r);
grep -q '^CONFIG_SCHED_CLASS_EXT=y' \$k && echo sched_ext=YES || echo sched_ext=NO
"@
        Write-Host $out
        if ($out -notmatch 'sched_ext=YES') { throw 'FAIL sched_ext not enabled' }
        Write-Host 'VPS_CONNECT_PASS'
    }
    'prep' {
        Invoke-Vps "export ELITE_SRC=/opt/elite/src REAL_ONLY=1; bash /opt/elite/src/scripts/contabo/sched-ext-vps-prep.sh swap"
        Invoke-Vps "export ELITE_SRC=/opt/elite/src; bash /opt/elite/src/scripts/contabo/sched-ext-vps-prep.sh deps"
    }
    'repro' {
        Invoke-Vps "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-monopolization-repro.sh"
    }
    'pass' {
        Invoke-Vps "export REAL_ONLY=1 ELITE_SRC=/opt/elite/src; bash /opt/elite/src/benchmarks/sched-ext-gates/rt-guard-pass.sh"
    }
}
