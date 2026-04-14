# Private/Git.ps1

function Install-FromGitRepo {
    <#
        Clones or pulls a git repo into the PSLazy module root.
        Returns the path to the .psd1 or .psm1 if found, else the repo root.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoUrl,

        [string]$Name,

        [string]$Branch = 'main',

        [string]$Tag,

        [switch]$AlwaysPull
    )

    # Ensure git exists
    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        Write-PSLazyLog -Level fail -Message 'git is not installed or not in PATH.' -Context 'git'
        Write-PSLazyLog -Level wrn  -Message 'Install git: https://git-scm.com/downloads' -Context 'git'
        return $null
    }

    # Resolve module root per platform
    $moduleRoot = Get-PSLazyModuleRoot

    if (-not (Test-Path $moduleRoot)) {
        New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
        Write-PSLazyLog -Level inf -Message "Created PSLazy module root: $moduleRoot" -Context 'git'
    }

    # Derive folder name from repo URL if no name given
    if (-not $Name) {
        $Name = [System.IO.Path]::GetFileNameWithoutExtension(
            ($RepoUrl -split '/')[-1] -replace '\.git$', ''
        )
    }

    $repoPath = Join-Path $moduleRoot $Name

    # Clone or pull
    if (Test-Path (Join-Path $repoPath '.git')) {
        if ($AlwaysPull) {
            Write-PSLazyLog -Level act -Message "Pulling latest for '$Name'..." -Context 'git'
            $ok = Invoke-GitCommand -Args @('-C', $repoPath, 'pull', '--ff-only') -Context $Name
            if (-not $ok) {
                Write-PSLazyLog -Level wrn -Message "git pull failed for '$Name' — using existing clone." -Context 'git'
            } else {
                Write-PSLazyLog -Level suc -Message "Pulled latest '$Name'." -Context 'git'
            }
        } else {
            Write-PSLazyLog -Level inf -Message "'$Name' already cloned. Use -AlwaysPull to update." -Context 'git'
        }
    } else {
        Write-PSLazyLog -Level act -Message "Cloning '$Name' from $RepoUrl..." -Context 'git'

        $cloneArgs = @('clone', $RepoUrl, $repoPath, '--depth', '1')

        # Branch takes priority; tag overrides both
        if ($Tag) {
            $cloneArgs += @('--branch', $Tag, '--single-branch')
        } elseif ($Branch -ne 'main') {
            $cloneArgs += @('--branch', $Branch, '--single-branch')
        }

        $ok = Invoke-GitCommand -Args $cloneArgs -Context $Name
        if (-not $ok) {
            Write-PSLazyLog -Level fail -Message "Failed to clone '$Name' from $RepoUrl." -Context 'git'
            return $null
        }

        Write-PSLazyLog -Level suc -Message "Cloned '$Name' to $repoPath." -Context 'git'
    }

    # Checkout specific tag post-clone if needed (when repo already existed)
    if ($Tag -and (Test-Path (Join-Path $repoPath '.git'))) {
        Invoke-GitCommand -Args @('-C', $repoPath, 'fetch', '--tags') -Context $Name | Out-Null
        Invoke-GitCommand -Args @('-C', $repoPath, 'checkout', "tags/$Tag", '--detach') -Context $Name | Out-Null
        Write-PSLazyLog -Level inf -Message "Checked out tag '$Tag' for '$Name'." -Context 'git'
    }

    # Resolve the module entry point
    $entryPoint = Resolve-ModuleEntryPoint -RepoPath $repoPath -Name $Name
    if (-not $entryPoint) {
        Write-PSLazyLog -Level wrn `
            -Message "No .psd1 or .psm1 found in '$repoPath'. You may need to set -Source manually." `
            -Context 'git'
        return $repoPath
    }

    Write-PSLazyLog -Level inf -Message "Resolved entry point: $entryPoint" -Context 'git'
    return $entryPoint
}

function Resolve-ModuleEntryPoint {
    <#
        Search priority:
          1. <Name>/<Name>.psd1   (standard module layout)
          2. <Name>.psd1          (flat layout)
          3. <Name>/<Name>.psm1
          4. <Name>.psm1
          5. Any *.psd1 in repo root
          6. Any *.psm1 in repo root
    #>
    param(
        [string]$RepoPath,
        [string]$Name
    )

    $candidates = @(
        (Join-Path $RepoPath "$Name\$Name.psd1"),
        (Join-Path $RepoPath "$Name.psd1"),
        (Join-Path $RepoPath "src\$Name.psd1"),
        (Join-Path $RepoPath "$Name\$Name.psm1"),
        (Join-Path $RepoPath "$Name.psm1"),
        (Join-Path $RepoPath "src\$Name.psm1")
    )

    foreach ($c in $candidates) {
        if (Test-Path $c) { return $c }
    }

    # Fallback — any manifest in the tree
    $found = Get-ChildItem -Path $RepoPath -Filter '*.psd1' -Recurse -Depth 2 |
        Select-Object -First 1
    if ($found) { return $found.FullName }

    $found = Get-ChildItem -Path $RepoPath -Filter '*.psm1' -Recurse -Depth 2 |
        Select-Object -First 1
    if ($found) { return $found.FullName }

    return $null
}

function Get-PSLazyModuleRoot {
    <#
        Returns a consistent, platform-appropriate directory for cloned modules.
        Windows : ~/Documents/PowerShell/PSLazy/Modules
        macOS   : ~/.local/share/powershell/PSLazy/Modules
        Linux   : ~/.local/share/powershell/PSLazy/Modules
    #>
    if ($IsWindows -or $env:OS -match 'Windows') {
        $base = [Environment]::GetFolderPath('MyDocuments')
        return Join-Path $base 'PowerShell\PSLazy\Modules'
    } else {
        return Join-Path $HOME '.local/share/powershell/PSLazy/Modules'
    }
}

function Invoke-GitCommand {
    param(
        [string[]]$Args,
        [string]$Context
    )
    try {
        $output = & git @Args 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-PSLazyLog -Level err -Message "git $($Args -join ' '): $output" -Context $Context
            return $false
        }
        return $true
    } catch {
        Write-PSLazyLog -Level err -Message "git command threw: $_" -Context $Context
        return $false
    }
}