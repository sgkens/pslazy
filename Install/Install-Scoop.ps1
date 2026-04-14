# Install/Install-Scoop.ps1

function Install-Scoop {
    [CmdletBinding()]
    param()

    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        Write-PSLazyLog -Level inf -Message 'scoop is already installed.' -Context 'bootstrap'
        return
    }

    Write-PSLazyLog -Level act -Message 'Installing scoop...' -Context 'bootstrap'

    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-RestMethod 'https://get.scoop.sh' | Invoke-Expression
        Write-PSLazyLog -Level suc -Message 'scoop installed.' -Context 'bootstrap'
    } catch {
        Write-PSLazyLog -Level fail -Message "scoop install failed: $_" -Context 'bootstrap'
    }
}