param([switch]$Test, [switch]$Inspect, [switch]$Diagnostics, [switch]$Package)
$ErrorActionPreference = 'Stop'
$windowsRoot = Split-Path $PSScriptRoot -Parent
$projectRoot = Split-Path $windowsRoot -Parent
$output = Join-Path $windowsRoot 'App'
$buildRoot = Join-Path $windowsRoot '.build'
$intermediate = Join-Path $buildRoot 'Intermediate'
$toolsOutput = Join-Path $buildRoot 'Tools'
$testsOutput = Join-Path $buildRoot 'Tests'
$packagesOutput = Join-Path $buildRoot 'Packages'
if ($Package -and ($Inspect -or $Diagnostics)) { throw 'Package the normal build, without -Inspect or -Diagnostics.' }
if ($Inspect -and $Diagnostics) { throw 'Choose -Inspect or -Diagnostics; -Inspect already includes diagnostic commands.' }
$diagnosticBuild = $Inspect -or $Diagnostics
$variant = 'Release'
$fileName = 'CursorWasher.exe'
if ($Inspect) { $variant = 'Inspection'; $fileName = 'CursorWasher.Inspect.exe' }
elseif ($Diagnostics) { $variant = 'Diagnostics'; $fileName = 'CursorWasher.Diagnostics.exe' }
if ($diagnosticBuild) { $output = Join-Path $buildRoot $variant }
$staging = Join-Path $intermediate $variant
$exe = Join-Path $output $fileName
$compiledExe = Join-Path $staging $fileName
function Assert-AppClosed {
    if (Get-Process 'CursorWasher*' -ErrorAction SilentlyContinue | Where-Object { $_.Path -eq $exe }) {
        throw 'Close CursorWasher using its tray menu before rebuilding.'
    }
}
Assert-AppClosed
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) { throw '.NET Framework 4.x C# compiler was not found.' }
New-Item -ItemType Directory -Path $output, $staging, $toolsOutput -Force | Out-Null
$config = Get-Content (Join-Path $projectRoot 'scripts\project.sh') -Raw
$version = [regex]::Match($config, '(?m)^APP_VERSION="([0-9.]+)"').Groups[1].Value
$build = [regex]::Match($config, '(?m)^APP_BUILD="([0-9]+)"').Groups[1].Value
if (-not $version -or -not $build) { throw 'Cannot read version/build from scripts/project.sh.' }
$metadata = @"
using System.Reflection;
[assembly: AssemblyTitle("CursorWasher for Windows")]
[assembly: AssemblyVersion("$version.$build")]
[assembly: AssemblyFileVersion("$version.$build")]
[assembly: AssemblyInformationalVersion("$version-windows-preview+$build")]
"@
$metadataPath = Join-Path $intermediate 'AssemblyInfo.cs'
[IO.File]::WriteAllText($metadataPath, $metadata)
$sources = @(Get-ChildItem (Join-Path $windowsRoot 'Sources') -Filter '*.cs' -Recurse | Sort-Object FullName | ForEach-Object FullName)
$appSources = $sources
if ($diagnosticBuild) {
    $appSources += @(Get-ChildItem (Join-Path $windowsRoot 'Diagnostics') -Filter '*.cs' -Recurse | Sort-Object FullName | ForEach-Object FullName)
}
$iconWriter = Join-Path $toolsOutput 'IconWriter.exe'
$iconPath = Join-Path $intermediate 'CursorWasher.ico'
& $compiler /nologo /target:exe /reference:System.Drawing.dll ('/out:' + $iconWriter) (Join-Path $windowsRoot 'Tools\IconWriter.cs')
if ($LASTEXITCODE -ne 0) { throw 'Icon converter compilation failed.' }
& $iconWriter (Join-Path $projectRoot 'Resources\app-icon.png') $iconPath
if ($LASTEXITCODE -ne 0) { throw 'Windows icon generation failed.' }
$commonArguments = @('/nologo', '/platform:anycpu', '/warn:4', '/warnaserror+',
    '/reference:System.dll', '/reference:System.Core.dll', '/reference:System.Drawing.dll',
    '/reference:System.Windows.Forms.dll', '/reference:System.Xml.dll', ('/win32manifest:' + (Join-Path $windowsRoot 'app.manifest')))
$arguments = $commonArguments + @('/target:winexe', '/optimize+', ('/win32icon:' + $iconPath), ('/out:' + $compiledExe), $metadataPath) + $appSources
if ($Inspect) { $arguments += '/define:INSPECTION,DIAGNOSTICS' }
elseif ($Diagnostics) { $arguments += '/define:DIAGNOSTICS' }
$resourceArguments = @('bucket-dry.png','water-calm-source.png','water-highlights-source.png','app-icon.png','status-bar-icon.svg') | ForEach-Object {
    $resource = Join-Path $projectRoot ('Resources\' + $_)
    if (-not (Test-Path -LiteralPath $resource)) { $resource = Join-Path $windowsRoot ('Resources\' + $_) }
    '/resource:' + $resource + ',CursorWasher.' + $_
}
$arguments += $resourceArguments
& $compiler @arguments
if ($LASTEXITCODE -ne 0) { throw 'C# compilation failed.' }
[IO.File]::WriteAllText(($compiledExe + '.config'), '<configuration><startup><supportedRuntime version="v4.0" sku=".NETFramework,Version=v4.8" /></startup></configuration>')
if ($Test) {
    New-Item -ItemType Directory -Path $testsOutput -Force | Out-Null
    $testExe = Join-Path $testsOutput 'CursorWasher.Tests.exe'
    $tests = @(Get-ChildItem (Join-Path $windowsRoot 'Tests') -Filter '*.cs' | Sort-Object FullName | ForEach-Object FullName)
    & $compiler @commonArguments /target:exe /main:CursorWasher.Tests ('/out:' + $testExe) @sources @tests @resourceArguments
    if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed.' }
    & $testExe
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed.' }
}
# A failed compile or requested test run must leave the launchable app intact.
Assert-AppClosed
Copy-Item -LiteralPath $compiledExe, ($compiledExe + '.config') -Destination $output -Force
Write-Output "Built: $exe ($version, build $build, Windows preview)"
if (-not $diagnosticBuild) {
    Copy-Item -LiteralPath (Join-Path $windowsRoot 'START.txt') -Destination $output -Force
    $shell = New-Object -ComObject WScript.Shell
    try {
        $shortcutPath = Join-Path $projectRoot 'CursorWasher.lnk'
        $shortcut = $shell.CreateShortcut($shortcutPath)
        try {
            $shortcut.TargetPath = $exe
            $shortcut.WorkingDirectory = $output
            $shortcut.IconLocation = $exe + ',0'
            $shortcut.Description = 'Launch CursorWasher for Windows'
            $shortcut.Save()
        } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shortcut) }
    } finally { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($shell) }
    Write-Output "Launch shortcut: $shortcutPath"
}
if ($Package) {
    New-Item -ItemType Directory -Path $packagesOutput -Force | Out-Null
    $zip = Join-Path $packagesOutput 'CursorWasher.zip'
    # Only these deliverable files, never local logs, settings, or inspection tools.
    Compress-Archive -LiteralPath $exe, ($exe + '.config'), (Join-Path $output 'START.txt') -DestinationPath $zip -Force
    Write-Output "Packaged locally: $zip"
}
