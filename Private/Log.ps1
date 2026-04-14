# Private/Log.ps1

function Write-PSLazyLog {
    <#
        Levels: inf, wrn, err, suc, act, fail
        Format: PSLazy > [LEVEL] message
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('inf', 'wrn', 'err', 'suc', 'act', 'fail')]
        [string]$Level,

        [Parameter(Mandatory)]
        [string]$Message,

        [string]$Context  # e.g. module name or operation
    )

    $levelConfig = @{
        inf  = @{ Label = ' INF '; FG = 'Cyan';    BG = 'DarkCyan'  }
        wrn  = @{ Label = ' WRN '; FG = 'Yellow';  BG = 'DarkYellow'}
        err  = @{ Label = ' ERR '; FG = 'Red';     BG = 'DarkRed'   }
        suc  = @{ Label = ' SUC '; FG = 'Green';   BG = 'DarkGreen' }
        act  = @{ Label = ' ACT '; FG = 'Magenta'; BG = 'DarkMagenta'}
        fail = @{ Label = 'FAIL '; FG = 'White';   BG = 'DarkRed'   }
    }

    $cfg = $levelConfig[$Level]

    # Prefix
    Write-Host 'PSLazy ' -ForegroundColor White -NoNewline
    Write-Host '> ' -ForegroundColor DarkGray -NoNewline

    # Badge
    Write-Host $cfg.Label -ForegroundColor $cfg.FG -BackgroundColor $cfg.BG -NoNewline
    Write-Host ' ' -NoNewline

    # Optional context in accent color
    if ($Context) {
        Write-Host "[$Context] " -ForegroundColor DarkGray -NoNewline
    }

    # Message
    Write-Host $Message -ForegroundColor $cfg.FG

    # Mirror errors to error stream as well
    if ($Level -in 'err', 'fail') {
        Write-Error "PSLazy: $Message" -ErrorAction Continue
    }
}