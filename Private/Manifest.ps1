# Private/Manifest.ps1

function Get-LazyModuleCommands {
    param([string]$ModulePath)

    $commands = [System.Collections.Generic.List[string]]::new()
    $resolvedPsd1 = $null

    if ($ModulePath -match '\.psd1$' -and (Test-Path $ModulePath)) {
        $resolvedPsd1 = $ModulePath
    } else {
        $resolvedPsd1 = (
            Get-Module -Name $ModulePath -ListAvailable -ErrorAction SilentlyContinue |
            Select-Object -First 1
        )?.Path
    }

    if (-not $resolvedPsd1) { return $commands }

    try {
        $manifest = Import-PowerShellDataFile -Path $resolvedPsd1 -ErrorAction Stop

        foreach ($key in @('FunctionsToExport', 'CmdletsToExport', 'AliasesToExport')) {
            $exports = $manifest[$key] | Where-Object { $_ -and $_ -ne '*' }
            if ($exports) { $commands.AddRange([string[]]$exports) }
        }
    } catch {
        Write-PSLazyLog -Level wrn -Message "Failed to read manifest '$resolvedPsd1': $_" -Context 'manifest'
    }

    return $commands
}

function Format-ExportedCommands {
    <#
        Outputs a color-coded grouped list of exported commands.
        Called when -OutputExported is set.
    #>
    param([string]$ModulePath)

    $mod = Get-Module -Name ([System.IO.Path]::GetFileNameWithoutExtension($ModulePath)) -ErrorAction SilentlyContinue
    if (-not $mod) {
        $mod = Get-Module -ListAvailable -Name ([System.IO.Path]::GetFileNameWithoutExtension($ModulePath)) |
            Select-Object -First 1
    }
    if (-not $mod) { return }

    $groups = [ordered]@{
        Cmdlets   = @($mod.ExportedCmdlets.Keys)
        Functions = @($mod.ExportedFunctions.Keys)
        Aliases   = @($mod.ExportedAliases.Keys)
    }

    $hasAny = $groups.Values | Where-Object { $_.Count -gt 0 }
    if (-not $hasAny) { return }

    $moduleName = $mod.Name

    # Bold+italic is escape sequence based — works in Windows Terminal / modern hosts
    $esc = [char]27
    $bold   = "$esc[1m"
    $italic = "$esc[3m"
    $reset  = "$esc[0m"

    Write-Host ""
    Write-Host "  ${bold}${italic}$moduleName — Exported Commands${reset}" -ForegroundColor Cyan
    Write-Host "  $('─' * 40)" -ForegroundColor DarkGray

    foreach ($group in $groups.GetEnumerator()) {
        if ($group.Value.Count -eq 0) { continue }

        Write-Host ""
        Write-Host "  ${bold}$($group.Key)${reset}" -ForegroundColor Yellow

        foreach ($cmd in ($group.Value | Sort-Object)) {
            Write-Host "    • " -ForegroundColor DarkGray -NoNewline
            Write-Host $cmd -ForegroundColor White
        }
    }

    Write-Host ""
}