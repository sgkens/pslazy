# Private/CommandHandler.ps1

function Install-CommandNotFoundHandler {
    $ExecutionContext.InvokeCommand.CommandNotFoundAction = {
        param($commandName, $commandLookupEventArgs)

        if (-not $script:LazyRegistry.ContainsKey($commandName)) { return }

        $entryKey = $script:LazyRegistry[$commandName]
        $entry    = $script:LazyEntries[$entryKey]

        if (-not $entry) { return }

        if (-not $script:LoadedModules.ContainsKey($entryKey)) {
            Write-PSLazyLog -Level act `
                -Message "Lazy loading module: $($entry.Name)  source: $($entry.Source)" `
                -Context 'lazy-load'

            try {
                Import-Module $entry.Source -Global -ErrorAction Stop
                $script:LoadedModules[$entryKey] = $true

                Write-PSLazyLog -Level suc `
                    -Message "Loaded '$($entry.Name)' successfully." `
                    -Context 'lazy-load'

                if ($entry.OutputExported) {
                    Format-ExportedCommands -ModulePath $entry.Source
                }
            } catch {
                Write-PSLazyLog -Level fail `
                    -Message "Failed to load '$($entry.Name)': $_" `
                    -Context 'lazy-load'
                return
            }
        }

        $resolved = $ExecutionContext.InvokeCommand.GetCommand(
            $commandName,
            [System.Management.Automation.CommandTypes]::All
        )
        if ($resolved) {
            $commandLookupEventArgs.Command    = $resolved
            $commandLookupEventArgs.StopSearch = $true
        }
    }
}