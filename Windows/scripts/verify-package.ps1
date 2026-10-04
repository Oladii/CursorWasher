$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path $PSScriptRoot -Parent
$exe = Join-Path $windowsRoot 'App\CursorWasher.exe'
$metadata = [Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
if ($metadata.ProductName -cne 'CursorWasher') { throw 'The EXE must identify its product as CursorWasher.' }
if ($metadata.FileVersion -notmatch '^\d+\.\d+\.\d+\.\d+$') { throw 'Invalid executable version.' }
if (Test-Path -LiteralPath ($exe + '.config')) { throw 'The portable app must not require a config file.' }
$zip = Join-Path $windowsRoot '.build\Packages\CursorWasher.zip'
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [IO.Compression.ZipFile]::OpenRead($zip)
try {
    $expected = @('CursorWasher.exe', 'START.txt', 'LICENSE.txt')
    $names = @($archive.Entries | ForEach-Object FullName)
    if ($names.Count -ne $expected.Count -or @(Compare-Object $expected $names).Count -ne 0) {
        throw 'The ZIP must contain only the app, launch instructions and license.'
    }
    foreach ($name in $expected) {
        $stream = $archive.GetEntry($name).Open()
        $hasher = [Security.Cryptography.SHA256]::Create()
        try { $digest = [BitConverter]::ToString($hasher.ComputeHash($stream)).Replace('-', '') }
        finally { $stream.Dispose(); $hasher.Dispose() }
        if ($digest -ne (Get-FileHash -LiteralPath (Join-Path $windowsRoot ('App\' + $name)) -Algorithm SHA256).Hash) {
            throw "The ZIP contains a stale file: $name"
        }
    }
} finally { $archive.Dispose() }
Write-Output "Verified: $($metadata.ProductName) $($metadata.FileVersion); EXE, instructions and license match the ZIP."
