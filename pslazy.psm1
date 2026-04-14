# PSLazy.psm1

$script:LazyRegistry  = @{}   # cmd -> registry entry key
$script:LazyEntries   = @{}   # key -> PSLazyEntry
$script:LoadedModules = @{}   # modulePath -> $true

# Dot-source all private then public functions
foreach ($folder in @('Private', 'Public')) {
    $path = Join-Path $PSScriptRoot $folder
    if (Test-Path $path) {
        Get-ChildItem -Path $path -Filter '*.ps1' | ForEach-Object {
            . $_.FullName
        }
    }
}

Install-CommandNotFoundHandler
Write-PSLazyLog -Level inf -Message 'PSLazy initialized.'