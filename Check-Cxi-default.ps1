param(
    [string]$Root = ".\_cxi_out\cxi",
    [switch]$Recurse,
    [string]$OutCsv = ".\_cxi_out\logs\cxi_check_report.csv",
    [string]$Ctrtool = ".\bin\ctrtool.exe"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"


function Parse-HexToInt64 {
    param([string]$HexText)

    if ([string]::IsNullOrWhiteSpace($HexText)) {
        return $null
    }

    $clean = $HexText.Trim()
    if ($clean.StartsWith("0x")) {
        $clean = $clean.Substring(2)
    }

    return [Convert]::ToInt64($clean, 16)
}

function Get-FirstMatch {
    param(
        [string]$Text,
        [string]$Pattern
    )

    $m = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if ($m.Success) {
        return $m.Groups[1].Value.Trim()
    }

    return $null
}

if (-not (Get-Command $Ctrtool -ErrorAction SilentlyContinue)) {
    throw "ctrtool not found. Make sure ctrtool.exe is in PATH or pass -Ctrtool E:\tools\3ds\ctrtool.exe"
}

if ($Recurse) {
    $files = Get-ChildItem -Path $Root -Filter *.cxi -File -Recurse
} else {
    $files = Get-ChildItem -Path $Root -Filter *.cxi -File
}

if (-not $files) {
    Write-Host "[MISS] No .cxi files found in $Root"
    exit 0
}

$rows = @()

foreach ($f in $files) {
    Write-Host "[CXI] $($f.Name)"

    $out = & $Ctrtool $f.FullName 2>&1
    $exitCode = $LASTEXITCODE
    $text = ($out | Out-String)

    $header      = Get-FirstMatch $text "Header:\s+([A-Za-z0-9]+)"
    $titleId     = Get-FirstMatch $text "Title id:\s+([0-9A-Fa-f]+)"
    $programId   = Get-FirstMatch $text "Program id:\s+([0-9A-Fa-f]+)"
    $productCode = Get-FirstMatch $text "Product code:\s+(.+)"
    $name        = Get-FirstMatch $text "Name:\s+(.+)"
    $crypto      = Get-FirstMatch $text "Crypto Key\s+(.+)"
    $formType    = Get-FirstMatch $text "FormType:\s+(.+)"
    $contentType = Get-FirstMatch $text "ContentType:\s+(.+)"
    $contentSizeHex = Get-FirstMatch $text "Content size:\s+(0x[0-9A-Fa-f]+)"
    $exefsHex    = Get-FirstMatch $text "ExeFS size:\s+(0x[0-9A-Fa-f]+)"
    $romfsHex    = Get-FirstMatch $text "RomFS size:\s+(0x[0-9A-Fa-f]+)"

    $contentSize = Parse-HexToInt64 $contentSizeHex
    $exefsSize   = Parse-HexToInt64 $exefsHex
    $romfsSize   = Parse-HexToInt64 $romfsHex

    $issues = New-Object System.Collections.Generic.List[string]

    if ($exitCode -ne 0) {
        $issues.Add("CTRTOOL_EXIT_$exitCode")
    }

    if ($header -ne "NCCH") {
        $issues.Add("NOT_NCCH")
    }

    if ($formType -notmatch "Executable") {
        $issues.Add("NOT_EXECUTABLE")
    }

    if ($contentType -notmatch "Application") {
        $issues.Add("NOT_APPLICATION")
    }

    if ($null -eq $exefsSize -or $exefsSize -le 0) {
        $issues.Add("NO_EXEFS")
    }

    if ($null -eq $romfsSize -or $romfsSize -le 0) {
        $issues.Add("NO_ROMFS")
    }

    if ($crypto -and $crypto -notmatch "^None\b") {
        $issues.Add("ENCRYPTED_OR_SECURE_CRYPTO")
    }

    if ($null -ne $contentSize -and $contentSize -ne $f.Length) {
        $issues.Add("SIZE_MISMATCH")
    }

    if ($issues.Count -eq 0) {
        $status = "OK"
        Write-Host "  [OK] $($f.Name)" -ForegroundColor Green
    } elseif ($issues -contains "ENCRYPTED_OR_SECURE_CRYPTO") {
        $status = "WARN"
        Write-Host "  [WARN] $($issues -join ', ')" -ForegroundColor Yellow
    } else {
        $status = "BAD"
        Write-Host "  [BAD] $($issues -join ', ')" -ForegroundColor Red
    }

    $rows += [pscustomobject]@{
        file          = $f.Name
        status        = $status
        issues        = ($issues -join ";")
        size_bytes    = $f.Length
        content_size  = $contentSize
        header        = $header
        crypto_key    = $crypto
        form_type     = $formType
        content_type  = $contentType
        exefs_size    = $exefsSize
        romfs_size    = $romfsSize
        title_id      = $titleId
        program_id    = $programId
        product_code  = $productCode
        internal_name = $name
        path          = $f.FullName
    }
}

$rows | Sort-Object status,file | Format-Table file,status,issues,crypto_key,product_code,internal_name -AutoSize
$parent = Split-Path -Parent $OutCsv
if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
$rows | Export-Csv -NoTypeInformation -Encoding UTF8 $OutCsv

Write-Host ""
Write-Host "[REPORT] $OutCsv"