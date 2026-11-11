#Requires -Version 5.1
<#
.SYNOPSIS
Updates an existing EllesmereUI installation from this checkout.
.DESCRIPTION
Copies only changed or missing files. Lua, TOC, XML and TXT comparisons ignore
CRLF versus LF line endings; other files are compared by SHA-256. Unchanged
destination files keep their timestamps. Nothing is deleted, including
installed libraries and files removed from the checkout.

Module destinations and exclusions come from .pkgmeta. This does not fetch
external libraries: install a packaged release before using this script.
.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .tools/deploy.ps1 -WhatIf
.EXAMPLE
powershell -NoProfile -ExecutionPolicy Bypass -File .tools/deploy.ps1
.EXAMPLE
& .\.tools\deploy.ps1 -AddOnsPath 'D:\Games\WoW\_forever_\Interface\AddOns'
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [ValidateNotNullOrEmpty()]
    [string]$AddOnsPath = 'C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
$destinationRoot = (Get-Item -LiteralPath $AddOnsPath).FullName
if (-not (Test-Path -LiteralPath (Join-Path $destinationRoot 'EllesmereUI\EllesmereUI.toc') -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $destinationRoot 'EllesmereUI\Libs') -PathType Container)) {
    throw 'Install a packaged EllesmereUI release (including Libs) in AddOnsPath first.'
}
if ($destinationRoot.TrimEnd('\') -eq $repo.TrimEnd('\') -or
    $repo.StartsWith($destinationRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
    throw 'AddOnsPath must not contain the source checkout.'
}

$modules = [ordered]@{}
$ignored = @()
$section = ''
foreach ($line in Get-Content -LiteralPath (Join-Path $repo '.pkgmeta')) {
    if ($line -match '^(\w[\w-]*):') {
        $section = $Matches[1]
    } elseif ($section -eq 'move-folders' -and $line -match '^  EllesmereUI/(\w+): (\w+)\s*$') {
        $modules[$Matches[1]] = $Matches[2]
    } elseif ($section -eq 'ignore' -and $line -match '^  - (\S+)\s*$') {
        $ignored += $Matches[1].Replace('/', '\')
    }
}
if ($modules.Count -eq 0) { throw 'No module mappings found in .pkgmeta.' }

function Test-Ignored([string]$RelativePath) {
    foreach ($entry in $ignored) {
        if ($RelativePath -eq $entry -or
            $RelativePath.StartsWith($entry.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
            return $true
        }
    }
    return $false
}

function Get-ContentHash([string]$Path) {
    $hasher = [Security.Cryptography.SHA256]::Create()
    try {
        $stream = [IO.File]::OpenRead($Path)
        try { return [BitConverter]::ToString($hasher.ComputeHash($stream)) }
        finally { $stream.Dispose() }
    } finally { $hasher.Dispose() }
}

function Test-SameContent([IO.FileInfo]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Destination -PathType Leaf)) { return $false }
    if ($Source.Extension -in '.lua', '.toc', '.xml', '.txt') {
        $sourceText = [IO.File]::ReadAllText($Source.FullName).Replace("`r`n", "`n")
        $destinationText = [IO.File]::ReadAllText($Destination).Replace("`r`n", "`n")
        return [string]::Equals($sourceText, $destinationText, [StringComparison]::Ordinal)
    }
    if ($Source.Length -ne (Get-Item -LiteralPath $Destination).Length) { return $false }
    return (Get-ContentHash $Source.FullName) -eq (Get-ContentHash $Destination)
}

$files = @(Get-ChildItem -LiteralPath $repo -File | Where-Object {
    $_.Extension -in '.lua', '.toc', '.xml' -or $_.Name -eq 'license.txt'
})
foreach ($directory in @('media') + @($modules.Keys)) {
    $files += Get-ChildItem -LiteralPath (Join-Path $repo $directory) -Recurse -File
}

# Build the entire plan before writing anything.
$changes = @()
$unchanged = 0
foreach ($file in $files) {
    $relative = $file.FullName.Substring($repo.Length + 1)
    if (Test-Ignored $relative) { continue }
    $parts = $relative -split '\\', 2
    if ($modules.Contains($parts[0])) {
        $targetRelative = Join-Path $modules[$parts[0]] $parts[1]
    } else {
        $targetRelative = Join-Path 'EllesmereUI' $relative
    }
    $destination = Join-Path $destinationRoot $targetRelative
    if (Test-SameContent $file $destination) {
        $unchanged++
    } else {
        $changes += [pscustomobject]@{ Source = $file.FullName; Destination = $destination }
    }
}

$copied = 0
foreach ($change in $changes) {
    if ($PSCmdlet.ShouldProcess($change.Destination, 'Copy changed or missing file')) {
        [IO.Directory]::CreateDirectory((Split-Path -Parent $change.Destination)) | Out-Null
        Copy-Item -LiteralPath $change.Source -Destination $change.Destination -Force
        $copied++
    }
}
Write-Host ("Unchanged: {0}; changed or missing: {1}; copied: {2}." -f $unchanged, $changes.Count, $copied)
if ($copied -gt 0) { Write-Host 'Deployment complete. Use /reload in WoW to load code changes.' }
