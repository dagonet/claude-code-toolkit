# server/install.ps1 — same contract as install.sh; prints the exe path.
$ErrorActionPreference = "Stop"
$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Venv = Join-Path $Here ".venv"
if (-not (Test-Path $Venv)) { python -m venv $Venv }
$VPy = Join-Path $Venv "Scripts\python.exe"
# Same contract: the pipeline output is the exe path and nothing else. A native
# command's stdout would otherwise join the pipeline that setup-project.ps1
# captures, so pip goes to the host. $ErrorActionPreference does not see native
# exit codes -- check $LASTEXITCODE by hand.
& $VPy -m pip install --quiet --upgrade pip | Out-Host
if ($LASTEXITCODE -ne 0) { throw "install.ps1: pip upgrade failed ($LASTEXITCODE)" }
& $VPy -m pip install --quiet -e "$Here[dev]" | Out-Host
if ($LASTEXITCODE -ne 0) { throw "install.ps1: editable install failed ($LASTEXITCODE)" }
$Exe = Join-Path $Venv "Scripts\mcp-template-sync-tools.exe"
if (-not (Test-Path $Exe)) { throw "install.ps1: expected console script not found at $Exe" }
Write-Output $Exe
