#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up a new project with Claude Code configuration from a template variant.

.DESCRIPTION
    Copies template files (CLAUDE.md, CLAUDE.local.md, AGENT_TEAM.md, PROJECT_CONTEXT.md,
    PROJECT_STATE.md, VERIFICATION_PLAYBOOK.md, .claude/, .editorconfig, .gitattributes, gitignore)
    to a target project directory and replaces {{PLACEHOLDER}} tokens with provided values.

    Command flags apply to every variant and always win over a variant-derived default:
    -BuildCmd, -TestCmd, -FormatCmd, -LintCmd, -GateCmd, -WorktreeBase, -LogPath, -DefaultBranch.
    -WrapExistingClaudeMd keeps an existing CLAUDE.md by moving its full content into the
    template's PROJECT-CUSTOM region instead of skipping the file.

.EXAMPLE
    .\setup-project.ps1 -Variant general -ProjectName "MyProject" -RepoUrl "https://github.com/user/myproject"

.EXAMPLE
    .\setup-project.ps1 -Variant dotnet -ProjectName "MyApi" -SolutionFile "MyApi.sln" -RepoUrl "https://github.com/user/myapi"

.EXAMPLE
    .\setup-project.ps1 -Variant dotnet-maui -ProjectName "MyApp" -SolutionFile "MyApp.sln" -DbPath "c:\Users\Me\AppData\Local\MyApp\Data" -DbFilename "myapp.db" -DryRun

.EXAMPLE
    .\setup-project.ps1 -Variant java -ProjectName "MyService" -BuildTool gradle -JavaVersion 21 -RepoUrl "https://github.com/user/myservice"

.EXAMPLE
    .\setup-project.ps1 -Variant python -ProjectName "MyApp" -PackageManager poetry -PythonVersion 3.12 -RepoUrl "https://github.com/user/myapp"
#>

