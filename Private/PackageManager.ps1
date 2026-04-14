# Private/PackageManager.ps1

function Install-PSLazyDependency {
    <#
        Attempts to install a package via the platform's package manager.
        Handles: winget, scoop, brew, apt, dnf, pacman
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PackageName,

        [string]$Version,

        [Parameter(Mandatory)]
        [hashtable]$Platform
    )

    $pm      = $Platform.PackageManager
    $os      = $Platform.OS
    $arch    = $Platform.Arch

    if (-not $pm) {
        Write-PSLazyLog -Level fail -Message "No supported package manager found on $os/$arch." -Context $PackageName
        Write-PSLazyLog -Level wrn  -Message "Install a package manager: winget/scoop (Windows), brew (macOS/Linux)." -Context 'hint'
        return $false
    }

    Write-PSLazyLog -Level act -Message "Installing '$PackageName' via $pm..." -Context $PackageName

    $success = $false

    switch ($pm) {
        'winget' {
            $args = @('install', '--id', $PackageName, '--silent', '--accept-package-agreements', '--accept-source-agreements')
            if ($Version) { $args += @('--version', $Version) }
            $success = Invoke-NativeCommand -Command 'winget' -Arguments $args
        }
        'scoop' {
            $args = @('install', $PackageName)
            if ($Version) { $args[1] = "$PackageName@$Version" }
            $success = Invoke-NativeCommand -Command 'scoop' -Arguments $args
        }
        'brew' {
            $args = if ($Version) {
                @('install', "$PackageName@$Version")
            } else {
                @('install', $PackageName)
            }
            $success = Invoke-NativeCommand -Command 'brew' -Arguments $args
        }
        'apt' {
            $pkg = if ($Version) { "${PackageName}=${Version}" } else { $PackageName }
            $success = Invoke-NativeCommand -Command 'sudo' -Arguments @('apt-get', 'install', '-y', $pkg)
        }
        'dnf' {
            $pkg = if ($Version) { "${PackageName}-${Version}" } else { $PackageName }
            $success = Invoke-NativeCommand -Command 'sudo' -Arguments @('dnf', 'install', '-y', $pkg)
        }
        'pacman' {
            $success = Invoke-NativeCommand -Command 'sudo' -Arguments @('pacman', '-S', '--noconfirm', $PackageName)
        }
        default {
            Write-PSLazyLog -Level fail -Message "Package manager '$pm' is not supported." -Context $PackageName
        }
    }

    if ($success) {
        Write-PSLazyLog -Level suc -Message "Installed '$PackageName' successfully." -Context $PackageName
    } else {
        Write-PSLazyLog -Level fail -Message "Failed to install '$PackageName'." -Context $PackageName
    }

    return $success
}

function Install-PSModule {
    param(
        [string]$Name,
        [string]$Version
    )

    Write-PSLazyLog -Level act -Message "Installing PS module '$Name' from PSGallery..." -Context $Name
    try {
        $installParams = @{
            Name               = $Name
            Scope              = 'CurrentUser'
            Force              = $true
            AllowClobber       = $true
            ErrorAction        = 'Stop'
        }
        if ($Version) { $installParams.RequiredVersion = $Version }

        Install-Module @installParams
        Write-PSLazyLog -Level suc -Message "PS module '$Name' installed." -Context $Name
        return $true
    } catch {
        Write-PSLazyLog -Level fail -Message "Could not install PS module '$Name': $_" -Context $Name
        return $false
    }
}

function Invoke-NativeCommand {
    param([string]$Command, [string[]]$Arguments)
    try {
        $result = & $Command @Arguments
        return $LASTEXITCODE -eq 0
    } catch {
        return $false
    }
}