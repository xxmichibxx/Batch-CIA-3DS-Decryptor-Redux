param(
    [string]$Root = ".",
    [string]$OutDir = ".\_cxi_out",
    [string]$ProjectRoot = ".",
    [ValidateSet("CXI", "CCI", "Both")]
    [string]$Mode = "CXI",
    [ValidateSet("CIA", "CIA3DS", "All")]
    [string]$InputType = "CIA",
    [switch]$Recurse,
    [switch]$Force,
    [switch]$KeepWork,
    [switch]$KeepNcch,
    [switch]$KeepInstallCia,
    [switch]$ReportCsv,
    [int]$MaxScanMB = 96
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# UTF-8 console / pipeline compatibility
try {
    [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $OutputEncoding = [Console]::OutputEncoding
}
catch {
    # Ignore old host encoding errors
}

$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Utf8Bom   = [System.Text.UTF8Encoding]::new($true)


function Get-Count {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return 0
    }

    return @($Value).Count
}

function Write-Utf8File {
    param(
        [string]$Path,
        [AllowNull()]
        [object]$Content,
        [switch]$Bom
    )

    $text = if ($null -eq $Content) {
        ""
    } elseif ($Content -is [array]) {
        ($Content -join [Environment]::NewLine)
    } else {
        [string]$Content
    }

    $enc = if ($Bom) { $script:Utf8Bom } else { $script:Utf8NoBom }
    [System.IO.File]::WriteAllText($Path, $text, $enc)
}

function Resolve-FullPath {
    param([string]$Path)
    return [System.IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

$ProjectRoot = Resolve-FullPath $ProjectRoot
$Root        = Resolve-FullPath $Root
$OutDir      = Resolve-FullPath $OutDir

$BinDir  = Join-Path $ProjectRoot "bin"
$Ctrtool = Join-Path $BinDir "ctrtool.exe"
$Makerom = Join-Path $BinDir "makerom.exe"
$Decrypt = Join-Path $BinDir "decrypt.exe"
$SeedDb  = Join-Path $BinDir "seeddb.bin"

$OutCxi        = Join-Path $OutDir "cxi"
$OutLoosePatch = Join-Path $OutDir "loosepatch"

# Optional / internal dirs
$OutWork       = Join-Path $OutDir "_work"
$OutLog        = Join-Path $OutDir "_logs"
$OutCci        = Join-Path $OutDir "_cci"
$OutInstallCia = Join-Path $OutDir "_cia_install"

foreach ($p in @($OutDir, $OutCxi, $OutLoosePatch)) {
    New-Item -ItemType Directory -Force -Path $p | Out-Null
}

if ($Mode -in @("CCI", "Both")) {
    New-Item -ItemType Directory -Force -Path $OutCci | Out-Null
}

if ($ReportCsv) {
    New-Item -ItemType Directory -Force -Path $OutLog | Out-Null
}

$ReportPath = if ($ReportCsv) {
    Join-Path $OutLog ("report_{0}.csv" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
} else {
    $null
}

$ReportRows = New-Object System.Collections.Generic.List[object]

function Write-Step { param([string]$Text) Write-Host $Text -ForegroundColor Cyan }
function Write-Ok   { param([string]$Text) Write-Host $Text -ForegroundColor Green }
function Write-Warn { param([string]$Text) Write-Host $Text -ForegroundColor Yellow }
function Write-Fail { param([string]$Text) Write-Host $Text -ForegroundColor Red }

function Require-Toolset {
    $missing = @()
    foreach ($tool in @($Ctrtool, $Makerom, $Decrypt)) {
        if (-not (Test-Path $tool)) { $missing += $tool }
    }
    if ($missing.Count -gt 0) {
        throw "Missing Redux toolset: $($missing -join ', ')"
    }
}

function Get-SafeBaseName {
    param([System.IO.FileInfo]$File)
    $name = [System.IO.Path]::GetFileNameWithoutExtension($File.Name)
    $name = $name -replace '[\\/:*?"<>|]', '_'
    return $name.Trim()
}

function Get-BaseTitleIdFromInstallTitleId {
    param([string]$TitleId)

    if (-not $TitleId) { return "" }

    $tid = $TitleId.ToLowerInvariant()

    if ($tid -match '^0004000e([0-9a-f]{8})$') {
        return "00040000" + $Matches[1]
    }

    if ($tid -match '^0004008c([0-9a-f]{8})$') {
        return "00040000" + $Matches[1]
    }

    return ""
}

function Clear-ReduxTmpNcch {
    foreach ($dir in @($BinDir, $ProjectRoot)) {
        foreach ($pat in @("tmp.*.ncch", "__cxi_stage*.ncch", "tmp.*.cia", "__cxi_stage*.cia")) {
            Get-ChildItem -Path $dir -Filter $pat -File -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }
    }
}


function Invoke-ToolCapture {
    param(
        [string]$Exe,
        [string[]]$ArgList,
        [string]$LogPath,
        [string]$WorkingDirectory = $ProjectRoot
    )

    Push-Location $WorkingDirectory
    try {
        # Debug: 记录真正传给 exe 的参数，避免 .args.txt 和实际调用不一致
        Write-Utf8File -Path ($LogPath + ".actual_args.txt") -Content ($ArgList -join " ")

        $output = & $Exe @ArgList 2>&1
        $exitCode = $LASTEXITCODE

        Write-Utf8File -Path $LogPath -Content $output

        return [pscustomobject]@{
            ExitCode = $exitCode
            Output   = ($output | Out-String)
            LogPath  = $LogPath
        }
    }
    finally {
        Pop-Location
    }
}


function Test-NcchMagic {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return $false
    }

    $fs = [System.IO.File]::OpenRead($Path)
    try {
        if ($fs.Length -lt 0x104) {
            return $false
        }

        $fs.Seek(0x100, [System.IO.SeekOrigin]::Begin) | Out-Null

        $buf = New-Object byte[] 4
        [void]$fs.Read($buf, 0, 4)

        $magic = [System.Text.Encoding]::ASCII.GetString($buf)
        return $magic -eq "NCCH"
    }
    finally {
        $fs.Close()
    }
}

function Get-CiaContentEntriesFromText {
    param([string]$Text)

    $entries = @()
    $currentIndex = $null

    foreach ($line in ($Text -split "`r?`n")) {
        if ($line -match '0x([0-9A-Fa-f]{4})\s*:') {
            $currentIndex = $Matches[1]
            continue
        }

        if ($null -ne $currentIndex -and $line -match '\bContentId\s*:\s*(?:0x)?([0-9A-Fa-f]{1,8})') {
            $entries += [pscustomobject]@{
                Index     = $currentIndex
                ContentId = $Matches[1].PadLeft(8, '0')
            }
            $currentIndex = $null
        }
    }

    return @($entries)
}


function Read-CtrtoolInfo {
    param([string]$Path, [string]$LogPath)

    $args = @()
    if (Test-Path $SeedDb) { $args += "--seeddb=$SeedDb" }
    $args += $Path

    $r = Invoke-ToolCapture -Exe $Ctrtool -ArgList $args -LogPath $LogPath

    $text = $r.Output

    $titleId = ""
    $titleVersion = ""
    $productCode = ""
    $programId = ""
    $internalName = ""
    $crypto = ""
    $contentIds = @()


    if ($text -match '(?im)^\s*Title id:\s*(\S+)')      { $titleId = $Matches[1] }
    if ($text -match '(?im)^\s*Product code:\s*(.+)$')  { $productCode = $Matches[1].Trim() }
    if ($text -match '(?im)^\s*Program id:\s*(\S+)')    { $programId = $Matches[1] }
    if ($text -match '(?im)^\s*Name:\s*(.+)$')          { $internalName = $Matches[1].Trim() }
    if ($text -match '(?im)^\s*Crypto Key\s*(.+)$')     { $crypto = $Matches[1].Trim() }

    # Prefer decimal version inside parentheses: TitleVersion: 3.4.0 (3136)
    if ($text -match '(?im)TitleVersion\s*:\s*.*?\((\d+)\)') {
        $titleVersion = $Matches[1]
    }
    elseif ($text -match '(?im)Title\s*Version\s*:\s*.*?\((\d+)\)') {
        $titleVersion = $Matches[1]
    }
    elseif ($text -match '(?im)TitleVersion\s*:\s*(\d+)') {
        $titleVersion = $Matches[1]
    }
    elseif ($text -match '(?im)Title\s*version\s*:\s*(\d+)') {
        $titleVersion = $Matches[1]
    }

    $contentEntries = @(Get-CiaContentEntriesFromText -Text $text)

    if (@($contentEntries).Count -gt 0) {
        $contentIds = @($contentEntries | ForEach-Object { $_.ContentId } | Select-Object -Unique)
    }

    foreach ($m in [regex]::Matches($text, '(?im)\bContentId\s*:\s*(?:0x)?([0-9A-Fa-f]{1,8})')) {
        $contentIds += $m.Groups[1].Value
    }
    foreach ($m in [regex]::Matches($text, '(?im)\bContent\s*Id\s*:\s*(?:0x)?([0-9A-Fa-f]{1,8})')) {
        $contentIds += $m.Groups[1].Value
    }

    $contentIds = @($contentIds | Select-Object -Unique)


    $isNcchByMagic = Test-NcchMagic -Path $Path

    return [pscustomobject]@{
        ExitCode     = $r.ExitCode
        Text         = $text
        LogPath      = $LogPath
        TitleId      = $titleId
        TitleVersion = $titleVersion
        ContentIds   = $contentIds
        ContentEntries = $contentEntries
        ProductCode  = $productCode
        ProgramId    = $programId
        InternalName = $internalName
        CryptoKey    = $crypto
        IsNcch       = (($text -match 'Header:\s+NCCH') -or $isNcchByMagic)
        IsNcsd       = ($text -match 'Header:\s+NCSD')
        IsExecutable = (
            $text -match '(?im)^\s*Form\s*type:\s*Executable' -or
            $text -match '(?im)^\s*FormType:\s*Executable' -or
            $text -match '(?im)^\s*Type:\s*Executable'
        )

        IsApplication = (
            $text -match '(?im)^\s*Content\s*type:\s*Application' -or
            $text -match '(?im)^\s*ContentType:\s*Application' -or
            $text -match '(?im)^\s*Content\s*Type:\s*Application'
        )

        HasExeFs = (
            $text -match '(?im)^\s*ExeFS\s+size:\s*0x(?!0+\b)[0-9A-Fa-f]+' -or
            $text -match '(?im)^\s*ExeFS\s+size:\s*[1-9][0-9]*\s+bytes' -or
            $text -match '(?im)^\s*ExeFS\s+offset:\s*(?!0+\b)[0-9A-Fa-f]+'
        )

        HasRomFs = (
            $text -match '(?im)^\s*RomFS\s+size:\s*0x(?!0+\b)[0-9A-Fa-f]+' -or
            $text -match '(?im)^\s*RomFS\s+size:\s*[1-9][0-9]*\s+bytes' -or
            $text -match '(?im)^\s*RomFS\s+offset:\s*(?!0+\b)[0-9A-Fa-f]+'
        )
    }
}

function Read-DecryptLogInfo {
    param([string]$LogPath)

    $titleId = ""
    $titleVersion = ""
    $contentIds = @()

    if (Test-Path -LiteralPath $LogPath) {
        $text = Get-Content -LiteralPath $LogPath -Raw -ErrorAction SilentlyContinue

        if ($text -match '(?im)^\s*Title\s+ID:\s*([0-9A-Fa-f]+)') {
            $titleId = $Matches[1]
        }
        elseif ($text -match '(?im)^\s*Title\s*id:\s*([0-9A-Fa-f]+)') {
            $titleId = $Matches[1]
        }

        # Prefer decimal version inside parentheses: TitleVersion: 3.4.0 (3136)
        if ($text -match '(?im)TitleVersion\s*:\s*.*?\((\d+)\)') {
            $titleVersion = $Matches[1]
        }
        elseif ($text -match '(?im)Title\s*Version\s*:\s*.*?\((\d+)\)') {
            $titleVersion = $Matches[1]
        }
        elseif ($text -match '(?im)TitleVersion\s*:\s*(\d+)') {
            $titleVersion = $Matches[1]
        }
        elseif ($text -match '(?im)Title\s*version\s*:\s*(\d+)') {
            $titleVersion = $Matches[1]
        }

        foreach ($m in [regex]::Matches($text, '(?im)\bContentId\s*:\s*(?:0x)?([0-9A-Fa-f]{1,8})')) {
            $contentIds += $m.Groups[1].Value
        }
        foreach ($m in [regex]::Matches($text, '(?im)\bContent\s*Id\s*:\s*(?:0x)?([0-9A-Fa-f]{1,8})')) {
            $contentIds += $m.Groups[1].Value
        }
        $contentIds = @($contentIds | Select-Object -Unique)
    }

  
    return [pscustomobject]@{
        TitleId      = $titleId
        TitleVersion = $titleVersion
        ContentIds   = $contentIds
    }
}

function Test-CxiCandidate {
    param([System.IO.FileInfo]$File, [string]$LogDir)

    $info = Read-CtrtoolInfo -Path $File.FullName -LogPath (Join-Path $LogDir ($File.Name + ".ctrtool.txt"))
    $score = 0
    foreach ($b in @($info.IsNcch, $info.IsExecutable, $info.IsApplication, $info.HasExeFs, $info.HasRomFs)) {
        if ($b) { $score++ }
    }

    return [pscustomobject]@{
        File  = $File
        Info  = $info
        Score = $score
    }
}

function Invoke-ReduxDecryptToNcch {
    param([System.IO.FileInfo]$InputFile, [string]$WorkDir, [string]$LogDir)

    Clear-ReduxTmpNcch

    # decrypt.exe 比较古早，尽量模拟原 bat：
    # 1. 文件放到 ProjectRoot
    # 2. 使用 ASCII 临时文件名
    # 3. 传相对文件名，不传绝对路径
    # 4. stdin 喂一个空行，等价于 bat 里的 echo | bin\decrypt.exe xxx.cia
    $stageName = "__cxi_stage_{0}{1}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8)), $InputFile.Extension.ToLowerInvariant()
    $stagePath = Join-Path $ProjectRoot $stageName

    $decryptLog = Join-Path $LogDir ($InputFile.BaseName + ".decrypt.txt")

    try {
        Copy-Item -Path $InputFile.FullName -Destination $stagePath -Force

        Write-Step "  [DECRYPT] Redux decrypt.exe -> tmp.*.ncch"

        Push-Location $ProjectRoot
        try {
            # PowerShell 里模拟：echo. | bin\decrypt.exe "__cxi_stage_xxxxxxxx.cia"
            $output = "" | & $Decrypt $stageName 2>&1
            $exitCode = $LASTEXITCODE
            Write-Utf8File -Path $decryptLog -Content $output
        }
        finally {
            Pop-Location
        }
        # decrypt.exe 有两种常见输出：
        # 1. 原 bat 路线：tmp.*.ncch
        # 2. 当前 PowerShell stage 路线：__cxi_stage_xxxxxxxx.0.ncch / .1.ncch
        $stageBase = [System.IO.Path]::GetFileNameWithoutExtension($stageName)

        $ncchPatterns = @(
            "tmp.*.ncch",
            "$stageBase*.ncch"
        )

        $ciaPatterns = @(
            "tmp.*.cia",
            "$stageBase*.cia"
        )

        $ncchFiles = @()
        $ciaFiles = @()

        foreach ($dir in @($BinDir, $ProjectRoot)) {
            foreach ($pat in $ncchPatterns) {
                $ncchFiles += Get-ChildItem -LiteralPath $dir -Filter $pat -File -ErrorAction SilentlyContinue
            }

            foreach ($pat in $ciaPatterns) {
                $ciaFiles += Get-ChildItem -LiteralPath $dir -Filter $pat -File -ErrorAction SilentlyContinue
            }
        }

        $ncchFiles = @($ncchFiles | Sort-Object FullName -Unique)
        $ciaFiles  = @($ciaFiles  | Sort-Object FullName -Unique)

        if ($ncchFiles.Count -eq 0 -and $ciaFiles.Count -eq 0) {
            $logText = ""
            if (Test-Path $decryptLog) {
                $logText = (Get-Content $decryptLog -Raw -ErrorAction SilentlyContinue)
            }

            throw "decrypt.exe produced no tmp.*.ncch. ExitCode=$exitCode. See: $decryptLog`n--- decrypt.exe output ---`n$logText"
        }

        $copiedNcch = @()
        foreach ($f in $ncchFiles) {
            $dst = Join-Path $WorkDir $f.Name
            Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
            $copiedNcch += Get-Item $dst
        }

        $copiedCia = @()
        foreach ($f in $ciaFiles) {
            $dst = Join-Path $WorkDir $f.Name
            Copy-Item -LiteralPath $f.FullName -Destination $dst -Force
            $copiedCia += Get-Item $dst
        }

        return [pscustomobject]@{
            NcchFiles  = $copiedNcch
            CiaFiles   = $copiedCia
            DecryptLog = $decryptLog
        }
    }
    finally {
        if (Test-Path -LiteralPath $stagePath) {
            Remove-Item $stagePath -Force -ErrorAction SilentlyContinue
        }

        # 清掉 decrypt.exe 根据 stageName 生成的 .ncch
        $stageBase = [System.IO.Path]::GetFileNameWithoutExtension($stageName)
        foreach ($dir in @($BinDir, $ProjectRoot)) {
            Get-ChildItem -Path $dir -Filter "$stageBase*.ncch" -File -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }

        # 清掉历史残留
        foreach ($dir in @($BinDir, $ProjectRoot)) {
            Get-ChildItem -Path $dir -Filter "__cxi_stage*.ncch" -File -ErrorAction SilentlyContinue |
                Remove-Item -Force -ErrorAction SilentlyContinue
        }

        foreach ($dir in @($BinDir, $ProjectRoot)) {
            foreach ($pat in @("$stageBase*.ncch", "$stageBase*.cia", "__cxi_stage*.ncch", "__cxi_stage*.cia")) {
                Get-ChildItem -Path $dir -Filter $pat -File -ErrorAction SilentlyContinue |
                    Remove-Item -Force -ErrorAction SilentlyContinue
            }
        }

        if (-not $KeepNcch) {
            Clear-ReduxTmpNcch
        }

    }
}

function Invoke-CtrtoolExtractContents {
    param(
        [System.IO.FileInfo]$InputFile,
        [string]$WorkDir,
        [string]$LogDir
    )

    $contentsLog = Join-Path $LogDir ($InputFile.BaseName + ".ctrtool_contents.txt")
    $extractDir = Join-Path $WorkDir "ctrtool_contents"
    New-Item -ItemType Directory -Force -Path $extractDir | Out-Null

    Write-Step "  [CTRTOOL] extracting contents from input"

    Push-Location $extractDir
    try {
        $output = & $CtrTool --contents=contents $InputFile.FullName 2>&1
        $exitCode = $LASTEXITCODE
        Write-Utf8File -Path $contentsLog -Content $output
    }
    finally {
        Pop-Location
    }

    $candidates = @()

    # ctrtool --contents=contents 通常会输出 contents.0000.xxxxxxxx 之类文件
    $candidates += Get-ChildItem -Path $extractDir -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Length -gt 0 -and (
                $_.Name -like "contents*" -or
                $_.Extension -in ".cxi", ".ncch", ".app"
            )
        }

    # 兜底：有些 ctrtool 会直接按 section 名吐文件
    $candidates += Get-ChildItem -Path $extractDir -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Length -gt 0 -and $_.FullName -notin $candidates.FullName
        }

    $ncchLike = @()

    foreach ($f in $candidates) {
        if (Test-NcchMagic -Path $f.FullName) {
            $dst = Join-Path $WorkDir ($f.BaseName + ".ncch")
            Copy-Item $f.FullName $dst -Force
            $ncchLike += Get-Item $dst
        }
    }

    if ($ncchLike.Count -eq 0) {
        throw "ctrtool --contents also produced no NCCH-like content. See: $contentsLog"
    }

    return $ncchLike
}

function Select-MainCxiFromNcch {
    param([System.IO.FileInfo[]]$NcchFiles, [string]$LogDir)

    $checks = @()
    foreach ($n in $NcchFiles) {
        $checks += Test-CxiCandidate -File $n -LogDir $LogDir
    }

    $main = $checks |
        Where-Object { $_.File.Name -match 'tmp\.Main\.ncch' -and $_.Info.IsNcch } |
        Select-Object -First 1

    if (-not $main) {
        $main = $checks |
            Where-Object { $_.Info.IsNcch -and $_.Info.IsExecutable -and $_.Info.IsApplication -and $_.Info.HasExeFs } |
            Sort-Object @{Expression={$_.Score}; Descending=$true}, @{Expression={$_.File.Length}; Descending=$true} |
            Select-Object -First 1
    }

    if (-not $main) {
        $main = $checks |
            Where-Object { Test-NcchMagic -Path $_.File.FullName } |
            Sort-Object @{Expression={$_.File.Length}; Descending=$true} |
            Select-Object -First 1
    }

    if (-not $main) {
        throw "No usable CXI-like NCCH content found."
    }


    if ($main.Score -lt 3) {
        if (Test-NcchMagic -Path $main.File.FullName) {
            Write-Warn "  [WARN] CXI candidate has low ctrtool score, but NCCH magic is valid. Using largest NCCH-like content."
        }
        else {
            throw "No usable CXI-like NCCH content found."
        }
    }

    return $main
}

function Get-CiaAutoKind {
    param(
        [System.IO.FileInfo[]]$NcchFiles,
        [string]$LogDir
    )

    $checks = @()
    foreach ($n in $NcchFiles) {
        $checks += Test-CxiCandidate -File $n -LogDir $LogDir
    }

    $mainGame = $checks |
        Where-Object {
            $_.Info.IsNcch -and
            $_.Info.IsExecutable -and
            $_.Info.IsApplication -and
            $_.Info.HasExeFs
        } |
        Sort-Object @{Expression={$_.Score}; Descending=$true}, @{Expression={$_.File.Length}; Descending=$true} |
        Select-Object -First 1

    if ($mainGame) {
        return [pscustomobject]@{
            Kind   = "GAME"
            Reason = "Executable Application NCCH with ExeFS"
            Main   = $mainGame
            Checks = $checks
        }
    }

    # Fallback: many game CIAs have one huge main NCCH even if ctrtool text parsing misses FormType/ContentType.
    # DLC/update can also be large, so this is a heuristic, but it prevents obvious full-game CIAs from being treated as install-only.
    $largestNcch = $checks |
        Where-Object {
            $_.Info.IsNcch -or (Test-NcchMagic -Path $_.File.FullName)
        } |
        Sort-Object @{Expression={$_.File.Length}; Descending=$true} |
        Select-Object -First 1

    if ($largestNcch -and $largestNcch.File.Length -gt 128MB) {
        return [pscustomobject]@{
            Kind   = "GAME"
            Reason = "Large NCCH fallback (>128MB); likely game main content"
            Main   = $largestNcch
            Checks = $checks
        }
    }

    $hasNcch = @(
        $checks | Where-Object {
            $_.Info.IsNcch -or (Test-NcchMagic -Path $_.File.FullName)
        }
    ).Count -gt 0

    if ($hasNcch) {
        return [pscustomobject]@{
            Kind   = "INSTALL_ONLY"
            Reason = "NCCH content exists but no executable main CXI; likely DLC or Update"
            Main   = $null
            Checks = $checks
        }
    }

    return [pscustomobject]@{
        Kind   = "UNKNOWN"
        Reason = "No usable NCCH content"
        Main   = $null
        Checks = $checks
    }
}

function Get-NcchContentProfile {
    param([System.IO.FileInfo[]]$NcchFiles, [string]$LogDir)

    $checks = @()
    foreach ($n in $NcchFiles) {
        $checks += Test-CxiCandidate -File $n -LogDir $LogDir
    }

    $hasGameMain = @(
        $checks | Where-Object {
            $_.Info.IsNcch -and
            $_.Info.IsExecutable -and
            $_.Info.IsApplication -and
            $_.Info.HasExeFs
        }
    ).Count -gt 0

    $hasNcch = @(
        $checks | Where-Object {
            $_.Info.IsNcch -or (Test-NcchMagic -Path $_.File.FullName)
        }
    ).Count -gt 0

    $largest = $checks |
        Sort-Object @{Expression={$_.File.Length}; Descending=$true} |
        Select-Object -First 1

    $kind = if ($hasGameMain) {
        "GAME"
    } elseif ($hasNcch) {
        "INSTALL_ONLY"
    } else {
        "UNKNOWN"
    }

    return [pscustomobject]@{
        Kind       = $kind
        HasGameMain= $hasGameMain
        HasNcch    = $hasNcch
        Largest    = $largest
        Checks     = $checks
    }
}

function New-InstallCiaFromNcch {
    param(
        [System.IO.FileInfo[]]$NcchFiles,
        [string]$OutPath,
        [string]$LogPath,
        [AllowNull()]
        [object]$CiaInfo
    )

    $valid = @(
        $NcchFiles |
            Where-Object { Test-NcchMagic -Path $_.FullName } |
            Sort-Object Name
    )

    if ($valid.Count -eq 0) {
        throw "No NCCH content available for install CIA."
    }

    $titleId = ""
    $titleVersion = "0"
    $contentIds = @()

    if ($null -ne $CiaInfo) {
        if ($CiaInfo.TitleId) {
            $titleId = ([string]$CiaInfo.TitleId).ToLowerInvariant()
        }
        if ($CiaInfo.TitleVersion) {
            $titleVersion = [string]$CiaInfo.TitleVersion
        }
        if ($CiaInfo.ContentIds) {
            $contentIds = @($CiaInfo.ContentIds)
        }

        if ($CiaInfo.Text) {
            Write-Utf8File -Path ($LogPath + ".ciainfo.txt") -Content $CiaInfo.Text
        }
    }

    $installKind = "CIA"
    if ($titleId -match '^0004000e') {
        $installKind = "Patch"
    }
    elseif ($titleId -match '^0004008c') {
        $installKind = "DLC"
    }

    if ($contentIds.Count -gt 0 -and $valid.Count -gt $contentIds.Count) {
        Write-Warn "  [WARN] Trimming NCCH files to ContentId count: $($contentIds.Count)"
        $valid = @($valid | Sort-Object Name | Select-Object -First $contentIds.Count)
    }
    elseif ($contentIds.Count -eq 0 -and $installKind -eq "Patch" -and $valid.Count -gt 1) {
        Write-Warn "  [WARN] Patch CIA has multiple NCCH but no ContentId parsed; using largest NCCH only."
        $valid = @($valid | Sort-Object Length -Descending | Select-Object -First 1)
    }

    $stageDirName = "__cia_build_{0}" -f ([guid]::NewGuid().ToString("N").Substring(0, 8))
    $stageDir = Join-Path $BinDir $stageDirName
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null

    try {
        $stageOutName = "out.cia"
        $stageOutPath = Join-Path $stageDir $stageOutName
        $stageOutRel  = ("bin/{0}/{1}" -f $stageDirName, $stageOutName)
        $staged = @()

        $i = 0
        foreach ($f in $valid) {
            $stageContentName = "content{0}.ncch" -f $i
            $stageContentPath = Join-Path $stageDir $stageContentName
            Copy-Item -LiteralPath $f.FullName -Destination $stageContentPath -Force

            $relativeContent = ("bin/{0}/{1}" -f $stageDirName, $stageContentName)

            $cid = $i
            if ($contentIds.Count -gt $i) {
                try {
                    $cid = [Convert]::ToInt32($contentIds[$i], 16)
                }
                catch {
                    $cid = $i
                }
            }
            Write-Host ("  [ARG_CONTENT] idx={0} id={1} file={2}" -f $i, $cid, $relativeContent)

            $staged += [pscustomobject]@{
                RelPath = $relativeContent
                Index   = $i
                Id      = $cid
            }

            $i++
        }

        $attempts = @()

        # makerom v0.19.0 usage says:
        #   -content <file>:<index>
        #   -ver <version>
        # It does NOT list -i / -target / -ignoresign.
        $args = @(
            "-f", "cia",
            "-o", $stageOutRel
        )

        foreach ($s in $staged) {
            $args += @("-content", ("{0}:{1}:{2}" -f $s.RelPath, $s.Index, $s.Id))
        }

        $args += @("-ver", $titleVersion)

        $attempts += [pscustomobject]@{
            Name = "v019-content-3part"
            Args = $args
        }

        $allLogs = New-Object System.Collections.Generic.List[string]

        foreach ($attempt in $attempts) {
            if (Test-Path -LiteralPath $stageOutPath) {
                Remove-Item -LiteralPath $stageOutPath -Force -ErrorAction SilentlyContinue
            }

            $attemptLog = $LogPath -replace '\.txt$', (".{0}.txt" -f $attempt.Name)
            $attemptArgsLog = $attemptLog + ".args.txt"

            Write-Host ("  [CONTENT_ID] " + (($contentIds | ForEach-Object { $_ }) -join ", "))
            Write-Step "  [MAKEROM] Build decrypted install CIA [$installKind/$($attempt.Name)] TitleId=$titleId Version=$titleVersion"
            Write-Utf8File -Path $attemptArgsLog -Content ($attempt.Args -join " ")

            $r = Invoke-ToolCapture -Exe $Makerom -ArgList $attempt.Args -LogPath $attemptLog -WorkingDirectory $ProjectRoot

            $allLogs.Add("=== $($attempt.Name) args ===")
            $allLogs.Add(($attempt.Args -join " "))
            $allLogs.Add("=== $($attempt.Name) output ===")
            if (Test-Path -LiteralPath $attemptLog) {
                $allLogs.Add((Get-Content -LiteralPath $attemptLog -Raw -ErrorAction SilentlyContinue))
            }
            if (Test-Path -LiteralPath $stageOutPath) {
                Copy-Item -LiteralPath $stageOutPath -Destination $OutPath -Force
                Write-Utf8File -Path $LogPath -Content $allLogs
                return
            }
        }

        Write-Utf8File -Path $LogPath -Content $allLogs
        throw "makerom failed to create install CIA after all attempts. See: $LogPath"
    }
    finally {
        if ($KeepWork) {
            Write-Host "  [STAGE] $stageDir"
        }
        elseif (Test-Path -LiteralPath $stageDir) {
            Remove-Item -LiteralPath $stageDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-LooseInstallLayoutFromNcch {
    param(
        [System.IO.FileInfo[]]$NcchFiles,
        [string]$OutRoot,
        [string]$InstallTitleId,
        [AllowNull()]
        [object]$CiaInfo,
        [switch]$AlsoWriteContentIdAliases
    )

    if (-not $InstallTitleId) {
        throw "InstallTitleId is empty; cannot build loose install layout."
    }

    $tid = $InstallTitleId.ToLowerInvariant()
    if ($tid.Length -ne 16) {
        throw "Invalid InstallTitleId: $InstallTitleId"
    }

    $hi = $tid.Substring(0, 8)
    $lo = $tid.Substring(8, 8)

    $contentDir = Join-Path $OutRoot ("title\{0}\{1}\content" -f $hi, $lo)
    New-Item -ItemType Directory -Force -Path $contentDir | Out-Null

    $valid = @(
        $NcchFiles |
            Where-Object { Test-NcchMagic -Path $_.FullName } |
            Sort-Object Name
    )

    if ($valid.Count -eq 0) {
        throw "No NCCH content available for loose install layout."
    }

    $entries = @()
    if ($null -ne $CiaInfo -and $CiaInfo.PSObject.Properties.Name -contains "ContentEntries") {
        $entries = @($CiaInfo.ContentEntries)
    }

    $contentIds = @()
    if ($null -ne $CiaInfo -and $CiaInfo.PSObject.Properties.Name -contains "ContentIds") {
        $contentIds = @($CiaInfo.ContentIds)
    }

    if ($entries.Count -gt 0 -and $valid.Count -gt $entries.Count) {
        Write-Warn "  [WARN] Trimming NCCH files to ContentInfo count: $($entries.Count)"
        $valid = @($valid | Sort-Object Name | Select-Object -First $entries.Count)
    }

    $mapRows = New-Object System.Collections.Generic.List[string]
    $mapRows.Add("index_app,content_id_app,source_file,size_bytes")

    for ($i = 0; $i -lt $valid.Count; $i++) {
        $f = @($valid)[$i]

        if (@($entries).Count -gt $i -and $entries[$i].Index) {
            $indexName = ([Convert]::ToUInt32($entries[$i].Index, 16)).ToString("x8")
        }
        else {
            $indexName = "{0:x8}" -f $i
        }

        $contentIdName = ""
        if (@($entries).Count -gt $i -and $entries[$i].ContentId) {
            $contentIdName = ([Convert]::ToUInt32($entries[$i].ContentId, 16)).ToString("x8")
        }
        elseif (@($contentIds).Count -gt $i) {
            try {
                $contentIdName = ([Convert]::ToUInt32(([string]$contentIds[$i]), 16)).ToString("x8")
            }
            catch {
                $contentIdName = ""
            }
        }


        $indexDst = Join-Path $contentDir ($indexName + ".app")
        Copy-Item -LiteralPath $f.FullName -Destination $indexDst -Force
        Write-Ok "  [OK] APP(index): $indexDst"

        if ($AlsoWriteContentIdAliases -and $contentIdName -and $contentIdName -ne $indexName) {
            $contentIdDst = Join-Path $contentDir ($contentIdName + ".app")
            Copy-Item -LiteralPath $f.FullName -Destination $contentIdDst -Force
            Write-Ok "  [OK] APP(contentId alias): $contentIdDst"
        }

        $mapRows.Add(("{0}.app,{1}.app,{2},{3}" -f $indexName, $contentIdName, $f.Name, $f.Length))
    }

    if ($ReportCsv) {
        $mapPath = Join-Path $OutRoot ("loose_map_{0}.csv" -f $tid)
        Write-Utf8File -Path $mapPath -Content $mapRows
        Write-Ok "  [OK] LOOSE MAP: $mapPath"
    }
    else {
        Write-Host "  [LOOSE MAP] CSV disabled. Use -ReportCsv to export loose_map."
    }

    return $contentDir
}

function New-CciFromNcch {
    param(
        [System.IO.FileInfo[]]$NcchFiles,
        [string]$OutPath,
        [string]$LogPath
    )

    $ordered = @()
    $map = @{
        "tmp.Main.ncch"           = 0
        "tmp.Manual.ncch"         = 1
        "tmp.DownloadPlay.ncch"   = 2
        "tmp.Partition4.ncch"     = 3
        "tmp.Partition5.ncch"     = 4
        "tmp.Partition6.ncch"     = 5
        "tmp.N3DSUpdateData.ncch" = 6
        "tmp.UpdateData.ncch"     = 7
    }

    foreach ($kv in $map.GetEnumerator() | Sort-Object Value) {
        $f = $NcchFiles | Where-Object { $_.Name -ieq $kv.Key } | Select-Object -First 1
        if ($f) {
            $ordered += [pscustomobject]@{
                File  = $f
                Index = $kv.Value
                Id    = $kv.Value
            }
        }
    }

    if ($ordered.Count -eq 0) {
        $i = 0
        foreach ($f in ($NcchFiles | Sort-Object Length -Descending)) {
            $ordered += [pscustomobject]@{
                File  = $f
                Index = $i
                Id    = $i
            }
            $i++
        }
    }

    $args = @("-f", "cci", "-ignoresign", "-target", "p", "-o", $OutPath)

    foreach ($x in $ordered) {
        $args += @("-i", ("{0}:{1}:{2}" -f $x.File.FullName, $x.Index, $x.Id))
    }

    Write-Step "  [MAKEROM] Build decrypted CCI"
    Write-Utf8File -Path ($LogPath + ".args.txt") -Content ($args -join " ")

    $r = Invoke-ToolCapture -Exe $Makerom -ArgList $args -LogPath $LogPath -WorkingDirectory $ProjectRoot

    if (-not (Test-Path -LiteralPath $OutPath)) {
        $logText = ""
        if (Test-Path -LiteralPath $LogPath) {
            $logText = Get-Content -LiteralPath $LogPath -Raw -ErrorAction SilentlyContinue
        }
        throw "makerom failed to create CCI. See: $LogPath`n--- makerom output ---`n$logText"
    }
}

function Find-NcchInFile {
    param([string]$Path, [int64]$MaxScanBytes)

    $fs = [System.IO.File]::OpenRead($Path)
    try {
        $chunkSize = 8 * 1024 * 1024
        $magic = [byte[]](0x4E, 0x43, 0x43, 0x48)
        $scanLimit = [Math]::Min([int64]$fs.Length, [int64]$MaxScanBytes)
        $pos = [int64]0
        $prev = [byte[]]::new(0)

        while ($pos -lt $scanLimit) {
            $toRead = [int][Math]::Min([int64]$chunkSize, $scanLimit - $pos)
            $readBuf = [byte[]]::new($toRead)
            $fs.Seek($pos, [System.IO.SeekOrigin]::Begin) | Out-Null
            $n = $fs.Read($readBuf, 0, $toRead)
            if ($n -le 0) { break }

            $buf = [byte[]]::new($prev.Length + $n)
            if ($prev.Length -gt 0) { [Array]::Copy($prev, 0, $buf, 0, $prev.Length) }
            [Array]::Copy($readBuf, 0, $buf, $prev.Length, $n)

            $bufLen = $prev.Length + $n
            $baseAbs = $pos - $prev.Length

            for ($i = 0; $i -le $bufLen - 4; $i++) {
                if ($buf[$i] -eq $magic[0] -and $buf[$i+1] -eq $magic[1] -and $buf[$i+2] -eq $magic[2] -and $buf[$i+3] -eq $magic[3]) {
                    $magicOffset = [int64]($baseAbs + $i)
                    $contentOffset = [int64]($magicOffset - 0x100)
                    if ($contentOffset -lt 0) { continue }
                    $fs.Seek($magicOffset + 4, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $sizeBytes = [byte[]]::new(4)
                    if ($fs.Read($sizeBytes, 0, 4) -ne 4) { continue }
                    $mediaUnits = [BitConverter]::ToUInt32($sizeBytes, 0)
                    $cxiSize = [int64]$mediaUnits * 0x200
                    if ($mediaUnits -gt 0 -and $cxiSize -gt 1MB -and ($contentOffset + $cxiSize) -le $fs.Length) {
                        return [pscustomobject]@{ ContentOffset=$contentOffset; CxiSize=$cxiSize }
                    }
                }
            }

            $overlap = [Math]::Min(3, $bufLen)
            $prev = [byte[]]::new($overlap)
            if ($overlap -gt 0) { [Array]::Copy($buf, $bufLen - $overlap, $prev, 0, $overlap) }
            $pos += $n
        }
        return $null
    }
    finally { $fs.Close() }
}


function Copy-FileRange {
    param([string]$Src, [string]$Dst, [int64]$Start, [int64]$Length)
    $inputStream = [System.IO.File]::OpenRead($Src)
    try {
        $inputStream.Seek($Start, [System.IO.SeekOrigin]::Begin) | Out-Null
        $outputStream = [System.IO.File]::Create($Dst)
        try {
            $buffer = [byte[]]::new(8 * 1024 * 1024)
            $remaining = [int64]$Length
            while ($remaining -gt 0) {
                $toRead = [int][Math]::Min([int64]$buffer.Length, $remaining)
                $read = $inputStream.Read($buffer, 0, $toRead)
                if ($read -le 0) { throw "Unexpected EOF while copying CXI range." }
                $outputStream.Write($buffer, 0, $read)
                $remaining -= $read
            }
        }
        finally { $outputStream.Close() }
    }
    finally { $inputStream.Close() }
}

function Try-DirectExtractFromDecryptedContainer {
    param([System.IO.FileInfo]$InputFile, [string]$Dst, [string]$LogDir)

    Write-Step "  [FALLBACK] ctrtool --contents / NCCH carve"
    $contentsDir = Join-Path $LogDir "contents"
    New-Item -ItemType Directory -Force -Path $contentsDir | Out-Null

    Push-Location $contentsDir
    try {
        $args = @()
        if (Test-Path $SeedDb) { $args += "--seeddb=$SeedDb" }
        $args += "--contents=contents"
        $args += $InputFile.FullName

        $r = Invoke-ToolCapture -Exe $Ctrtool -ArgList $args -LogPath (Join-Path $LogDir ($InputFile.BaseName + ".contents.txt")) -WorkingDirectory $contentsDir
    }
    finally {
        Pop-Location
    }

    $contents = @(Get-ChildItem -Path $contentsDir -Filter "contents.*" -File -ErrorAction SilentlyContinue | Sort-Object Length -Descending)
    if ($contents.Count -gt 0) {
        $main = Select-MainCxiFromNcch -NcchFiles $contents -LogDir $LogDir
        Copy-Item -Path $main.File.FullName -Destination $Dst -Force
        return "ctrtool-contents"
    }

    $found = Find-NcchInFile -Path $InputFile.FullName -MaxScanBytes ([int64]$MaxScanMB * 1024 * 1024)
    if ($null -eq $found) { throw "No NCCH found by fallback scan." }
    Copy-FileRange -Src $InputFile.FullName -Dst $Dst -Start $found.ContentOffset -Length $found.CxiSize
    return "carve"
}

Require-Toolset

$extensions = switch ($InputType) {
    "CIA"    { @(".cia") }
    "CIA3DS" { @(".cia", ".3ds") }
    "All"    { @(".cia", ".3ds", ".cci", ".cxi") }
}

if ($Recurse) {
    $inputFiles = @(Get-ChildItem -Path $Root -File -Recurse | Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() })
} else {
    $inputFiles = @(Get-ChildItem -Path $Root -File | Where-Object { $extensions -contains $_.Extension.ToLowerInvariant() })
}

if ($inputFiles.Count -eq 0) {
    Write-Warn "[MISS] No $InputType input files found in: $Root"
    Write-Host "       Default mode only scans *.cia in the current folder. Use -InputType All or -Recurse if needed."
    exit 0
}

Write-Host "[INFO] ProjectRoot: $ProjectRoot"
Write-Host "[INFO] Root:        $Root"
Write-Host "[INFO] OutDir:      $OutDir"
Write-Host "[INFO] Mode:        $Mode"
Write-Host "[INFO] InputType:   $InputType"
Write-Host "[INFO] Files:       $($inputFiles.Count)"
Write-Host ""

foreach ($file in $inputFiles) {
    $base = Get-SafeBaseName $file

    # Runtime temp workspace.
    # This is needed for extraction/conversion, but should not be a user-facing output.
    $work = Join-Path $OutWork ("work_" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Force -Path $work | Out-Null

    # Runtime logs are always created inside _work.
    # They are auto-removed on success unless -KeepWork is used.
    $logDir = Join-Path $work "logs"
    New-Item -ItemType Directory -Force -Path $logDir | Out-Null

    $outCxiPath = Join-Path $OutCxi ($base + ".cxi")

    # Optional outputs: don't create their parent dirs until actually needed.
    $outCciPath = Join-Path $OutCci ($base + ".cci")
    $outInstallCiaPath = Join-Path $OutInstallCia ($base + ".decrypted.cia")


    $status = "BAD"
    $issue = ""
    $method = ""
    $autoType = ""
    $installTitleId = ""
    $expectedBaseTitleId = ""
    $looseInstallPath = ""
    $info = $null

    Write-Host "[FILE] $($file.FullName)"

    try {
        if ((Test-Path $outCxiPath) -and -not $Force -and ($Mode -in @("CXI", "Both"))) {
            throw "Output exists: $outCxiPath ; use -Force to overwrite."
        }
        if ((Test-Path $outCciPath) -and -not $Force -and ($Mode -in @("CCI", "Both"))) {
            throw "Output exists: $outCciPath ; use -Force to overwrite."
        }
        if ($KeepInstallCia -and (Test-Path -LiteralPath $outInstallCiaPath) -and -not $Force) {
            throw "Output exists: $outInstallCiaPath ; use -Force to overwrite."
        }

        if ($file.Extension -ieq ".cxi") {
            if ($Mode -in @("CXI", "Both")) { Copy-Item $file.FullName $outCxiPath -Force; $method = "copy-cxi" }
        }
        elseif ($file.Extension -match '^\.(cia|3ds)$') {
            $ncch = @()
            $installCiaCandidates = @()
            $decryptMethod = ""
            $decryptLogPath = ""

            try {
                $decryptResult = Invoke-ReduxDecryptToNcch -InputFile $file -WorkDir $work -LogDir $logDir
                $ncch = @($decryptResult.NcchFiles)
                $installCiaCandidates = @($decryptResult.CiaFiles)
                $decryptLogPath = $decryptResult.DecryptLog
                $decryptMethod = "redux-decrypt"
            }
            catch {
                Write-Warn "  [WARN] Redux decrypt failed, fallback to ctrtool --contents"
                Write-Warn ("  [WARN] " + $_.Exception.Message)

                $ncch = Invoke-CtrtoolExtractContents -InputFile $file -WorkDir $work -LogDir $logDir
                $decryptMethod = "ctrtool-contents-ncch"
            }

            $ciaInfo = Read-CtrtoolInfo -Path $file.FullName -LogPath (Join-Path $logDir ($base + ".cia.container.txt"))

            $profile = Get-CiaAutoKind -NcchFiles $ncch -LogDir $logDir
       
            if (-not $ciaInfo.TitleId -and $decryptLogPath) {
                $dl = Read-DecryptLogInfo -LogPath $decryptLogPath

                if ($dl.TitleId) {
                    $ciaInfo.TitleId = $dl.TitleId
                }
                if ($dl.TitleVersion) {
                    $ciaInfo.TitleVersion = $dl.TitleVersion
                }
                if ($dl.ContentIds -and @($dl.ContentIds).Count -gt 0) {
                    $ciaInfo.ContentIds = @($dl.ContentIds)
                }
            }

            $autoType = $profile.Kind
            Write-Step "  [TYPE] $($profile.Kind) - $($profile.Reason)"

            if ($profile.Kind -eq "GAME") {
                $autoType = "GAME"

                if ($Mode -in @("CXI", "Both")) {
                    $main = $profile.Main
                    if (-not $main) {
                        $main = Select-MainCxiFromNcch -NcchFiles $ncch -LogDir $logDir
                    }
                    Copy-Item -LiteralPath $main.File.FullName -Destination $outCxiPath -Force
                    $method = $decryptMethod + "+auto-game-cxi"
                    Write-Ok "  [OK] CXI: $outCxiPath"
                }

                if ($Mode -in @("CCI", "Both")) {
                    New-CciFromNcch -NcchFiles $ncch -OutPath $outCciPath -LogPath (Join-Path $logDir ($base + ".makerom.cci.txt"))
                    Write-Ok "  [OK] CCI: $outCciPath"
                    if ($method) { $method += "+makerom-cci" } else { $method = $decryptMethod + "+makerom-cci" }
                }
            }
            elseif ($profile.Kind -eq "INSTALL_ONLY") {
                $autoType = "INSTALL_ONLY"

                Write-Warn "  [INSTALL_ONLY] No executable CXI main content. Treat as DLC/Update CIA."

                $installTitleId = ""
                if ($ciaInfo -and $ciaInfo.TitleId) {
                    $installTitleId = ([string]$ciaInfo.TitleId).ToLowerInvariant()
                }

                $expectedBaseTitleId = Get-BaseTitleIdFromInstallTitleId -TitleId $installTitleId

                if ($installTitleId) {
                    Write-Warn "  [INSTALL_ONLY] Install TitleId: $installTitleId"
                }

                if ($expectedBaseTitleId) {
                    Write-Warn "  [INSTALL_ONLY] Expected Base TitleId: $expectedBaseTitleId"
                }

                if ($installTitleId) {
                    $outInstallCiaPath = Join-Path $OutInstallCia ("{0} [{1}].decrypted.cia" -f $base, $installTitleId)
                }

                if ($KeepInstallCia -and (Test-Path -LiteralPath $outInstallCiaPath) -and -not $Force) {
                    throw "Output exists: $outInstallCiaPath ; use -Force to overwrite."
                }

                # Default INSTALL_ONLY output:
                #   DLC / Update CIA -> loosepatch/title/<hi>/<lo>/content/*.app
                #
                # Optional:
                #   -KeepInstallCia also emits _cia_install/*.decrypted.cia

                if ($KeepInstallCia) {
                    New-Item -ItemType Directory -Force -Path $OutInstallCia | Out-Null

                    try {
                        New-InstallCiaFromNcch `
                            -NcchFiles $ncch `
                            -OutPath $outInstallCiaPath `
                            -LogPath (Join-Path $logDir ($base + ".makerom.install.cia.txt")) `
                            -CiaInfo $ciaInfo

                        $method = $decryptMethod + "+makerom-install-cia"
                        Write-Ok "  [OK] INSTALL CIA: $outInstallCiaPath"
                    }
                    catch {
                        Write-Warn "  [WARN] makerom install CIA failed; continuing with loose layout."
                        Write-Warn ("  [WARN] " + $_.Exception.Message)
                    }
                }

                $looseInstallPath = New-LooseInstallLayoutFromNcch `
                    -NcchFiles $ncch `
                    -OutRoot $OutLoosePatch `
                    -InstallTitleId $installTitleId `
                    -CiaInfo $ciaInfo

                if ($method) {
                    $method += "+loose-sd-install-layout"
                }
                else {
                    $method = $decryptMethod + "+loose-sd-install-layout"
                }

                Write-Ok "  [OK] LOOSE INSTALL: $looseInstallPath"


                $status = "OK"
                $issue = "INSTALL_ONLY_DLC_OR_UPDATE"
            }
            else {
                throw "Unknown CIA content profile. No executable CXI and no NCCH-like content."
            }
        }
        elseif ($file.Extension -ieq ".cci") {
            if ($Mode -in @("CCI", "Both")) { Copy-Item $file.FullName $outCciPath -Force; $method = "copy-cci" }
            if ($Mode -in @("CXI", "Both")) {
                $method = Try-DirectExtractFromDecryptedContainer -InputFile $file -Dst $outCxiPath -LogDir $logDir
                Write-Ok "  [OK] CXI: $outCxiPath"
            }
        }

        $verifyTarget = $null
        if (($Mode -in @("CXI", "Both")) -and (Test-Path -LiteralPath $outCxiPath)) {
            $verifyTarget = $outCxiPath
        }
        elseif (($Mode -in @("CCI", "Both")) -and (Test-Path -LiteralPath $outCciPath)) {
            $verifyTarget = $outCciPath
        }
        elseif ($KeepInstallCia -and (Test-Path -LiteralPath $outInstallCiaPath)) {
            $verifyTarget = $outInstallCiaPath
        }

        if ($verifyTarget) {
            $info = Read-CtrtoolInfo -Path $verifyTarget -LogPath (Join-Path $logDir ($base + ".verify.txt"))
            if ($info.ExitCode -eq 0 -or $info.IsNcch -or $info.IsNcsd) {
                $status = "OK"
                Write-Ok "  [VERIFY] OK"
                if ($info.ProductCode) { Write-Host "  [PRODUCT] $($info.ProductCode)" }
                if ($info.InternalName) { Write-Host "  [NAME]    $($info.InternalName)" }
                if ($info.CryptoKey) { Write-Host "  [CRYPTO]  $($info.CryptoKey)" }
            } else {
                $issue = "ctrtool verify failed"
                Write-Warn "  [VERIFY] suspicious; see logs"
            }
        }
    }
    catch {
        $issue = $_.Exception.Message
        Write-Fail "  [ERROR] $issue"
    }
    finally {
        $ReportRows.Add([pscustomobject]@{
            file          = $file.FullName
            status        = $status
            issues        = $issue
            method        = $method
            auto_type     = $autoType
            install_title_id       = $installTitleId
            expected_base_title_id = $expectedBaseTitleId
            product_code  = if ($info) { $info.ProductCode } else { "" }
            title_id      = if ($info -and $info.TitleId) { $info.TitleId } elseif ($installTitleId) { $installTitleId } else { "" }
            program_id    = if ($info) { $info.ProgramId } else { "" }
            internal_name = if ($info) { $info.InternalName } else { "" }
            crypto_key    = if ($info) { $info.CryptoKey } else { "" }
            cxi_path      = if (Test-Path $outCxiPath) { $outCxiPath } else { "" }
            cci_path      = if (Test-Path $outCciPath) { $outCciPath } else { "" }
            install_cia_path = if (Test-Path -LiteralPath $outInstallCiaPath) { $outInstallCiaPath } else { "" }
            loose_install_path = $looseInstallPath
            log_dir       = $logDir
        })

        if ($KeepWork -or $status -eq "BAD") {
            Write-Host "  [WORK] $work"
        }
        elseif (Test-Path -LiteralPath $work) {
            Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue
        }
        Write-Host ""
    }
}

if ($ReportCsv) {
    $ReportRows | Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
    Write-Host "[REPORT] $ReportPath"
}
else {
    Write-Host "[REPORT] CSV disabled. Use -ReportCsv to export report."
}