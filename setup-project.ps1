#Requires -Version 5.1
<#
.SYNOPSIS
    Sets up a new project with Claude Code configuration from a template variant.

.DESCRIPTION
    Copies template files (CLAUDE.md, CLAUDE.local.md, AGENT_TEAM.md, PROJECT_STATE.md,
    .claude/, .editorconfig, gitignore) to a target project directory and replaces
    {{PLACEHOLDER}} tokens with provided values.

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
    [string]$WorktreeBase,
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

# Always replaced
$replacements['{{PROJECT_NAME}}'] = $ProjectName
$replacements['{{PROJECT_NAME_LOWER}}'] = $ProjectName.ToLower()

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
    $replacements['{{BUILD_COMMAND}}'] = "dotnet build $SolutionFile"
    $replacements['{{TEST_COMMAND}}']  = "dotnet test"
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
        $replacements['{{BUILD_COMMAND}}'] = "poetry run pytest"
        $replacements['{{TEST_COMMAND}}']  = "poetry run pytest"
        $replacements['{{FORMAT_COMMAND}}'] = "poetry run ruff format ."
        $replacements['{{LINT_COMMAND}}']  = "poetry run ruff check ."
        if (-not $TechStack) {
            $replacements['{{TECH_STACK}}'] = "Python $pyVersion, Poetry"
        }
    }
    elseif ($pyPkgMgr -eq "uv") {
        $replacements['{{BUILD_COMMAND}}'] = "uv run pytest"
        $replacements['{{TEST_COMMAND}}']  = "uv run pytest"
        $replacements['{{FORMAT_COMMAND}}'] = "uv run ruff format ."
        $replacements['{{LINT_COMMAND}}']  = "uv run ruff check ."
        if (-not $TechStack) {
            $replacements['{{TECH_STACK}}'] = "Python $pyVersion, uv"
        }
    }
    else {
        $replacements['{{BUILD_COMMAND}}'] = "python -m pytest"
        $replacements['{{TEST_COMMAND}}']  = "python -m pytest"
        $replacements['{{FORMAT_COMMAND}}'] = "ruff format ."
        $replacements['{{LINT_COMMAND}}']  = "ruff check ."
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
        $replacements['{{BUILD_COMMAND}}'] = "./gradlew build"
        $replacements['{{TEST_COMMAND}}']  = "./gradlew test"
        $replacements['{{FORMAT_COMMAND}}'] = "./gradlew spotlessApply"
        $replacements['{{LINT_COMMAND}}']  = "./gradlew spotlessCheck"
        if (-not $TechStack) {
            $replacements['{{TECH_STACK}}'] = "Java $javaVersion, Spring Boot, Gradle"
        }
    }
    else {
        $replacements['{{BUILD_COMMAND}}'] = "mvn clean verify"
        $replacements['{{TEST_COMMAND}}']  = "mvn test"
        $replacements['{{FORMAT_COMMAND}}'] = "mvn spotless:apply"
        $replacements['{{LINT_COMMAND}}']  = "mvn spotless:check"
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
    foreach ($name in @("CLAUDE.md", "CLAUDE.local.md", "AGENT_TEAM.md", "PROJECT_CONTEXT.md", "PROJECT_STATE.md")) {
        $path = Join-Path $Source $name
        if (Test-Path $path) {
            $files += @{ Source = $path; RelPath = $name; IsGitignore = $false }
        }
    }

    # Code style config files (variant-specific)
    foreach ($styleFile in @(".editorconfig", "rustfmt.toml", ".prettierrc")) {
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

    # Shared hook scripts (from repo root, not template-specific)
    $hooksDir = Join-Path $PSScriptRoot "hooks"
    if (Test-Path $hooksDir) {
        Get-ChildItem -Path $hooksDir -Filter "*.sh" -File | ForEach-Object {
            $relPath = "hooks/$($_.Name)"
            $files += @{ Source = $_.FullName; RelPath = $relPath; IsGitignore = $false }
        }
    }

    return $files
}

$templateFiles = Get-TemplateFiles -Source $TemplateDir

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
                  elseif ($exists -and -not $Force) { "SKIP (exists)" }
                  elseif ($exists -and $Force) { "OVERWRITE" }
                  else { "CREATE" }
        Write-Host "  $($f.RelPath) -> $action"
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
        Write-Host "Project-level .claude/.mcp.json (would be generated):" -ForegroundColor Yellow
        foreach ($line in ($mcpPreview -split "`n")) {
            Write-Host "    $line"
        }
    }
    else {
        Write-Host "Project-level .claude/.mcp.json: (not generated - no entries for this variant/flags)" -ForegroundColor DarkGray
    }

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
            $existingContent = Get-Content -Path $targetFile -Encoding UTF8 -Raw
            $linesToAdd = @()
            foreach ($line in ($sourceContent -split "`n")) {
                $trimmed = $line.Trim()
                if ($trimmed -and -not $trimmed.StartsWith('#') -and $existingContent -notmatch [regex]::Escape($trimmed)) {
                    $linesToAdd += $trimmed
                }
            }
            if ($linesToAdd.Count -gt 0) {
                $appendBlock = "`n`n# Claude Code - machine-specific files`n" + ($linesToAdd -join "`n") + "`n"
                # Apply replacements to the append block
                foreach ($key in $replacements.Keys) {
                    $appendBlock = $appendBlock.Replace($key, $replacements[$key])
                }
                Add-Content -Path $targetFile -Value $appendBlock -Encoding UTF8
                $copiedFiles += "$($f.RelPath) (appended)"
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
        }
        continue
    }

    # Skip existing files unless -Force
    if ((Test-Path $targetFile) -and -not $Force) {
        $skippedFiles += "$($f.RelPath) (exists, use -Force to overwrite)"
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
    Set-Content -Path $targetFile -Value $content -Encoding UTF8 -NoNewline
    $copiedFiles += $f.RelPath

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
$templateHead = & git -C $PSScriptRoot rev-parse --short HEAD 2>$null
if (-not $templateHead) { $templateHead = "unknown" }

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

# --- Generate project-level .claude/.mcp.json if any entries apply ---
$mcpJsonContent = Build-ProjectMcpJson
if ($mcpJsonContent) {
    $mcpJsonPath = Join-Path (Join-Path $TargetDir ".claude") ".mcp.json"
    if ((Test-Path $mcpJsonPath) -and -not $Force) {
        Write-Host "  [-] .claude/.mcp.json (exists, use -Force to overwrite)" -ForegroundColor Yellow
    }
    else {
        $mcpJsonDir = Split-Path $mcpJsonPath -Parent
        if (-not (Test-Path $mcpJsonDir)) {
            New-Item -ItemType Directory -Path $mcpJsonDir -Force | Out-Null
        }
        Set-Content -Path $mcpJsonPath -Value $mcpJsonContent -Encoding UTF8 -NoNewline
        Write-Host "  [+] .claude/.mcp.json (generated)" -ForegroundColor Green
    }
}

# --- Check for remaining placeholders ---
Write-Host ""
$remainingPlaceholders = @()
foreach ($f in $copiedFiles) {
    # Strip suffix like " (appended)" for file path lookup
    $cleanPath = ($f -replace ' \(.*\)$', '')
    $filePath = Join-Path $TargetDir $cleanPath
    if (Test-Path $filePath) {
        $lines = Get-Content -Path $filePath -Encoding UTF8
        $lineNum = 0
        foreach ($line in $lines) {
            $lineNum++
            $found = [regex]::Matches($line, '\{\{[A-Z_]+\}\}')
            foreach ($m in $found) {
                $remainingPlaceholders += [PSCustomObject]@{
                    File        = $cleanPath
                    Line        = $lineNum
                    Placeholder = $m.Value
                }
            }
        }
    }
}

if ($remainingPlaceholders.Count -gt 0) {
    Write-Host "Remaining placeholders to fill manually:" -ForegroundColor Yellow
    $grouped = $remainingPlaceholders | Group-Object Placeholder | Sort-Object Name
    foreach ($group in $grouped) {
        Write-Host "  $($group.Name):" -ForegroundColor DarkYellow
        foreach ($item in $group.Group) {
            Write-Host "    $($item.File):$($item.Line)"
        }
    }
}
else {
    Write-Host "All placeholders replaced." -ForegroundColor Green
}

Write-Host ""
