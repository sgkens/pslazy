    # Private/Platform.ps1

enum PSLazyArch {
    x64
    x86
    arm64
    arm32
    any
}

function Get-PSLazyPlatform {
    <#
        Returns a hashtable: OS, Arch, PackageManager
    #>
    [OutputType([hashtable])]
    param()

    # OS
    $os = if ($IsWindows -or $env:OS -match 'Windows') { 'windows' }
          elseif ($IsMacOS)  { 'macos'   }
          elseif ($IsLinux)  { 'linux'   }
          else               { 'unknown' }

    # Architecture
    $rawArch = [System.Runtime.InteropServices.RuntimeInformation]::ProcessArchitecture
    $arch = switch ($rawArch) {
        'X64'   { 'x64'   }
        'X86'   { 'x86'   }
        'Arm64' { 'arm64' }
        'Arm'   { 'arm32' }
        default { 'x64'   }
    }

    # Preferred package manager per platform
    $pm = switch ($os) {
        'windows' { Get-WindowsPackageManager }
        'macos'   { Get-MacPackageManager     }
        'linux'   { Get-LinuxPackageManager   }
        default   { $null }
    }

    return @{ OS = $os; Arch = $arch; PackageManager = $pm }
}

function Get-WindowsPackageManager {
    if (Get-Command winget -ErrorAction SilentlyContinue) { return 'winget' }
    if (Get-Command scoop  -ErrorAction SilentlyContinue) { return 'scoop'  }
    return $null
}

function Get-MacPackageManager {
    if (Get-Command brew -ErrorAction SilentlyContinue) { return 'brew' }
    return $null
}

function Get-LinuxPackageManager {
    foreach ($pm in @('brew', 'apt', 'dnf', 'pacman', 'zypper')) {
        if (Get-Command $pm -ErrorAction SilentlyContinue) { return $pm }
    }
    return $null
}