# Public/Register-LazyModule.ps1

function Register-LazyModule {
    <#
    .SYNOPSIS
        Registers a module (or binary) for lazy-loading on first use.
    .PARAMETER Name
        Friendly name for this entry.
    .PARAMETER Source
        Module name, .psd1 path, or binary/package id.
    .PARAMETER Version
        Optional version. If the module is missing, this version will be installed.
    .PARAMETER Dependencies
        Other PSLazy entry names that must be loaded before this module.
    .PARAMETER OutputExported
        When set, prints all exported cmdlets/functions/aliases after first load.
    .PARAMETER PackageId
        Native package identifier (winget id, brew formula, scoop app) used for
        auto-install when the module/binary is not found.
    .PARAMETER Arch
        Supported architectures. Defaults to 'any'. If the current arch is not
        listed, registration will fail with a warning.
    .PARAMETER PSModule
        Treat as a PowerShell Gallery module — auto-install via Install-Module
        if not present.
    .PARAMETER GitRepo
        Git repo URL to clone or pull from.
    .PARAMETER GitBranch
        Branch to clone or pull from. Defaults to 'main'.
    .PARAMETER GitTag
        Tag to checkout. If not set, will checkout the latest commit on the branch.
    .EXAMPLE
        Register-LazyModule -Name 'Pester' -Source 'Pester' -PSModule
        Register-LazyModule -Name 'Az' -Source 'Az' -Version '11.0.0' -PSModule
        Register-LazyModule -Name 'kubectl' -PackageId 'Kubernetes.kubectl' -Arch x64,arm64
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [string]$Name,

        [string]$Source,

        [string]$Version,

        [string[]]$Dependencies,

        [switch]$OutputExported,

        [string]$PackageId,

        [ValidateSet('x64', 'x86', 'arm64', 'arm32', 'any')]
        [string[]]$Arch = @('any'),

        [switch]$PSModule,
        
        [string]$GitRepo,       # e.g. 'https://github.com/user/MyModule'

        [string]$GitBranch = 'main',

        [string]$GitTag,        # e.g. 'v2.1.0' — takes priority over branch

        [switch]$AlwaysPull,    # git pull on every PS session start

        [string]$GitRelease,     # Repo URL — download release archive instead of git clone

        [string]$ReleaseTag,     # Specific tag — omit for latest

        [string]$AssetFilter,    # Wildcard filter e.g. '*-win-x64.zip'

        [string]$Token,          # Auth token for private repos / rate limits

        [switch]$AlwaysFetch     # Re-download on every session start
    )

    $platform = Get-PSLazyPlatform

    # Architecture gate
    if ('any' -notin $Arch -and $platform.Arch -notin $Arch) {
        Write-PSLazyLog -Level fail `
            -Message "Architecture '$($platform.Arch)' not supported for '$Name'. Supported: $($Arch -join ', ')." `
            -Context $Name
        Write-PSLazyLog -Level wrn `
            -Message "Entry '$Name' was NOT registered." `
            -Context $Name
        return
    }

    $entryKey = $Name.ToLower()

    Write-PSLazyLog -Level inf `
        -Message "Initializing lazy module: $Name$(if ($Version) { " v$Version" })$(if ($Source) { "  source: $Source" })" `
        -Context 'register'
    
    # Git repo
    if ($GitRepo) {
        Write-PSLazyLog -Level inf `
            -Message "Initializing lazy module: $Name  source: $GitRepo$(if ($GitTag) { " tag: $GitTag" } elseif ($GitBranch -ne 'main') { " branch: $GitBranch" })" `
            -Context 'register'

        $resolvedSource = Install-FromGitRepo `
            -RepoUrl    $GitRepo   `
            -Name       $Name      `
            -Branch     $GitBranch `
            -Tag        $GitTag    `
            -AlwaysPull:$AlwaysPull

        if (-not $resolvedSource) { return }
    }

    if ($GitRelease) {
        $resolvedSource = Install-FromGitRelease `
            -RepoUrl      $GitRelease   `
            -Name         $Name         `
            -Tag          $ReleaseTag   `
            -AssetFilter  $AssetFilter  `
            -Token        $Token        `
            -AlwaysFetch:$AlwaysFetch

        if (-not $resolvedSource) { return }
    }
    # Resolve source — try to find it, install if missing
    $resolvedSource = $Source

    if ($PSModule) {
        # If a file path is provided, we use it as the source directly without loading it yet.
        if ($resolvedSource -match '\.psd1$' -or $resolvedSource -match '\.psm1$' -or $resolvedSource -match '\.ps1$') {
            if (-not (Test-Path $resolvedSource)) {
                Write-PSLazyLog -Level fail -Message "Source file not found: $resolvedSource" -Context 'register'
                return
            }
            # Source is already a file path, nothing more to do here.
        } else {
            # It's a module name, check if installed, if not, we can either install now or later.
            # Usually for PSModule we might want to ensure it's at least available or mark for auto-install.
            Write-PSLazyLog -Level inf -Message "Checking module $Name from [PSGallery]" -Context 'register'
            $existing = Get-Module -Name $Name -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1
            if (-not $existing) {
                Write-PSLazyLog -Level inf -Message "Module $Name not found. It will be installed on first use." -Context 'register'
                # We'll keep the name as source and let the handler deal with it.
            } else {
                $resolvedSource = $existing.Path
            }
        }
    } elseif ($PackageId -and -not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-PSLazyLog -Level inf -Message "Package $PackageId will be installed on first use if $Name is not found." -Context 'register'
        $resolvedSource = $PackageId
    }

    # Resolve dependencies
    $resolvedDeps = @()
    if ($Dependencies) {
        foreach ($dep in $Dependencies) {
            $depKey = $dep.ToLower()
            if (-not $script:LazyEntries.ContainsKey($depKey)) {
                Write-PSLazyLog -Level wrn `
                    -Message "Dependency '$dep' is not registered in PSLazy yet. Ensure it is registered before '$Name'." `
                    -Context $Name
            }
            $resolvedDeps += $depKey
        }
    }

    # Build the entry object
    $entry = [PSCustomObject]@{
        Name           = $Name
        Source         = $resolvedSource
        Version        = $Version
        Dependencies   = $resolvedDeps
        OutputExported = $OutputExported.IsPresent
        PackageId      = $PackageId
        Arch           = $Arch
        Platform       = $platform
        PSModule       = $PSModule.IsPresent
        Loaded         = $false
    }

    $script:LazyEntries[$entryKey] = $entry

    # Get exported commands for command->entry mapping
    # We now call this for any PSModule or file-based source
    if ($PSModule -or ($resolvedSource -match '\.(psd1|psm1|ps1)$')) {
        $commands = Get-LazyModuleCommands -ModulePath $resolvedSource

        if ($commands.Count -eq 0) {
            Write-PSLazyLog -Level wrn `
                -Message "'$Name' has no discoverable exports via static analysis. Commands won't auto-trigger lazy load unless they are already in the session." `
                -Context $Name
        }

        $dupes = $commands | Where-Object {
            $script:LazyRegistry.ContainsKey($_) -and $script:LazyRegistry[$_] -ne $entryKey
        }
        foreach ($dupe in $dupes) {
            Write-PSLazyLog -Level wrn `
                -Message "Command '$dupe' already registered to '$($script:LazyRegistry[$dupe])' — overwriting with '$Name'." `
                -Context $Name
        }

        $moduleName = $MyInvocation.MyCommand.Module.Name
        foreach ($cmd in $commands) {
            $script:LazyRegistry[$cmd] = $entryKey
            
            # Create proxy function for discovery and tab completion
            # We use a module-qualified call to ensure it can find internal functions.
            $proxySB = [scriptblock]::Create("param([Parameter(ValueFromRemainingArguments)]`$args); & (Get-Module $moduleName) { Invoke-PSLazyLoad -Command '$cmd' -Args `$args }")

            Set-Item "function:global:$cmd" -Value $proxySB -ErrorAction SilentlyContinue
        }

        Write-PSLazyLog -Level suc `
            -Message "Registered '$Name' with $($commands.Count) command(s) and proxies." `
            -Context 'register'
    } else {
        Write-PSLazyLog -Level suc `
            -Message "Registered '$Name' (binary/native — no command mapping)." `
            -Context 'register'
    }
}