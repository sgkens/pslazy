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


# Private/Git.ps1 — add alongside existing functions

function Install-FromGitRelease {
    <#
        Downloads a tagged release archive from GitHub or GitLab.
        Extracts into the PSLazy module root and resolves the entry point.

        Supports:
          - GitHub  : https://github.com/owner/repo
          - GitLab  : https://gitlab.com/owner/repo
          - Gitea   : https://gitea.example.com/owner/repo  (self-hosted)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$RepoUrl,

        [string]$Name,

        # If omitted, resolves to the latest release tag via API
        [string]$Tag,

        # Filter asset filename — useful when a release has multiple assets.
        # Supports wildcards e.g. '*-win-x64.zip'
        # Defaults to the source archive (repo zip) if no assets match.
        [string]$AssetFilter,

        # GitHub/GitLab personal access token for private repos or to avoid rate limits
        [string]$Token,

        [switch]$AlwaysFetch
    )

    if (-not $Name) {
        $Name = [System.IO.Path]::GetFileNameWithoutExtension(
            ($RepoUrl -split '/')[-1] -replace '\.git$', ''
        )
    }

    $moduleRoot = Get-PSLazyModuleRoot
    $destPath   = Join-Path $moduleRoot $Name

    # Already exists and no force-fetch
    if ((Test-Path $destPath) -and -not $AlwaysFetch) {
        Write-PSLazyLog -Level inf `
            -Message "'$Name' already extracted. Use -AlwaysFetch to re-download." `
            -Context 'git-release'

        $entry = Resolve-ModuleEntryPoint -RepoPath $destPath -Name $Name
        return $entry ?? $destPath
    }

    # Detect host
    $host = Resolve-GitHost -RepoUrl $RepoUrl
    if (-not $host) {
        Write-PSLazyLog -Level fail -Message "Unsupported git host for URL: $RepoUrl" -Context 'git-release'
        return $null
    }

    Write-PSLazyLog -Level inf `
        -Message "Detected git host: $($host.Type) — $($host.BaseApi)" `
        -Context 'git-release'

    # Resolve tag
    $resolvedTag = $Tag
    if (-not $resolvedTag) {
        Write-PSLazyLog -Level act -Message "Resolving latest release tag for '$Name'..." -Context 'git-release'
        $resolvedTag = Get-LatestReleaseTag -Host $host -Token $Token
        if (-not $resolvedTag) {
            Write-PSLazyLog -Level fail -Message "Could not resolve latest tag for '$Name'." -Context 'git-release'
            return $null
        }
        Write-PSLazyLog -Level inf -Message "Latest tag: $resolvedTag" -Context 'git-release'
    }

    # Resolve download URL
    $downloadUrl = $null
    $fileName    = $null

    $assets = Get-ReleaseAssets -Host $host -Tag $resolvedTag -Token $Token

    if ($assets -and $AssetFilter) {
        $match = $assets | Where-Object { $_.Name -like $AssetFilter } | Select-Object -First 1
        if ($match) {
            $downloadUrl = $match.Url
            $fileName    = $match.Name
        } else {
            Write-PSLazyLog -Level wrn `
                -Message "No asset matched filter '$AssetFilter'. Falling back to source archive." `
                -Context 'git-release'
        }
    }

    # Fallback — source archive zip
    if (-not $downloadUrl) {
        $downloadUrl = Get-SourceArchiveUrl -Host $host -Tag $resolvedTag
        $fileName    = "$Name-$resolvedTag.zip"
    }

    Write-PSLazyLog -Level act `
        -Message "Downloading '$Name' @ $resolvedTag from $downloadUrl" `
        -Context 'git-release'

    $archivePath = Join-Path ([System.IO.Path]::GetTempPath()) $fileName
    $ok = Invoke-FileDownload -Url $downloadUrl -Destination $archivePath -Token $Token

    if (-not $ok) {
        Write-PSLazyLog -Level fail -Message "Download failed for '$Name'." -Context 'git-release'
        return $null
    }

    Write-PSLazyLog -Level suc -Message "Downloaded '$fileName'." -Context 'git-release'

    # Extract
    if (Test-Path $destPath) {
        Remove-Item $destPath -Recurse -Force
    }

    $ok = Expand-ReleaseArchive -ArchivePath $archivePath -Destination $destPath -Name $Name

    # Cleanup temp
    Remove-Item $archivePath -Force -ErrorAction SilentlyContinue

    if (-not $ok) {
        Write-PSLazyLog -Level fail -Message "Extraction failed for '$Name'." -Context 'git-release'
        return $null
    }

    Write-PSLazyLog -Level suc -Message "Extracted '$Name' to $destPath" -Context 'git-release'

    $entryPoint = Resolve-ModuleEntryPoint -RepoPath $destPath -Name $Name
    if (-not $entryPoint) {
        Write-PSLazyLog -Level wrn `
            -Message "No .psd1 or .psm1 found. You may need -Source pointing into $destPath" `
            -Context 'git-release'
        return $destPath
    }

    Write-PSLazyLog -Level inf -Message "Resolved entry point: $entryPoint" -Context 'git-release'
    return $entryPoint
}

