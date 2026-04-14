# PSLazy.psm1

$script:LazyModules = @{}
$script:LoadedModules = @{}

function Register-LazyModule {
    <#
    .SYNOPSIS
        Registers a module to be loaded lazily when one of its commands is first called.
    .PARAMETER ModulePath
        The module name (e.g. 'Az') or path to a .psd1 file.
    .EXAMPLE
        Register-LazyModule -ModulePath 'Az'
        Register-LazyModule -ModulePath 'C:\Modules\MyModule\MyModule.psd1'
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, ValueFromPipeline, Position = 0)]
        [string[]]$ModulePath
    )

    process {
        foreach ($path in $ModulePath) {
            $moduleKey = [System.IO.Path]::GetFileNameWithoutExtension($path)

            # Read exported commands from manifest or scan for commands
            $commands = Get-LazyModuleCommands -ModulePath $path

            if ($commands.Count -eq 0) {
                Write-Warning "PSLazy: No exported commands found for '$moduleKey'. It will not be lazy-loaded."
                continue
            }

            foreach ($cmd in $commands) {
                $script:LazyModules[$cmd] = $path
            }

            Write-Verbose "PSLazy: Registered '$moduleKey' with $($commands.Count) commands."
        }
    }
}

function Get-LazyModuleCommands {
    [CmdletBinding()]
    param([string]$ModulePath)

    # Try reading the .psd1 manifest directly (fast, no import needed)
    $resolvedPsd1 = $null

    if ($ModulePath -match '\.psd1$' -and (Test-Path $ModulePath)) {
        $resolvedPsd1 = $ModulePath
    } else {
        # Find module by name in PSModulePath
        $mod = Get-Module -Name $ModulePath -ListAvailable -ErrorAction SilentlyContinue |
            Select-Object -First 1
        if ($mod) {
            $resolvedPsd1 = $mod.Path
        }
    }

    $commands = [System.Collections.Generic.List[string]]::new()

    if ($resolvedPsd1) {
        try {
            $manifest = Import-PowerShellDataFile -Path $resolvedPsd1 -ErrorAction Stop

            # Collect all exported command types
            $keys = @(
                'FunctionsToExport',
                'CmdletsToExport',
                'AliasesToExport'
            )

            foreach ($key in $keys) {
                if ($manifest[$key]) {
                    # Wildcard '*' means we can't know ahead of time — skip pre-registration
                    $exports = $manifest[$key] | Where-Object { $_ -and $_ -ne '*' }
                    $commands.AddRange([string[]]$exports)
                }
            }
        } catch {
            Write-Warning "PSLazy: Failed to read manifest for '$ModulePath': $_"
        }
    }

    return $commands
}

function Initialize-PSLazy {
    <#
    .SYNOPSIS
        Installs the CommandNotFound handler that auto-loads lazy modules.
        Called automatically when PSLazy is imported.
    #>
    $ExecutionContext.InvokeCommand.CommandNotFoundAction = {
        param($commandName, $commandLookupEventArgs)

        if ($script:LazyModules.ContainsKey($commandName)) {
            $modulePath = $script:LazyModules[$commandName]

            if (-not $script:LoadedModules.ContainsKey($modulePath)) {
                Write-Host "PSLazy: Auto-loading module for '$commandName'..." -ForegroundColor DarkGray
                Import-Module $modulePath -Global -ErrorAction Stop
                $script:LoadedModules[$modulePath] = $true
            }

            # Tell PowerShell to re-look up the command
            $commandLookupEventArgs.CommandScriptBlock = {
                & $commandName @args
            }.GetNewClosure()

            $commandLookupEventArgs.StopSearch = $true
        }
    }
}

function Get-LazyModule {
    <#
    .SYNOPSIS
        Lists all registered lazy modules and their commands.
    #>
    $script:LazyModules.GetEnumerator() |
        Select-Object @{N='Command';E={$_.Key}}, @{N='Module';E={$_.Value}} |
        Sort-Object Module, Command
}

function Unregister-LazyModule {
    <#
    .SYNOPSIS
        Removes a module from the lazy-load registry.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$ModulePath
    )

    $keysToRemove = $script:LazyModules.GetEnumerator() |
        Where-Object { $_.Value -eq $ModulePath } |
        Select-Object -ExpandProperty Key

    foreach ($key in $keysToRemove) {
        $script:LazyModules.Remove($key)
    }

    Write-Verbose "PSLazy: Unregistered '$ModulePath'."
}

# Auto-install the handler when module is imported
Initialize-PSLazy