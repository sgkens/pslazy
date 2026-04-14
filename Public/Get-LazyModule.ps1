    # Public/Get-LazyModule.ps1

function Get-LazyModule {
    <#
    .SYNOPSIS
        Lists all registered PSLazy entries and their state.
    #>
    [CmdletBinding()]
    param()

    if ($script:LazyEntries.Count -eq 0) {
        Write-PSLazyLog -Level wrn -Message 'No modules registered.' -Context 'registry'
        return
    }

    $script:LazyEntries.GetEnumerator() | ForEach-Object {
        $e = $_.Value
        [PSCustomObject]@{
            Name         = $e.Name
            Version      = $e.Version ?? '(any)'
            Source       = $e.Source
            Loaded       = $script:LoadedModules.ContainsKey($_.Key)
            Dependencies = $e.Dependencies -join ', '
            Arch         = $e.Arch -join ', '
            Platform     = $e.Platform.OS
            PSModule     = $e.PSModule
        }
    } | Sort-Object Name | Format-Table -AutoSize
}