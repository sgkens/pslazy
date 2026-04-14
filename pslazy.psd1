# PSLazy.psd1

@{
    ModuleVersion     = '1.0.0'
    RootModule        = 'PSLazy.psm1'
    GUID              = 'a1b2c3d4-e5f6-7890-abcd-ef1234567890'
    Author            = 'Garvey K Snow @sgkens'
    CompanyName       = 'Phellams'
    Description       = 'Lazy-load PowerShell modules on first use to speed up shell startup.'
    PowerShellVersion = '5.1'
    FunctionsToExport = @(
        'Register-LazyModule'
        'Get-LazyModule'
        'Unregister-LazyModule'
        'Initialize-PSLazy'
    )
}