#region Helpers

function Resolve-GitHost {
    param([string]$RepoUrl)

    # Normalise — strip trailing slash and .git
    $url = $RepoUrl.TrimEnd('/') -replace '\.git$', ''

    if ($url -match 'github\.com/(?<owner>[^/]+)/(?<repo>[^/]+)') {
        return @{
            Type    = 'github'
            Owner   = $Matches.owner
            Repo    = $Matches.repo
            BaseApi = 'https://api.github.com'
        }
    }

    if ($url -match 'gitlab\.com/(?<owner>.+)/(?<repo>[^/]+)') {
        $encodedPath = [Uri]::EscapeDataString("$($Matches.owner)/$($Matches.repo)")
        return @{
            Type    = 'gitlab'
            Owner   = $Matches.owner
            Repo    = $Matches.repo
            BaseApi = 'https://gitlab.com/api/v4'
            Encoded = $encodedPath
        }
    }

    # Gitea / self-hosted — heuristic match
    if ($url -match 'https?://(?<base>[^/]+)/(?<owner>[^/]+)/(?<repo>[^/]+)') {
        return @{
            Type    = 'gitea'
            Owner   = $Matches.owner
            Repo    = $Matches.repo
            Base    = $Matches.base
            BaseApi = "https://$($Matches.base)/api/v1"
        }
    }

    return $null
}

