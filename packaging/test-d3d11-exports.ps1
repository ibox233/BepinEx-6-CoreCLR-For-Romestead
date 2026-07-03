param(
    [string] $ShimPath = (Join-Path $PSScriptRoot "..\Native\Romestead.D3D11Shim\target\release\romestead_d3d11_shim.dll"),
    [string] $SystemD3D11Path = (Join-Path $env:WINDIR "System32\d3d11.dll")
)

$ErrorActionPreference = "Stop"

function Get-PeExports {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    $bytes = [IO.File]::ReadAllBytes((Resolve-Path -LiteralPath $Path).Path)

    function Read-UInt16([int] $Offset) {
        [BitConverter]::ToUInt16($bytes, $Offset)
    }

    function Read-UInt32([int] $Offset) {
        [BitConverter]::ToUInt32($bytes, $Offset)
    }

    function Read-Int32([int] $Offset) {
        [BitConverter]::ToInt32($bytes, $Offset)
    }

    function Read-CString([int] $Offset) {
        $end = $Offset
        while ($bytes[$end] -ne 0) {
            $end++
        }

        [Text.Encoding]::ASCII.GetString($bytes, $Offset, $end - $Offset)
    }

    $peHeader = Read-Int32 0x3c
    $sectionCount = Read-UInt16 ($peHeader + 6)
    $optionalHeader = $peHeader + 24
    $optionalHeaderSize = Read-UInt16 ($peHeader + 20)
    $magic = Read-UInt16 $optionalHeader
    $dataDirectory = if ($magic -eq 0x20b) { $optionalHeader + 112 } else { $optionalHeader + 96 }
    $exportRva = Read-UInt32 $dataDirectory

    if ($exportRva -eq 0) {
        return @()
    }

    $sectionTable = $optionalHeader + $optionalHeaderSize
    $sections = for ($i = 0; $i -lt $sectionCount; $i++) {
        $section = $sectionTable + (40 * $i)
        [pscustomobject]@{
            VirtualAddress = Read-UInt32 ($section + 12)
            VirtualSize = Read-UInt32 ($section + 8)
            RawSize = Read-UInt32 ($section + 16)
            RawPointer = Read-UInt32 ($section + 20)
        }
    }

    function Convert-RvaToOffset([uint32] $Rva) {
        foreach ($section in $sections) {
            $size = [Math]::Max($section.VirtualSize, $section.RawSize)
            if ($Rva -ge $section.VirtualAddress -and $Rva -lt ($section.VirtualAddress + $size)) {
                return [int] ($section.RawPointer + ($Rva - $section.VirtualAddress))
            }
        }

        throw "RVA was not found in PE sections: $Rva"
    }

    $exportDirectory = Convert-RvaToOffset $exportRva
    $nameCount = Read-UInt32 ($exportDirectory + 24)
    $nameTableRva = Read-UInt32 ($exportDirectory + 32)
    $nameTable = Convert-RvaToOffset $nameTableRva

    for ($i = 0; $i -lt $nameCount; $i++) {
        $nameRva = Read-UInt32 ($nameTable + (4 * $i))
        Read-CString (Convert-RvaToOffset $nameRva)
    }
}

$systemExports = @(Get-PeExports -Path $SystemD3D11Path | Sort-Object)
$shimExports = @(Get-PeExports -Path $ShimPath | Sort-Object)
$missingExports = @($systemExports | Where-Object { $_ -notin $shimExports })
$extraExports = @($shimExports | Where-Object { $_ -notin $systemExports })

[pscustomobject]@{
    SystemD3D11 = (Resolve-Path -LiteralPath $SystemD3D11Path).Path
    Shim = (Resolve-Path -LiteralPath $ShimPath).Path
    SystemExportCount = $systemExports.Count
    ShimExportCount = $shimExports.Count
    MissingExports = if ($missingExports) { $missingExports -join ", " } else { "<none>" }
    ExtraExports = if ($extraExports) { $extraExports -join ", " } else { "<none>" }
}

if ($missingExports -or $extraExports) {
    throw "Romestead d3d11 shim export list does not match the system d3d11.dll export list."
}
