# PSLazy.psm1

$script:LazyModules = @{}
$script:LoadedModules = @{}

#region Private

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

    if (-not $resolvedPsd1) {
        Write-Warning "PSLazy: Could not locate module '$ModulePath'."
        return $commands
    }

    try {
        $manifest = Import-PowerShellDataFile -Path $resolvedPsd1 -ErrorAction Stop

        foreach ($key in @('FunctionsToExport', 'CmdletsToExport', 'AliasesToExport')) {
            $exports = $manifest[$key] | Where-Object { $_ -and $_ -ne '*' }
            if ($exports) { $commands.AddRange([string[]]$exports) }
        }

        if ($commands.Count -eq 0) {
            Write-Warning "PSLazy: '$ModulePath' exports wildcards or nothing — cannot lazy-register. Load it eagerly instead."
        }
    } catch {
        Write-Warning "PSLazy: Failed to read manifest '$resolvedPsd1': $_"
    }

    return $commands
}

function Install-CommandNotFoundHandler {
    $ExecutionContext.InvokeCommand.CommandNotFoundAction = {
        param($commandName, $commandLookupEventArgs)

        if (-not $script:LazyModules.ContainsKey($commandName)) { return }

        $modulePath = $script:LazyModules[$commandName]

        if (-not $script:LoadedModules.ContainsKey($modulePath)) {
            try {
                Write-Host "PSLazy: Auto-loading '$modulePath' for '$commandName'..." -ForegroundColor DarkGray
                Import-Module $modulePath -Global -ErrorAction Stop
                $script:LoadedModules[$modulePath] = $true
            } catch {
                Write-Error "PSLazy: Failed to load '$modulePath': $_"
                return
            }
        }

        # Re-resolve the now-loaded command
        $resolved = $ExecutionContext.InvokeCommand.GetCommand($commandName, [System.Management.Automation.CommandTypes]::All)
        if ($resolved) {
            $commandLookupEventArgs.Command = $resolved
            $commandLookupEventArgs.StopSearch = $true
        }
    }
}

#endregion

#region Public

function Register-LazyModule {
    <#
    .SYNOPSIS
        Registers a module for lazy-loading when any of its commands are first called.
    .PARAMETER ModulePath
        Module name or path to a .psd1 file.
    .EXAMPLE
        Register-LazyModule 'Pester'
        Register-LazyModule 'C:\Modules\MyModule\MyModule.psd1'
        'Az', 'SqlServer' | Register-LazyModule
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string[]]$ModulePath
    )

    process {
        foreach ($path in $ModulePath) {
            # Prevent double-registration
            if ($script:LoadedModules.ContainsKey($path)) {
                Write-Warning "PSLazy: '$path' is already loaded — skipping."
                continue
            }

            $commands = Get-LazyModuleCommands -ModulePath $path
            if ($commands.Count -eq 0) { continue }

            $dupes = $commands | Where-Object { $script:LazyModules.ContainsKey($_) -and $script:LazyModules[$_] -ne $path }
            foreach ($dupe in $dupes) {
                Write-Warning "PSLazy: Command '$dupe' already registered to '$($script:LazyModules[$dupe])' — overwriting with '$path'."
            }

            foreach ($cmd in $commands) {
                $script:LazyModules[$cmd] = $path
            }

            Write-Verbose "PSLazy: Registered '$path' ($($commands.Count) commands)."
        }
    }
}

function Unregister-LazyModule {
    <#
    .SYNOPSIS
        Removes a module from the lazy-load registry.
    .PARAMETER ModulePath
        Module name or path matching what was passed to Register-LazyModule.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ModulePath
    )

    $keys = @($script:LazyModules.GetEnumerator() |
        Where-Object Value -EQ $ModulePath |
        Select-Object -ExpandProperty Key)

    if ($keys.Count -eq 0) {
        Write-Warning "PSLazy: No registration found for '$ModulePath'."
        return
    }

    foreach ($key in $keys) { $script:LazyModules.Remove($key) }
    Write-Verbose "PSLazy: Unregistered '$ModulePath' ($($keys.Count) commands removed)."
}

function Get-LazyModule {
    <#
    .SYNOPSIS
        Lists all registered lazy modules and their pending/loaded state.
    #>
    [CmdletBinding()]
    param()

    $script:LazyModules.GetEnumerator() |
        Group-Object Value |
        Select-Object `
            @{ N = 'Module';   E = { $_.Name } },
            @{ N = 'Commands'; E = { $_.Count } },
            @{ N = 'Loaded';   E = { $script:LoadedModules.ContainsKey($_.Name) } } |
        Sort-Object Module
}

#endregion

# Install the handler once when PSLazy itself is imported
Install-CommandNotFoundHandler