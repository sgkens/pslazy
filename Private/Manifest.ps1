# Private/Manifest.ps1

function Get-LazyScriptExports {
    param([string]$FilePath)

    if (-not (Test-Path $FilePath)) { return @() }

    try {
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($FilePath, [ref]$null, [ref]$null)
        $functions = $ast.FindAll({ $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)
        
        # Also find aliases if possible? Usually harder via AST as they are often dynamic Set-Alias calls
        # For now, stick to functions as requested.
        return $functions.Name
    } catch {
        Write-PSLazyLog -Level wrn -Message "Failed to parse script '$FilePath' for exports: $_" -Context 'manifest'
        return @()
    }
}

function Get-LazyModuleCommands {
    param([string]$ModulePath)

    $commands = [System.Collections.Generic.List[string]]::new()
    
    if (-not $ModulePath) { return $commands }

    # Tier 1: .psd1 (Manifest)
    if ($ModulePath -match '\.psd1$' -and (Test-Path $ModulePath)) {
        try {
            $manifest = Import-PowerShellDataFile -Path $ModulePath -ErrorAction Stop

            foreach ($key in @('FunctionsToExport', 'CmdletsToExport', 'AliasesToExport')) {
                $exports = $manifest[$key] | Where-Object { $_ -and $_ -ne '*' }
                if ($exports) { $commands.AddRange([string[]]$exports) }
            }
            return $commands
        } catch {
            Write-PSLazyLog -Level wrn -Message "Failed to read manifest '$ModulePath': $_" -Context 'manifest'
        }
    }

    # Tier 2 & 3: .psm1 / .ps1 (Script analysis)
    if ($ModulePath -match '\.psm1$' -or $ModulePath -match '\.ps1$') {
        if (Test-Path $ModulePath) {
            $exports = Get-LazyScriptExports -FilePath $ModulePath
            if ($exports) { $commands.AddRange([string[]]$exports) }
            return $commands
        }
    }

    # Fallback: Try to find module path via Get-Module -ListAvailable
    $resolvedPsd1 = (
        Get-Module -Name $ModulePath -ListAvailable -ErrorAction SilentlyContinue |
        Select-Object -First 1
    )?.Path

    if ($resolvedPsd1) {
        return Get-LazyModuleCommands -ModulePath $resolvedPsd1
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
        Cmdlets   = @($mod.ExportedCommands.Keys)
        Functions = @($mod.ExportedCmdlets.Keys)
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