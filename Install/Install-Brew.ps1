# Install/Install-Brew.ps1

function Install-Brew {
    [CmdletBinding()]
    param()

    if (Get-Command brew -ErrorAction SilentlyContinue) {
        Write-PSLazyLog -Level inf -Message 'brew is already installed.' -Context 'bootstrap'
        return
    }

    Write-PSLazyLog -Level act -Message 'Installing Homebrew...' -Context 'bootstrap'

    try {
        $script = Invoke-RestMethod 'https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh'
        $tmp    = Join-Path ([System.IO.Path]::GetTempPath()) 'brew-install.sh'
        $script | Set-Content $tmp

        if ($IsMacOS) {
            & bash $tmp
        } elseif ($IsLinux) {
            & bash $tmp
            # Add brew to PATH for Linux
            $brewPath = '/home/linuxbrew/.linuxbrew/bin'
            if (Test-Path $brewPath) {
                $env:PATH = "$brewPath:$env:PATH"
            }
        }

        Write-PSLazyLog -Level suc -Message 'Homebrew installed.' -Context 'bootstrap'
    } catch {
        Write-PSLazyLog -Level fail -Message "brew install failed: $_" -Context 'bootstrap'
    }
}