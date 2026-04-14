# PSLazy.psd1

@{
    ModuleVersion     = '3.0.0'
    RootModule        = 'PSLazy.psm1'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'You'
    Description       = 'Lazy-load PowerShell modules on first use. Cross-platform, dependency-aware, auto-installing.'
    PowerShellVersion = '7.0'
    FunctionsToExport = @(
        'Register-LazyModule'
        'Unregister-LazyModule'
        'Get-LazyModule'
    )
    PrivateData = @{
        PSData = @{ Tags = @('lazy', 'profile', 'performance', 'startup') }
    }
}