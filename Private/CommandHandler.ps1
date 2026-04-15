# Private/CommandHandler.ps1

function Invoke-PSLazyLoad {
    [CmdletBinding()]
    param(
        [string]$Command,
        [object[]]$Args
    )

    if (-not $script:LazyRegistry.ContainsKey($Command)) {
        throw "Command '$Command' is not registered in PSLazy."
    }

    $entryKey = $script:LazyRegistry[$Command]
    $entry    = $script:LazyEntries[$entryKey]

    if (-not $entry) {
        throw "Lazy entry for '$entryKey' not found."
    }

    if (-not $script:LoadedModules.ContainsKey($entryKey)) {
        Write-PSLazyLog -Level act `
            -Message "Lazy loading module: $($entry.Name)  source: $($entry.Source)" `
            -Context 'lazy-load'

        try {
            # Check if it is a .ps1 script that needs dot-sourcing
            if ($entry.Source -match '\.ps1$') {
                . $entry.Source
            } else {
                Import-Module $entry.Source -Global -ErrorAction Stop
            }
            
            $script:LoadedModules[$entryKey] = $true

            Write-PSLazyLog -Level suc `
                -Message "Loaded '$($entry.Name)' successfully." `
                -Context 'lazy-load'

            # Remove the proxy functions for all commands in this module
            # This ensures that the newly loaded real functions/cmdlets are used.
            $commandsToRemove = $script:LazyRegistry.Keys | Where-Object { $script:LazyRegistry[$_] -eq $entryKey }
            foreach ($cmdToRemove in $commandsToRemove) {
                if (Get-Content "function:global:$cmdToRemove" -ErrorAction SilentlyContinue | Select-String "Invoke-PSLazyLoad" -Quiet) {
                    Remove-Item "function:global:$cmdToRemove" -ErrorAction SilentlyContinue
                }
            }

            if ($entry.OutputExported) {
                Format-ExportedCommands -ModulePath $entry.Source
            }
            
            # Remove the proxy functions since the real ones are now loaded
            # This prevents recursive calls if the real command is also a function
            # and is now in a higher precedence scope.
            # Actually, the real function will shadow the proxy if it's in global scope.
        } catch {
            Write-PSLazyLog -Level fail `
                -Message "Failed to load '$($entry.Name)': $_" `
                -Context 'lazy-load'
            throw $_
        }
    }

    # Execute the real command
    if ($Command) {
        & $Command @Args
    }
}

function Install-CommandNotFoundHandler {
    $ExecutionContext.InvokeCommand.CommandNotFoundAction = {
        param($commandName, $commandLookupEventArgs)

        if (-not $script:LazyRegistry.ContainsKey($commandName)) { return }

        # Use the centralized loader
        try {
            Invoke-PSLazyLoad -Command $commandName
            
            $resolved = $ExecutionContext.InvokeCommand.GetCommand(
                $commandName,
                [System.Management.Automation.CommandTypes]::All
            )
            if ($resolved) {
                $commandLookupEventArgs.Command    = $resolved
                $commandLookupEventArgs.StopSearch = $true
            }
        } catch {
            # Error already logged in Invoke-PSLazyLoad
        }
    }
}