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

        [switch]$PSModule
        
        [string]$GitRepo,       # e.g. 'https://github.com/user/MyModule'

        [string]$GitBranch = 'main',

        [string]$GitTag,        # e.g. 'v2.1.0' — takes priority over branch

        [switch]$AlwaysPull     # git pull on every PS session start
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

    # Resolve source — try to find it, install if missing
    $resolvedSource = $Source

    if ($PSModule) {
        $existing = Get-Module -Name $Name -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1
        if (-not $existing) {
            $installed = Install-PSModule -Name $Name -Version $Version
            if (-not $installed) { return }
            $existing = Get-Module -Name $Name -ListAvailable -ErrorAction SilentlyContinue | Select-Object -First 1
        }
        $resolvedSource = if ($existing) { $existing.Path } else { $Name }
    } elseif ($PackageId -and -not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        $installed = Install-PSLazyDependency -PackageName $PackageId -Version $Version -Platform $platform
        if (-not $installed) { return }
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
    if ($PSModule -or ($resolvedSource -match '\.psd1$') -or (Get-Module -Name $Name -ListAvailable -ErrorAction SilentlyContinue)) {
        $commands = Get-LazyModuleCommands -ModulePath $resolvedSource

        if ($commands.Count -eq 0) {
            Write-PSLazyLog -Level wrn `
                -Message "'$Name' has no discoverable exports (wildcard or binary). Commands won't auto-trigger lazy load." `
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

        foreach ($cmd in $commands) {
            $script:LazyRegistry[$cmd] = $entryKey
        }

        Write-PSLazyLog -Level suc `
            -Message "Registered '$Name' with $($commands.Count) command(s)." `
            -Context 'register'
    } else {
        Write-PSLazyLog -Level suc `
            -Message "Registered '$Name' (binary/native — no command mapping)." `
            -Context 'register'
    }
}