param(
    [Parameter(Mandatory)]
    [ValidateSet("general", "dotnet", "dotnet-maui", "rust-tauri", "java", "python")]
    [string]$Variant,

    [Parameter(Mandatory)]
    [string]$ProjectName,

    [string]$TargetPath = ".",

    [string]$RepoUrl,
    [string]$SolutionFile,
    [string]$DbPath,
    [string]$DbFilename,
    [string]$TechStack,
    # Default, not a constant: -WorktreeBase still wins. Both `if ($WorktreeBase)`
    # sites below (the replacement map and the sync manifest) therefore fire for a
    # default bootstrap. Kept in sync with setup-project.sh's WORKTREE_BASE and
    # with templates/*/gitignore by verify-template-consistency.sh.
    [string]$WorktreeBase = ".claude/worktrees",
    [string]$LogPath,
    [string]$MauiProject,
    [string]$TestProject,

    [ValidateSet("maven", "gradle", "")]
    [string]$BuildTool,
    [string]$JavaVersion,

    [ValidateSet("pip", "poetry", "uv", "")]
    [string]$PackageManager,
    [string]$PythonVersion,

    [string]$McpDevServersPath,
    [string]$SqliteDbPath,

    [string]$BuildCmd,
    [string]$TestCmd,
    [string]$FormatCmd,
    [string]$LintCmd,
    [string]$GateCmd,
    [string]$DefaultBranch,

    [switch]$WrapExistingClaudeMd,
    [switch]$Force,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$CallerCwd = (Get-Location).Path

# --- Resolve paths ---
$TemplateDir = Join-Path (Join-Path $PSScriptRoot "templates") $Variant
$resolved = Resolve-Path -Path $TargetPath -ErrorAction SilentlyContinue
if ($resolved) {
    $TargetDir = $resolved.Path
}
else {
    $TargetDir = [System.IO.Path]::GetFullPath($TargetPath)
}

if (-not (Test-Path $TemplateDir)) {
    Write-Error "Template variant '$Variant' not found at: $TemplateDir"
    return
}

# --- Validate variant-specific parameters ---
$warnings = @()

if ($Variant -in @("dotnet", "dotnet-maui") -and -not $SolutionFile) {
    $warnings += "SolutionFile not provided - {{SOLUTION_FILE}}, {{BUILD_COMMAND}} placeholders will remain"
}

if ($Variant -eq "dotnet-maui") {
    if (-not $DbPath) {
        $warnings += "DbPath not provided - {{DB_DIRECTORY}}, {{DB_PATH}} placeholders will remain"
    }
    if (-not $DbFilename) {
        $warnings += "DbFilename not provided - {{DB_FILENAME}} placeholders will remain"
    }
}

if ($Variant -eq "java") {
    if ($BuildTool -and $BuildTool -notin @("maven", "gradle")) {
        Write-Error "BuildTool must be 'maven' or 'gradle', got: $BuildTool"
        return
    }
}

if ($Variant -eq "python") {
    if ($PackageManager -and $PackageManager -notin @("pip", "poetry", "uv")) {
        Write-Error "PackageManager must be 'pip', 'poetry', or 'uv', got: $PackageManager"
        return
    }
}

if ($Force -and $WrapExistingClaudeMd) {
    Write-Error "-Force and -WrapExistingClaudeMd conflict -- -Force overwrites an existing CLAUDE.md, -WrapExistingClaudeMd preserves it inside the PROJECT-CUSTOM region. Pass one or the other."
    return
}

# --- Default branch: explicit flag, else detected from the target repo, else main ---
#
# The value lands in PROJECT_CONTEXT.md and is read back by the branch-protection
# hooks, so refuse anything that is not a plain ref name.
if ($DefaultBranch) {
    if ($DefaultBranch -notmatch '^[A-Za-z0-9._/-]+$' -or $DefaultBranch.StartsWith('-') -or $DefaultBranch.Contains('..')) {
        Write-Error "DefaultBranch must be a plain ref name (letters, digits, . _ / -), got: $DefaultBranch"
        return
    }
}
else {
    # Detect only when the TARGET ITSELF is a repo root: git walks up, so a target
    # inside someone else's checkout would otherwise inherit that repo's branch.
    #
    # $ErrorActionPreference is 'Stop' for this script, which turns ANY stderr output
    # from a native command into a terminating error -- and git writes to stderr for
    # a missing directory or an unset origin/HEAD, both of which are normal here.
    $detected = ""
    if (Test-Path $TargetDir) {
        $prevEap = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $toplevel = (& git -C $TargetDir rev-parse --show-toplevel 2>$null)
            if ($LASTEXITCODE -eq 0 -and $toplevel) {
                $sameRepo = ([System.IO.Path]::GetFullPath($toplevel).TrimEnd('\', '/') -eq
                             [System.IO.Path]::GetFullPath($TargetDir).TrimEnd('\', '/'))
                if ($sameRepo) {
                    # Prefer the remote's default branch: the branch that happens to be
                    # checked out during bootstrap is often a feature branch, and this
                    # value is what PROJECT_CONTEXT.md declares PROTECTED.
                    $remoteHead = (& git -C $TargetDir symbolic-ref refs/remotes/origin/HEAD 2>$null)
                    if ($LASTEXITCODE -eq 0 -and $remoteHead -and $remoteHead.StartsWith("refs/remotes/origin/")) {
                        $detected = $remoteHead.Substring("refs/remotes/origin/".Length)
                    }
                    else {
                        $current = (& git -C $TargetDir symbolic-ref --short HEAD 2>$null)
                        if ($LASTEXITCODE -eq 0) { $detected = $current }
                    }
                }
            }
        }
        finally { $ErrorActionPreference = $prevEap }
    }
    if ($detected) {
        $DefaultBranch = $detected
        Write-Host "Detected default branch: $DefaultBranch (override with -DefaultBranch)"
    }
    else {
        $DefaultBranch = "main"
    }
}

# --- Resolve relative MCP path flags against caller CWD ---
function Resolve-CallerPath {
    param([string]$Path)
    if (-not $Path) { return $Path }
    if ([System.IO.Path]::IsPathRooted($Path)) { return $Path }
    return (Join-Path $CallerCwd $Path)
}
if ($McpDevServersPath) { $McpDevServersPath = Resolve-CallerPath $McpDevServersPath }
if ($SqliteDbPath)      { $SqliteDbPath      = Resolve-CallerPath $SqliteDbPath }

# Warn if a variant needs -McpDevServersPath but it's missing
if ($Variant -in @("dotnet", "dotnet-maui") -and -not $McpDevServersPath) {
    $warnings += "-McpDevServersPath not set - project-level dotnet-tools MCP entry will be skipped"
}
if ($Variant -eq "rust-tauri" -and -not $McpDevServersPath) {
    $warnings += "-McpDevServersPath not set - project-level rust-tools MCP entry will be skipped"
}

# --- Build placeholder replacement map ---
$replacements = @{}

# Variant-derived default: never overwrites a value an explicit flag already set.
# (A plain hashtable assignment is last-write-wins, which would silently invert the
# precedence against setup-project.sh, where the first substitution wins.)
function Add-Derived {
    param([string]$Key, [string]$Value)
    if (-not $replacements.ContainsKey($Key)) { $replacements[$Key] = $Value }
}

# Always replaced
$replacements['{{PROJECT_NAME}}'] = $ProjectName
$replacements['{{PROJECT_NAME_LOWER}}'] = $ProjectName.ToLower()
$replacements['{{DEFAULT_BRANCH}}'] = $DefaultBranch

# --- Protected branches: bootstrap is the only layer that KNOWS the trunk ---
#
# The template ships the safe literal `- **Protected branches**: main master`.
# Until v2.2.1 it shipped a placeholder, which NOTHING substitutes on a
# /sync-template apply -- so a `develop` repo received a line that read as
# configured, silently resolved to `main master`, and had its trunk unprotected.
# No placeholder is reintroduced: the static default is right for the common
# case, and setup -- which resolved the branch above -- rewrites the line when
# that default would not cover it.
$protectedDefault = 'main master'
$protectedBranches = $protectedDefault
if ($protectedDefault.Split(' ') -notcontains $DefaultBranch) {
    $protectedBranches = $DefaultBranch
}

function Set-ProtectedBranches {
    param([string]$Text)
    if ($protectedBranches -eq $protectedDefault) { return $Text }
    return [regex]::Replace($Text, '(?m)^- \*\*Protected branches\*\*:.*$',
                            "- **Protected branches**: $protectedBranches")
}

# Explicit command flags -- set before any variant-derived default so they win
if ($BuildCmd)  { $replacements['{{BUILD_COMMAND}}']  = $BuildCmd }
if ($TestCmd)   { $replacements['{{TEST_COMMAND}}']   = $TestCmd }
if ($FormatCmd) { $replacements['{{FORMAT_COMMAND}}'] = $FormatCmd }
if ($LintCmd)   { $replacements['{{LINT_COMMAND}}']   = $LintCmd }
if ($GateCmd)   { $replacements['{{GATE_COMMAND}}']   = $GateCmd }

# Replaced if provided
if ($RepoUrl)       { $replacements['{{REPO_URL}}']       = $RepoUrl }
if ($SolutionFile)  { $replacements['{{SOLUTION_FILE}}']  = $SolutionFile }
if ($TechStack)     { $replacements['{{TECH_STACK}}']     = $TechStack }
if ($WorktreeBase)  { $replacements['{{WORKTREE_BASE}}']  = $WorktreeBase }
if ($LogPath)       { $replacements['{{LOG_PATH}}']       = $LogPath }
if ($MauiProject)   { $replacements['{{MAUI_PROJECT}}']   = $MauiProject }
if ($TestProject)   { $replacements['{{TEST_PROJECT}}']   = $TestProject }
if ($DbPath)        { $replacements['{{DB_DIRECTORY}}']   = $DbPath }
if ($DbFilename)    { $replacements['{{DB_FILENAME}}']    = $DbFilename }

# Auto-derived: full DB path
if ($DbPath -and $DbFilename) {
    $replacements['{{DB_PATH}}'] = Join-Path $DbPath $DbFilename
}

# Auto-derived: build/test commands for dotnet variants
if ($Variant -in @("dotnet", "dotnet-maui") -and $SolutionFile) {
    Add-Derived '{{BUILD_COMMAND}}' "dotnet build $SolutionFile"
    Add-Derived '{{TEST_COMMAND}}' "dotnet test"
}

# Auto-derived: build/test commands for rust-tauri variant
if ($Variant -eq "rust-tauri") {
    if (-not $TechStack) {
        $replacements['{{TECH_STACK}}'] = "Tauri v2, Rust, TypeScript, SolidJS, SQLite"
    }
}

# Auto-derived: Python variant placeholders
if ($Variant -eq "python") {
    $pyPkgMgr = if ($PackageManager) { $PackageManager } else { "pip" }
    $pyVersion = if ($PythonVersion) { $PythonVersion } else { "3.12" }
    $replacements['{{PYTHON_VERSION}}'] = $pyVersion

    if ($pyPkgMgr -eq "poetry") {
        Add-Derived '{{BUILD_COMMAND}}' "poetry run pytest"
        Add-Derived '{{TEST_COMMAND}}' "poetry run pytest"
        Add-Derived '{{FORMAT_COMMAND}}' "poetry run ruff format ."
        Add-Derived '{{LINT_COMMAND}}' "poetry run ruff check ."
        Add-Derived '{{GATE_COMMAND}}' "poetry run ruff format --check . && poetry run ruff check . && poetry run pytest"
        if (-not $TechStack) {
            $replacements['{{TECH_STACK}}'] = "Python $pyVersion, Poetry"
        }
    }
    elseif ($pyPkgMgr -eq "uv") {
        Add-Derived '{{BUILD_COMMAND}}' "uv run pytest"
        Add-Derived '{{TEST_COMMAND}}' "uv run pytest"
        Add-Derived '{{FORMAT_COMMAND}}' "uv run ruff format ."
        Add-Derived '{{LINT_COMMAND}}' "uv run ruff check ."
        Add-Derived '{{GATE_COMMAND}}' "uv run ruff format --check . && uv run ruff check . && uv run pytest"
        if (-not $TechStack) {
            $replacements['{{TECH_STACK}}'] = "Python $pyVersion, uv"
        }
    }
    else {
        Add-Derived '{{BUILD_COMMAND}}' "python -m pytest"
        Add-Derived '{{TEST_COMMAND}}' "python -m pytest"
        Add-Derived '{{FORMAT_COMMAND}}' "ruff format ."
        Add-Derived '{{LINT_COMMAND}}' "ruff check ."
        Add-Derived '{{GATE_COMMAND}}' "ruff format --check . && ruff check . && python -m pytest"
        if (-not $TechStack) {
            $replacements['{{TECH_STACK}}'] = "Python $pyVersion, pip"
        }
    }
}

# Auto-derived: Java variant placeholders
if ($Variant -eq "java") {
    $javaBuildTool = if ($BuildTool) { $BuildTool } else { "maven" }
    $javaVersion = if ($JavaVersion) { $JavaVersion } else { "21" }
    $replacements['{{JAVA_VERSION}}'] = $javaVersion

    if ($javaBuildTool -eq "gradle") {
        Add-Derived '{{BUILD_COMMAND}}' "./gradlew build"
        Add-Derived '{{TEST_COMMAND}}' "./gradlew test"
        Add-Derived '{{FORMAT_COMMAND}}' "./gradlew spotlessApply"
        Add-Derived '{{LINT_COMMAND}}' "./gradlew spotlessCheck"
        Add-Derived '{{GATE_COMMAND}}' "./gradlew spotlessCheck build"
        if (-not $TechStack) {
            $replacements['{{TECH_STACK}}'] = "Java $javaVersion, Spring Boot, Gradle"
        }
    }
    else {
        Add-Derived '{{BUILD_COMMAND}}' "mvn clean verify"
        Add-Derived '{{TEST_COMMAND}}' "mvn test"
        Add-Derived '{{FORMAT_COMMAND}}' "mvn spotless:apply"
        Add-Derived '{{LINT_COMMAND}}' "mvn spotless:check"
        Add-Derived '{{GATE_COMMAND}}' "mvn spotless:check clean verify"
        if (-not $TechStack) {
            $replacements['{{TECH_STACK}}'] = "Java $javaVersion, Spring Boot, Maven"
        }
    }
}

# --- SHA-256 hash function ---
function Get-ContentHash {
    param([string]$Content)
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha256.ComputeHash($bytes)
    return ([BitConverter]::ToString($hash) -replace '-', '').ToLower()
}

# --- Build project-level .mcp.json content (returns $null if no entries apply) ---
function Build-ProjectMcpJson {
    $mcpServers = [ordered]@{}

    if ($Variant -in @("dotnet", "dotnet-maui") -and $McpDevServersPath) {
        $mcpServers['dotnet-tools'] = [ordered]@{
            command = ($McpDevServersPath.TrimEnd('\','/') + "/.venv/Scripts/mcp-dotnet-tools.exe")
        }
    }
    if ($Variant -eq "rust-tauri" -and $McpDevServersPath) {
        $mcpServers['rust-tools'] = [ordered]@{
            command = ($McpDevServersPath.TrimEnd('\','/') + "/.venv/Scripts/mcp-rust-tools.exe")
        }
    }
    if ($Variant -in @("dotnet-maui", "rust-tauri")) {
        $mcpServers['windows-mcp'] = [ordered]@{
            command = "uvx"
            args    = @("windows-mcp")
        }
    }
    if ($SqliteDbPath) {
        $mcpServers['sqlite'] = [ordered]@{
            command = "uvx"
            args    = @("mcp-server-sqlite", "--db-path", $SqliteDbPath)
        }
    }

    if ($mcpServers.Count -eq 0) { return $null }

    $wrapper = [ordered]@{ mcpServers = $mcpServers }
    return ($wrapper | ConvertTo-Json -Depth 6)
}

# --- Collect files to copy ---
function Get-TemplateFiles {
    param([string]$Source)
    $files = @()

    # Top-level markdown and config files
    foreach ($name in @("CLAUDE.md", "CLAUDE.local.md", "AGENT_TEAM.md", "PROJECT_CONTEXT.md", "PROJECT_STATE.md", "VERIFICATION_PLAYBOOK.md")) {
        $path = Join-Path $Source $name
        if (Test-Path $path) {
            $files += @{ Source = $path; RelPath = $name; IsGitignore = $false }
        }
    }

    # Code style config files (variant-specific)
    foreach ($styleFile in @(".editorconfig", "rustfmt.toml", ".prettierrc", ".gitattributes")) {
        $stylePath = Join-Path $Source $styleFile
        if (Test-Path $stylePath) {
            $files += @{ Source = $stylePath; RelPath = $styleFile; IsGitignore = $false }
        }
    }

    # gitignore (special handling - copied as .gitignore, appended if exists)
    $gitignore = Join-Path $Source "gitignore"
    if (Test-Path $gitignore) {
        $files += @{ Source = $gitignore; RelPath = ".gitignore"; IsGitignore = $true }
    }

    # .claude/ directory (recursive)
    $claudeDir = Join-Path $Source ".claude"
    if (Test-Path $claudeDir) {
        Get-ChildItem -Path $claudeDir -Recurse -File | ForEach-Object {
            $relPath = $_.FullName.Substring($Source.Length).TrimStart('\', '/')
            $files += @{ Source = $_.FullName; RelPath = $relPath; IsGitignore = $false }
        }
    }

    # Shared hook scripts (from repo root, not template-specific).
    # EVERY file, RECURSIVELY: the gates source hooks/lib/*.sh via $(dirname "$0")/lib/...
    # and fail CLOSED (exit 2) when the lib is missing, so the old non-recursive
    # *.sh copy left a Windows-bootstrapped project unable to commit, push, or merge.
    $hooksDir = Join-Path $PSScriptRoot "hooks"
    if (Test-Path $hooksDir) {
        Get-ChildItem -Path $hooksDir -Recurse -File | ForEach-Object {
            $relPath = "hooks/" + $_.FullName.Substring($hooksDir.Length).TrimStart('\', '/').Replace('\', '/')
            $files += @{ Source = $_.FullName; RelPath = $relPath; IsGitignore = $false }
        }
    }

    return $files
}

$templateFiles = Get-TemplateFiles -Source $TemplateDir

# --- Wrap an existing CLAUDE.md into the template's PROJECT-CUSTOM region ---
#
# Without -WrapExistingClaudeMd an existing CLAUDE.md is skipped outright, so a
# consumer whose file is all hard rules gets none of the template. Wrapping keeps
# every one of their rules -- inside the region sync-template preserves.
function Merge-IntoCustomRegion {
    param([string]$Rendered, [string]$Body)
    $out = New-Object System.Collections.Generic.List[string]
    $inside = $false
    foreach ($line in ($Rendered -split "`n")) {
        if ($line.Contains("<!-- PROJECT-CUSTOM:BEGIN")) {
            $out.Add($line); $out.Add(""); $out.Add($Body.TrimEnd("`r", "`n")); $out.Add("")
            $inside = $true
            continue
        }
        if ($line.Contains("<!-- PROJECT-CUSTOM:END")) { $inside = $false }
        if ($inside) { continue }
        $out.Add($line)
    }
    return ($out -join "`n")
}

function Test-ShouldWrapClaudeMd {
    param([string]$RelPath)
    if ($RelPath -ne "CLAUDE.md") { return $false }
    if (-not $WrapExistingClaudeMd) { return $false }
    if ($Force) { return $false }
    $existing = Join-Path $TargetDir "CLAUDE.md"
    if (-not (Test-Path $existing)) { return $false }
    # Nesting two PROJECT-CUSTOM regions would corrupt sync-template's region logic.
    return -not ((Get-Content -Path $existing -Encoding UTF8 -Raw).Contains("PROJECT-CUSTOM:BEGIN"))
}

# --- .gitignore merge block ---
#
# The rendered lines the merge would append to an EXISTING .gitignore. Shared by
# both modes so the dry-run list is the real run's list. The presence test is a
# WHOLE-LINE match: `/.mcp.json` is a substring of `.claude/.mcp.json`, so a
# substring test skipped the root rule on every upgrade path.
# Returns $null when there is nothing to add.
function Get-GitignoreAppendBlock {
    param([string]$SourceContent, [string]$TargetFile)
    $existingLines = @(Get-Content -Path $TargetFile -Encoding UTF8 | ForEach-Object { $_.Trim() })
    $linesToAdd = @()
    foreach ($line in ($SourceContent -split "`n")) {
        $trimmed = $line.Trim()
        if ($trimmed -and -not $trimmed.StartsWith('#') -and $existingLines -notcontains $trimmed) {
            $linesToAdd += $trimmed
        }
    }
    if ($linesToAdd.Count -eq 0) { return $null }
    $block = "`n`n# Claude Code - machine-specific files`n" + ($linesToAdd -join "`n") + "`n"
    foreach ($key in $replacements.Keys) { $block = $block.Replace($key, $replacements[$key]) }
    return $block
}

function Get-ClaudeMdSkipHint {
    param([string]$RelPath)
    if ($RelPath -ne "CLAUDE.md") { return "" }
    if ($WrapExistingClaudeMd) { return " -- already carries a PROJECT-CUSTOM region, nothing to wrap" }
    return " -- pass -WrapExistingClaudeMd to keep it inside the template's PROJECT-CUSTOM region"
}

# Exact text that would be written for a template file -- used by both modes.
function Get-RenderedContent {
    param($File)
    # An existing .gitignore is merged, not rewritten -- only the append block is written.
    if ($File.IsGitignore -and (Test-Path (Join-Path $TargetDir $File.RelPath))) {
        $block = Get-GitignoreAppendBlock -SourceContent (Get-Content -Path $File.Source -Encoding UTF8 -Raw) `
                                          -TargetFile (Join-Path $TargetDir $File.RelPath)
        if ($null -eq $block) { return "" }
        return $block
    }
    $text = Get-Content -Path $File.Source -Encoding UTF8 -Raw
    foreach ($key in $replacements.Keys) { $text = $text.Replace($key, $replacements[$key]) }
    if ($File.RelPath -eq 'PROJECT_CONTEXT.md') { $text = Set-ProtectedBranches -Text $text }
    if (Test-ShouldWrapClaudeMd $File.RelPath) {
        $existing = Get-Content -Path (Join-Path $TargetDir "CLAUDE.md") -Encoding UTF8 -Raw
        $text = Merge-IntoCustomRegion -Rendered $text -Body $existing
    }
    return $text
}

# --- Remaining-placeholder report ---
#
# Computed over the RENDERED content in memory, so the dry run and the real run
# report the same thing. The old real-run-only version read the written files and
# therefore could not run in dry-run mode at all (that branch returns first).
$script:renderedFiles = @()

function Add-RenderedFile {
    param([string]$RelPath, [string]$Text)
    $script:renderedFiles += [PSCustomObject]@{ RelPath = $RelPath; Text = $Text }
}

function Write-RemainingPlaceholders {
    $remaining = @()
    foreach ($rendered in $script:renderedFiles) {
        $lineNum = 0
        foreach ($line in ($rendered.Text -split "`n")) {
            $lineNum++
            foreach ($m in [regex]::Matches($line, '\{\{[A-Z_]+\}\}')) {
                $remaining += [PSCustomObject]@{
                    File        = $rendered.RelPath
                    Line        = $lineNum
                    Placeholder = $m.Value
                }
            }
        }
    }

    if ($remaining.Count -gt 0) {
        Write-Host "Remaining placeholders to fill manually:" -ForegroundColor Yellow
        foreach ($group in ($remaining | Group-Object Placeholder | Sort-Object Name)) {
            Write-Host "  $($group.Name):" -ForegroundColor DarkYellow
            foreach ($item in $group.Group) {
                Write-Host "    $($item.File):$($item.Line)"
            }
        }
    }
    else {
        Write-Host "All placeholders replaced." -ForegroundColor Green
    }
}

# --- Branch protection, stated in the report ---
#
# A bootstrap that cannot protect the trunk it just configured must SAY so here.
# The hook does warn, but hook stderr never reaches the session transcript, so
# this output is the only channel that actually reaches the person running it.
function Write-BranchProtection {
    $rendered = $script:renderedFiles | Where-Object { $_.RelPath -eq 'PROJECT_CONTEXT.md' }
    if (-not $rendered) {
        Write-Host "Branch protection: PROJECT_CONTEXT.md was NOT written (kept the existing file)." -ForegroundColor Yellow
        Write-Host "  Resolved trunk is '$DefaultBranch' - check its '- **Protected branches**:' line"
        Write-Host "  yourself; a trunk that is not named there is not protected."
        return
    }
    if ($protectedBranches -eq $protectedDefault) {
        Write-Host "Branch protection: $protectedBranches (trunk '$DefaultBranch' is covered)." -ForegroundColor Green
    }
    else {
        Write-Host "Branch protection: $protectedBranches - set from the resolved trunk." -ForegroundColor Yellow
        Write-Host "  main/master are NOT protected in this project; add them to"
        Write-Host "  PROJECT_CONTEXT.md's '- **Protected branches**:' line if you want them."
    }
}

# --- autoMode.environment snippet ---
#
# permissions.autoMode is User/managed scope only: a project cannot ship one,
# which is the right polarity (a hostile repo must not widen its own trust). So
# the script cannot write this anywhere useful -- it prints a line for the user
# to paste into ~/.claude/settings.json, exactly like the legacy .mcp.json
# warning tells the user what to move by hand.
#
# ASCII dashes only: PowerShell 5.1 reads a BOM-less UTF-8 file as ANSI, so an
# em dash in a Write-Host string would reach the user as mojibake.
# v3.0.3 (item 23): this used to print a PER-REPO line naming $TargetDir as THE
# trusted repo. autoMode.environment is USER scope, so such a line makes the
# classifier read every OTHER repository as outside the trust boundary --
# measured as 58 denials across 11 sessions, 50 in one consumer. The entries are
# read from user-level-reference/settings.json at run time so this snippet cannot
# drift from the reference it points at.
#
# ReadAllLines with an explicit UTF8 encoding, never Get-Content: PowerShell 5.1
# reads a BOM-less UTF-8 file as ANSI, and a mojibaked entry pasted into
# settings.json is worse than no entry.
function Write-AutoModeSnippet {
    $ref = Join-Path (Join-Path $PSScriptRoot "user-level-reference") "settings.json"

    Write-Host "autoMode.environment (User/managed scope -- it applies to EVERY project on this" -ForegroundColor Yellow
    Write-Host "machine, so it cannot live in this project and must not name this project):" -ForegroundColor Yellow
    Write-Host ""
    if (Test-Path $ref) {
        $inArray = $false
        foreach ($line in [IO.File]::ReadAllLines($ref, [Text.Encoding]::UTF8)) {
            if (-not $inArray) {
                if ($line -match '"environment"\s*:\s*\[') { $inArray = $true }
                continue
            }
            if ($line -match '^\s*\]') { break }
            Write-Host "  $line"
        }
    }
    else {
        Write-Host "  (user-level-reference/settings.json not found next to this script --"
        Write-Host "   read the entries from the toolkit repo before editing anything.)"
    }
    Write-Host ""
    Write-Host "  Verify these entries are present in permissions.autoMode.environment in"
    Write-Host "  ~/.claude/settings.json. Do NOT append per-project variants: a line naming"
    Write-Host "  one repository as THE trusted repo makes every other repository on this"
    Write-Host "  machine read as outside the trust boundary, and the classifier will then"
    Write-Host "  ask for confirmation on ordinary commands there."
}

# --- DryRun output ---
if ($DryRun) {
    Write-Host ""
    Write-Host "=== DRY RUN ===" -ForegroundColor Cyan
    Write-Host "Variant:    $Variant"
    Write-Host "Project:    $ProjectName"
    Write-Host "Source:     $TemplateDir"
    Write-Host "Target:     $TargetDir"
    Write-Host ""

    Write-Host "Files to copy:" -ForegroundColor Yellow
    foreach ($f in $templateFiles) {
        $targetFile = Join-Path $TargetDir $f.RelPath
        $exists = Test-Path $targetFile
        $action = if ($f.IsGitignore -and $exists) { "APPEND" }
                  elseif (Test-ShouldWrapClaudeMd $f.RelPath) { "WRAP (existing content moves into the PROJECT-CUSTOM region)" }
                  elseif ($exists -and -not $Force) { "SKIP (exists)" + (Get-ClaudeMdSkipHint $f.RelPath) }
                  elseif ($exists -and $Force) { "OVERWRITE" }
                  else { "CREATE" }
        Write-Host "  $($f.RelPath) -> $action"
        # Only files the real run would write contribute to the placeholder report.
        if (-not $action.StartsWith("SKIP")) {
            Add-RenderedFile -RelPath $f.RelPath -Text (Get-RenderedContent -File $f)
        }
    }

    Write-Host ""
    Write-Host "Replacements:" -ForegroundColor Yellow
    foreach ($key in ($replacements.Keys | Sort-Object)) {
        Write-Host "  $key -> $($replacements[$key])"
    }

    if ($warnings.Count -gt 0) {
        Write-Host ""
        Write-Host "Warnings:" -ForegroundColor Yellow
        foreach ($w in $warnings) {
            Write-Host "  [!] $w" -ForegroundColor DarkYellow
        }
    }

    Write-Host ""
    Write-Host "Manifest:" -ForegroundColor Yellow
    Write-Host "  .claude/template-manifest.json will be generated with:"
    Write-Host "    variant: $Variant"
    Write-Host "    templateRepo: $($PSScriptRoot -replace '\\', '/')"
    Write-Host "    placeholders: $($replacements.Count) values"
    Write-Host "    files: $($templateFiles.Where({ -not $_.IsGitignore }).Count) tracked"

    Write-Host ""
    $mcpPreview = Build-ProjectMcpJson
    if ($mcpPreview) {
        Write-Host "Project-level .mcp.json (would be generated at repo root):" -ForegroundColor Yellow
        foreach ($line in ($mcpPreview -split "`n")) {
            Write-Host "    $line"
        }
    }
    else {
        Write-Host "Project-level .mcp.json: (not generated - no entries for this variant/flags)" -ForegroundColor DarkGray
    }

    Write-Host ""
    Write-RemainingPlaceholders
    Write-BranchProtection

    Write-Host ""
    Write-AutoModeSnippet

    Write-Host ""
    Write-Host "=== END DRY RUN ===" -ForegroundColor Cyan
    return
}

# --- Create target directory if needed ---
if (-not (Test-Path $TargetDir)) {
    New-Item -ItemType Directory -Path $TargetDir -Force | Out-Null
    Write-Host "Created target directory: $TargetDir"
}

# --- Copy and process files ---
$copiedFiles = @()
$skippedFiles = @()

# --- Manifest tracking ---
$manifestFiles = @{}
$alwaysModified = @("PROJECT_CONTEXT.md")
$variantCoders = @{
    "dotnet"      = @(".claude/agents/dotnet-coder.md")
    "dotnet-maui" = @(".claude/agents/dotnet-coder.md")
    "rust-tauri"  = @(".claude/agents/rust-coder.md")
    "java"        = @(".claude/agents/java-coder.md")
    "python"      = @(".claude/agents/python-coder.md")
    "general"     = @()
}

foreach ($f in $templateFiles) {
    $targetFile = Join-Path $TargetDir $f.RelPath

    # Special handling for .gitignore (append if exists)
    if ($f.IsGitignore) {
        $sourceContent = Get-Content -Path $f.Source -Encoding UTF8 -Raw
        if (Test-Path $targetFile) {
            # Append entries not already present
            $appendBlock = Get-GitignoreAppendBlock -SourceContent $sourceContent -TargetFile $targetFile
            if ($appendBlock) {
                Add-Content -Path $targetFile -Value $appendBlock -Encoding UTF8
                $copiedFiles += "$($f.RelPath) (appended)"
                Add-RenderedFile -RelPath $f.RelPath -Text $appendBlock
            }
            else {
                $skippedFiles += "$($f.RelPath) (entries already present)"
            }
        }
        else {
            # Create new .gitignore
            $parentDir = Split-Path $targetFile -Parent
            if (-not (Test-Path $parentDir)) {
                New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
            }
            foreach ($key in $replacements.Keys) {
                $sourceContent = $sourceContent.Replace($key, $replacements[$key])
            }
            Set-Content -Path $targetFile -Value $sourceContent -Encoding UTF8 -NoNewline
            $copiedFiles += $f.RelPath
            Add-RenderedFile -RelPath $f.RelPath -Text $sourceContent
        }
        continue
    }

    # Wrap an existing CLAUDE.md instead of skipping it
    if (Test-ShouldWrapClaudeMd $f.RelPath) {
        $rawContent = Get-Content -Path $f.Source -Encoding UTF8 -Raw
        $renderedTemplate = $rawContent
        foreach ($key in $replacements.Keys) { $renderedTemplate = $renderedTemplate.Replace($key, $replacements[$key]) }
        $wrapped = Get-RenderedContent -File $f
        Set-Content -Path $targetFile -Value $wrapped -Encoding UTF8 -NoNewline
        $copiedFiles += "$($f.RelPath) (existing content wrapped into PROJECT-CUSTOM)"
        Add-RenderedFile -RelPath $f.RelPath -Text $wrapped
        $manifestFiles[($f.RelPath -replace '\\', '/')] = @{
            templateHash    = Get-ContentHash $renderedTemplate
            templateRawHash = Get-ContentHash $rawContent
            localHash       = Get-ContentHash $wrapped
            locallyModified = $true
            reason          = "Existing CLAUDE.md wrapped into the PROJECT-CUSTOM region"
        }
        continue
    }

    # Skip existing files unless -Force
    if ((Test-Path $targetFile) -and -not $Force) {
        $skippedFiles += "$($f.RelPath) (exists, use -Force to overwrite)" + (Get-ClaudeMdSkipHint $f.RelPath)
        continue
    }

    # Ensure parent directory exists
    $parentDir = Split-Path $targetFile -Parent
    if (-not (Test-Path $parentDir)) {
        New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
    }

    # Read, replace placeholders, write
    $rawContent = Get-Content -Path $f.Source -Encoding UTF8 -Raw
    $content = $rawContent
    foreach ($key in $replacements.Keys) {
        $content = $content.Replace($key, $replacements[$key])
    }
    # Same rewrite the dry run reports -- this write path does NOT go through
    # Get-RenderedContent, so the transform has to be applied here too or the two
    # modes disagree about the one line that decides whether the trunk is
    # protected. (The .sh half had exactly this bug, caught by a bootstrap test.)
    if ($f.RelPath -eq 'PROJECT_CONTEXT.md') { $content = Set-ProtectedBranches -Text $content }
    Set-Content -Path $targetFile -Value $content -Encoding UTF8 -NoNewline
    $copiedFiles += $f.RelPath
    Add-RenderedFile -RelPath $f.RelPath -Text $content

    # Track for manifest (skip .gitignore — it's merge-only, not a template-owned file)
    if (-not $f.IsGitignore) {
        $relKey = $f.RelPath -replace '\\', '/'
        $isModified = ($relKey -in $alwaysModified) -or ($relKey -in $variantCoders[$Variant])
        $reason = if ($relKey -in $alwaysModified) { "Project-specific config" }
                  elseif ($relKey -in $variantCoders[$Variant]) { "Project-specific agent" }
                  else { $null }
        $replacedHash = Get-ContentHash $content
        $entry = @{
            templateHash    = $replacedHash
            templateRawHash = Get-ContentHash $rawContent
            localHash       = $replacedHash
            locallyModified = $isModified
        }
        if ($reason) { $entry.reason = $reason }
        $manifestFiles[$relKey] = $entry
    }
}

# --- Summary ---
Write-Host ""
Write-Host "=== Setup Complete ===" -ForegroundColor Green
Write-Host "Variant:    $Variant"
Write-Host "Project:    $ProjectName"
Write-Host "Target:     $TargetDir"
Write-Host ""

if ($copiedFiles.Count -gt 0) {
    Write-Host "Copied/Updated:" -ForegroundColor Green
    foreach ($f in $copiedFiles) {
        Write-Host "  [+] $f"
    }
}

if ($skippedFiles.Count -gt 0) {
    Write-Host ""
    Write-Host "Skipped:" -ForegroundColor Yellow
    foreach ($f in $skippedFiles) {
        Write-Host "  [-] $f"
    }
}

if ($warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "Warnings:" -ForegroundColor Yellow
    foreach ($w in $warnings) {
        Write-Host "  [!] $w" -ForegroundColor DarkYellow
    }
}

# --- Generate template manifest ---
# Same $ErrorActionPreference = 'Stop' trap as the default-branch detection above
# (:153-175): a toolkit extracted without .git (e.g. a ZIP download) makes git
# write "not a git repository" to stderr, which under 'Stop' is a terminating
# error -- aborting the script here, after most files are already written but
# before the manifest and the auto-mode snippet, leaves a bootstrap that LOOKS
# complete and can never sync. Guard it the same way: fall back to "unknown".
$templateHead = "unknown"
$prevEapHead = $ErrorActionPreference
$ErrorActionPreference = "Continue"
try {
    $headOut = (& git -C $PSScriptRoot rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $headOut) { $templateHead = $headOut }
}
finally { $ErrorActionPreference = $prevEapHead }

# Build placeholders map (only actually-provided values)
$placeholderMap = [ordered]@{}
$placeholderMap['PROJECT_NAME'] = $ProjectName
$placeholderMap['PROJECT_NAME_LOWER'] = $ProjectName.ToLower()
if ($RepoUrl)      { $placeholderMap['REPO_URL']      = $RepoUrl }
if ($SolutionFile) { $placeholderMap['SOLUTION_FILE']  = $SolutionFile }
if ($TechStack)    { $placeholderMap['TECH_STACK']     = $TechStack }
if ($WorktreeBase) { $placeholderMap['WORKTREE_BASE']  = $WorktreeBase }
if ($LogPath)      { $placeholderMap['LOG_PATH']       = $LogPath }
if ($MauiProject)  { $placeholderMap['MAUI_PROJECT']   = $MauiProject }
if ($TestProject)  { $placeholderMap['TEST_PROJECT']   = $TestProject }
if ($DbPath)       { $placeholderMap['DB_DIRECTORY']   = $DbPath }
if ($DbFilename)   { $placeholderMap['DB_FILENAME']    = $DbFilename }
if ($DbPath -and $DbFilename) { $placeholderMap['DB_PATH'] = Join-Path $DbPath $DbFilename }
if ($Variant -eq "java") {
    $placeholderMap['JAVA_VERSION'] = $replacements['{{JAVA_VERSION}}']
    $placeholderMap['BUILD_COMMAND'] = $replacements['{{BUILD_COMMAND}}']
    $placeholderMap['TEST_COMMAND']  = $replacements['{{TEST_COMMAND}}']
    $placeholderMap['FORMAT_COMMAND'] = $replacements['{{FORMAT_COMMAND}}']
    $placeholderMap['LINT_COMMAND']  = $replacements['{{LINT_COMMAND}}']
}
if ($Variant -eq "python") {
    $placeholderMap['PYTHON_VERSION'] = $replacements['{{PYTHON_VERSION}}']
    $placeholderMap['BUILD_COMMAND'] = $replacements['{{BUILD_COMMAND}}']
    $placeholderMap['TEST_COMMAND']  = $replacements['{{TEST_COMMAND}}']
    $placeholderMap['FORMAT_COMMAND'] = $replacements['{{FORMAT_COMMAND}}']
    $placeholderMap['LINT_COMMAND']  = $replacements['{{LINT_COMMAND}}']
}

# Command values and the default branch, whichever way they were set (explicit flag
# or variant default) -- the manifest must record what was actually substituted.
foreach ($name in @('DEFAULT_BRANCH', 'BUILD_COMMAND', 'TEST_COMMAND', 'FORMAT_COMMAND', 'LINT_COMMAND', 'GATE_COMMAND')) {
    if ($replacements.ContainsKey("{{$name}}")) { $placeholderMap[$name] = $replacements["{{$name}}"] }
}

# Build ordered files map
$orderedFiles = [ordered]@{}
foreach ($key in ($manifestFiles.Keys | Sort-Object)) {
    $orderedFiles[$key] = $manifestFiles[$key]
}

$manifest = [ordered]@{
    version      = 2
    variant      = $Variant
    templateRepo = ($PSScriptRoot -replace '\\', '/')
    lastSynced   = $templateHead
    placeholders = $placeholderMap
    files        = $orderedFiles
}

$manifestJson = $manifest | ConvertTo-Json -Depth 4
$manifestPath = Join-Path (Join-Path $TargetDir ".claude") "template-manifest.json"
$manifestDir  = Split-Path $manifestPath -Parent
if (-not (Test-Path $manifestDir)) {
    New-Item -ItemType Directory -Path $manifestDir -Force | Out-Null
}
Set-Content -Path $manifestPath -Value $manifestJson -Encoding UTF8 -NoNewline
$copiedFiles += ".claude/template-manifest.json"
Write-Host "  [+] .claude/template-manifest.json (generated)" -ForegroundColor Green

# --- Generate project-level .mcp.json if any entries apply ---
#
# MUST be the REPO ROOT. Claude Code reads project-scope MCP servers only from
# <project-root>/.mcp.json; <project>/.claude/.mcp.json is an open upstream
# feature request, not current behaviour. Earlier versions of this script wrote
# the .claude/ path, so those servers never loaded.
$mcpJsonContent = Build-ProjectMcpJson
if ($mcpJsonContent) {
    $mcpJsonPath = Join-Path $TargetDir ".mcp.json"
    $legacyMcpPath = Join-Path (Join-Path $TargetDir ".claude") ".mcp.json"

    if (Test-Path $legacyMcpPath) {
        Write-Host "  [!] .claude/.mcp.json found -- that path is NOT read by Claude Code." -ForegroundColor Yellow
        Write-Host "      Its servers have never loaded. Merge anything you need into .mcp.json, then delete it." -ForegroundColor Yellow
    }

    if ((Test-Path $mcpJsonPath) -and -not $Force) {
        # Never clobber a hand-maintained root file -- several repos already have one.
        Write-Host "  [-] .mcp.json (exists -- left untouched; use -Force to overwrite)" -ForegroundColor Yellow
        $names = ([regex]::Matches($mcpJsonContent, '"([a-zA-Z_-]+)"\s*:\s*\{') | ForEach-Object { $_.Groups[1].Value }) -join ' '
        Write-Host "      Servers this variant would add: $names" -ForegroundColor DarkGray
    }
    else {
        Set-Content -Path $mcpJsonPath -Value $mcpJsonContent -Encoding UTF8 -NoNewline
        Write-Host "  [+] .mcp.json (generated at repo root)" -ForegroundColor Green
    }
}

# --- Check for remaining placeholders ---
Write-Host ""
Write-RemainingPlaceholders
Write-BranchProtection

Write-Host ""
Write-AutoModeSnippet

Write-Host ""
