# Install/Install-Winget.ps1
# Run on fresh Windows machines where winget is missing.

function Install-Winget {
    [CmdletBinding()]
    param()

    if (Get-Command winget -ErrorAction SilentlyContinue) {
        Write-PSLazyLog -Level inf -Message 'winget is already installed.' -Context 'bootstrap'
        return
    }

    Write-PSLazyLog -Level act -Message 'Installing winget via App Installer (MSIX)...' -Context 'bootstrap'

    try {
        # Requires Windows 10 1709+ and the Appx module
        $progressPreference = 'SilentlyContinue'
        $releases = Invoke-RestMethod 'https://api.github.com/repos/microsoft/winget-cli/releases/latest'
        $msixUrl  = ($releases.assets | Where-Object name -Match '\.msixbundle$' | Select-Object -First 1).browser_download_url
        $tmp      = Join-Path $env:TEMP 'winget.msixbundle'

        Invoke-WebRequest -Uri $msixUrl -OutFile $tmp -UseBasicParsing
        Add-AppxPackage -Path $tmp

        Write-PSLazyLog -Level suc -Message 'winget installed. Restart your terminal.' -Context 'bootstrap'
    } catch {
        Write-PSLazyLog -Level fail -Message "winget install failed: $_" -Context 'bootstrap'
    }
}