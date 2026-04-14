# Public/Unregister-LazyModule.ps1

function Unregister-LazyModule {
    <#
    .SYNOPSIS
        Removes a module from the PSLazy registry.
    .PARAMETER Name
        The name used when registering with Register-LazyModule.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name
    )

    $entryKey = $Name.ToLower()

    if (-not $script:LazyEntries.ContainsKey($entryKey)) {
        Write-PSLazyLog -Level wrn -Message "No entry found for '$Name'." -Context 'unregister'
        return
    }

    $cmdKeys = @($script:LazyRegistry.GetEnumerator() |
        Where-Object Value -EQ $entryKey |
        Select-Object -ExpandProperty Key)

    foreach ($key in $cmdKeys) { $script:LazyRegistry.Remove($key) }

    $script:LazyEntries.Remove($entryKey)
    $script:LoadedModules.Remove($entryKey)

    Write-PSLazyLog -Level suc `
        -Message "Unregistered '$Name' ($($cmdKeys.Count) commands removed)." `
        -Context 'unregister'
}