function Get-LatestReleaseTag {
    param([hashtable]$Host, [string]$Token)

    $headers = Get-AuthHeaders -Host $Host -Token $Token

    try {
        $response = switch ($Host.Type) {
            'github' {
                Invoke-RestMethod `
                    -Uri     "$($Host.BaseApi)/repos/$($Host.Owner)/$($Host.Repo)/releases/latest" `
                    -Headers $headers `
                    -ErrorAction Stop
            }
            'gitlab' {
                Invoke-RestMethod `
                    -Uri     "$($Host.BaseApi)/projects/$($Host.Encoded)/releases" `
                    -Headers $headers `
                    -ErrorAction Stop |
                    Select-Object -First 1
            }
            'gitea' {
                Invoke-RestMethod `
                    -Uri     "$($Host.BaseApi)/repos/$($Host.Owner)/$($Host.Repo)/releases" `
                    -Headers $headers `
                    -ErrorAction Stop |
                    Select-Object -First 1
            }
        }

        return $response.tag_name
    } catch {
        Write-PSLazyLog -Level err -Message "Tag resolution failed: $_" -Context 'git-release'
        return $null
    }
}

function Get-ReleaseAssets {
    param([hashtable]$Host, [string]$Tag, [string]$Token)

    $headers = Get-AuthHeaders -Host $Host -Token $Token

    try {
        $assets = switch ($Host.Type) {
            'github' {
                $rel = Invoke-RestMethod `
                    -Uri     "$($Host.BaseApi)/repos/$($Host.Owner)/$($Host.Repo)/releases/tags/$Tag" `
                    -Headers $headers `
                    -ErrorAction Stop
                $rel.assets | Select-Object `
                    @{ N = 'Name'; E = { $_.name } },
                    @{ N = 'Url';  E = { $_.browser_download_url } }
            }
            'gitlab' {
                $rel = Invoke-RestMethod `
                    -Uri     "$($Host.BaseApi)/projects/$($Host.Encoded)/releases/$Tag" `
                    -Headers $headers `
                    -ErrorAction Stop
                $rel.assets.links | Select-Object `
                    @{ N = 'Name'; E = { $_.name } },
                    @{ N = 'Url';  E = { $_.url  } }
            }
            'gitea' {
                $rel = Invoke-RestMethod `
                    -Uri     "$($Host.BaseApi)/repos/$($Host.Owner)/$($Host.Repo)/releases/tags/$Tag" `
                    -Headers $headers `
                    -ErrorAction Stop
                $rel.assets | Select-Object `
                    @{ N = 'Name'; E = { $_.name } },
                    @{ N = 'Url';  E = { $_.browser_download_url } }
            }
        }
        return $assets
    } catch {
        Write-PSLazyLog -Level wrn -Message "Could not fetch release assets: $_" -Context 'git-release'
        return $null
    }
}

function Get-SourceArchiveUrl {
    param([hashtable]$Host, [string]$Tag)
    [string]$SourceArchiveUrl = switch ($Host.Type) {
        'github' { "https://github.com/$($Host.Owner)/$($Host.Repo)/archive/refs/tags/$Tag.zip" }
        'gitlab' { "https://gitlab.com/$($Host.Owner)/$($Host.Repo)/-/archive/$Tag/$($Host.Repo)-$Tag.zip" }
        'gitea'  { "https://$($Host.Base)/$($Host.Owner)/$($Host.Repo)/archive/$Tag.zip" }
    }
    return $SourceArchiveUrl
}

function Get-AuthHeaders {
    param([hashtable]$Host, [string]$Token)

    $headers = @{ 'User-Agent' = 'PSLazy' }

    if ($Token) {
        $headers['Authorization'] = switch ($Host.Type) {
            'github' { "Bearer $Token" }
            'gitlab' { "PRIVATE-TOKEN $Token" }
            'gitea'  { "token $Token"   }
        }
    }

    return $headers
}

function Invoke-FileDownload {
    param([string]$Url, [string]$Destination, [string]$Token)

    try {
        $headers = @{ 'User-Agent' = 'PSLazy' }
        if ($Token) { $headers['Authorization'] = "Bearer $Token" }

        Invoke-WebRequest -Uri $Url -OutFile $Destination -Headers $headers -UseBasicParsing -ErrorAction Stop
        return $true
    } catch {
        Write-PSLazyLog -Level err -Message "Download error: $_" -Context 'git-release'
        return $false
    }
}

function Expand-ReleaseArchive {
    param([string]$ArchivePath, [string]$Destination, [string]$Name)

    try {
        $ext = [System.IO.Path]::GetExtension($ArchivePath).ToLower()
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) "pslazy-extract-$Name"

        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }

        if ($ext -eq '.zip') {
            Expand-Archive -Path $ArchivePath -DestinationPath $tmp -Force
        } elseif ($ext -in '.gz', '.tgz') {
            # tar is available on Windows 10 1803+, macOS, Linux
            if (-not (Get-Command tar -ErrorAction SilentlyContinue)) {
                Write-PSLazyLog -Level fail -Message 'tar is required for .tar.gz extraction.' -Context 'git-release'
                return $false
            }
            New-Item -ItemType Directory -Path $tmp -Force | Out-Null
            & tar -xzf $ArchivePath -C $tmp
            if ($LASTEXITCODE -ne 0) { return $false }
        } else {
            Write-PSLazyLog -Level fail -Message "Unsupported archive format: $ext" -Context 'git-release'
            return $false
        }

        # GitHub/GitLab wrap content in a root folder — unwrap it
        $children = Get-ChildItem $tmp
        if ($children.Count -eq 1 -and $children[0].PSIsContainer) {
            Move-Item $children[0].FullName $Destination
        } else {
            Move-Item $tmp $Destination
        }

        if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
        return $true
    } catch {
        Write-PSLazyLog -Level err -Message "Extraction error: $_" -Context 'git-release'
        return $false
    }
}
