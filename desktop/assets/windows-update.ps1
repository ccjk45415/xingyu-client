param(
    [Parameter(Mandatory=$true)][ValidateSet('Prepare','Apply')][string]$Mode,
    [Parameter(Mandatory=$true)][string]$Job,
    [switch]$NoRestart
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2
Add-Type -AssemblyName System.IO.Compression.FileSystem

function Inside([string]$Root, [string]$Relative) {
    $base = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    $path = [IO.Path]::GetFullPath((Join-Path $base $Relative))
    if (-not $path.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) { throw 'Path escapes bundle' }
    return $path
}
function Plain([string]$Path) {
    $cursor = [IO.Path]::GetFullPath($Path)
    while ($cursor) {
        if (Test-Path -LiteralPath $cursor) {
            if ((Get-Item -Force -LiteralPath $cursor).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Linked update paths are not supported'
            }
        }
        $next = [IO.Path]::GetDirectoryName($cursor)
        if ($next -eq $cursor) { break }
        $cursor = $next
    }
}
function Hash([string]$Path) {
    $stream = [IO.File]::OpenRead($Path)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $algorithm.Dispose() }
}

$work = Split-Path -Parent ([IO.Path]::GetFullPath($Job))
$stage = Inside $work 'stage'
$backup = Inside $work 'backup'
$ready = Inside $work 'ready.json'
$changed = New-Object System.Collections.Generic.List[object]
$applying = $false
$lock = $null
try {
    Plain $Job
    $config = Get-Content -Raw -Encoding UTF8 -LiteralPath $Job | ConvertFrom-Json
    $install = [IO.Path]::GetFullPath($config.install).TrimEnd('\')
    Plain $install
    if (-not (Test-Path -LiteralPath (Inside $install 'Xingyu.exe') -PathType Leaf)) { throw 'Installed application missing' }
    if ($config.versionName -notmatch '^\d+\.\d+\.\d+$' -or $config.sha256 -notmatch '^[a-f0-9]{64}$') { throw 'Invalid release metadata' }
    if ($Mode -eq 'Prepare') {
        $probe = Inside $install ('.xingyu-write-test-' + [Guid]::NewGuid().ToString('N'))
        [IO.File]::WriteAllText($probe, '')
        Remove-Item -LiteralPath $probe
        Plain $config.archive
        if ((Hash $config.archive) -ne $config.sha256) { throw 'Archive checksum mismatch' }
        if (Test-Path -LiteralPath $stage) { throw 'Staging directory already exists' }
        [IO.Directory]::CreateDirectory($stage) | Out-Null
        $archive = [IO.Compression.ZipFile]::OpenRead($config.archive)
        try {
            $files = New-Object System.Collections.Generic.List[object]
            $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
            $prefix = 'Xingyu-Windows-' + $config.versionName + '/'
            [long]$expanded = 0
            foreach ($entry in $archive.Entries) {
                if ($archive.Entries.Count -gt 10000) { throw 'Too many entries' }
                $name = $entry.FullName
                if (-not $name.StartsWith($prefix, [StringComparison]::Ordinal) -or $name.Contains('\')) { throw 'Unexpected archive root' }
                $relative = $name.Substring($prefix.Length)
                if (-not $relative) { continue }
                if ($relative -match '(^|/)(\.|\.\.)(/|$)|[:\x00-\x1f]' -or $relative.Contains('//')) { throw 'Invalid entry path' }
                foreach ($segment in $relative.TrimEnd('/').Split('/')) {
                    if ($segment.EndsWith('.') -or $segment.EndsWith(' ') -or $segment -match '^(CON|PRN|AUX|NUL|COM[0-9]|LPT[0-9])(\.|$)') { throw 'Invalid Windows filename' }
                }
                if ((($entry.ExternalAttributes -shr 16) -band 0xF000) -eq 0xA000) { throw 'Archive contains a symlink' }
                $target = Inside $stage $relative
                if ($name.EndsWith('/')) { [IO.Directory]::CreateDirectory($target) | Out-Null; continue }
                if (-not $seen.Add($relative)) { throw 'Duplicate archive entry' }
                $expanded += $entry.Length
                if ($expanded -gt 600MB) { throw 'Expanded bundle too large' }
                [IO.Directory]::CreateDirectory((Split-Path -Parent $target)) | Out-Null
                [IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $target, $false)
                $destination = Inside $install $relative
                Plain $destination
                # Verify write access and file locks before terminating the app.
                if (Test-Path -LiteralPath $destination -PathType Leaf) {
                    if ($relative -ne 'Xingyu.exe') {
                        # Loaded DLLs are normally locked by our own process;
                        # replacement is deferred until that process exits.
                        $item = Get-Item -LiteralPath $destination
                        if ($item.IsReadOnly) { throw 'A managed file is read-only' }
                    }
                }
                $files.Add(@{path=$relative; sha256=(Hash $target)})
            }
            foreach ($required in @('Xingyu.exe','flutter_windows.dll','msvcp140.dll','vcruntime140.dll','vcruntime140_1.dll','data/app.so','data/icudtl.dat','data/flutter_assets/NOTICES.Z','VERSION.json')) {
                if (-not $seen.Contains($required)) { throw 'Incomplete application bundle' }
            }
            $version = Get-Content -Raw -Encoding UTF8 -LiteralPath (Inside $stage 'VERSION.json') | ConvertFrom-Json
            if ($version.product -ne 'moe.cangku.xingyu.desktop' -or $version.platform -ne 'windows-x64' -or
                $version.versionCode -ne $config.versionCode -or $version.versionName -ne $config.versionName) { throw 'Bundle version mismatch' }
            @{files=@($files.ToArray()); versionCode=$config.versionCode; versionName=$config.versionName} |
                ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 -LiteralPath $ready
        } finally { $archive.Dispose() }
        exit 0
    }
    $prepared = Get-Content -Raw -Encoding UTF8 -LiteralPath $ready | ConvertFrom-Json
    if ($prepared.versionCode -ne $config.versionCode -or $prepared.versionName -ne $config.versionName) { throw 'Prepared version mismatch' }
    foreach ($file in $prepared.files) {
        $source = Inside $stage $file.path
        Plain $source
        if ((Hash $source) -ne $file.sha256) { throw 'Staged file changed' }
        Plain (Inside $install $file.path)
    }
    if ([int]$config.parentPid -gt 0) {
        $parent = Get-Process -Id ([int]$config.parentPid) -ErrorAction SilentlyContinue
        if ($parent -and -not $parent.WaitForExit(60000)) { throw 'Application did not exit' }
    }
    $lock = [IO.File]::Open((Inside $install '.xingyu-update.lock'), [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    $applying = $true
    foreach ($file in $prepared.files) {
        $destination = Inside $install $file.path
        $saved = Inside $backup $file.path
        Plain $destination
        $existing = Test-Path -LiteralPath $destination -PathType Leaf
        if ($existing) {
            [IO.Directory]::CreateDirectory((Split-Path -Parent $saved)) | Out-Null
            Move-Item -LiteralPath $destination -Destination $saved
        }
        $changed.Add(@{path=$file.path; existing=$existing})
        [IO.Directory]::CreateDirectory((Split-Path -Parent $destination)) | Out-Null
        Copy-Item -LiteralPath (Inside $stage $file.path) -Destination $destination
        if ((Hash $destination) -ne $file.sha256) { throw 'Installed file verification failed' }
    }
    $lock.Dispose(); $lock = $null
    @{status='installed'; version=$config.versionName} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Inside $work 'result.json')
    if (-not $NoRestart) { Start-Process -FilePath (Inside $install 'Xingyu.exe') -WorkingDirectory $install }
    exit 0
} catch {
    if ($NoRestart) { Write-Host $_.Exception.Message; Write-Host $_.ScriptStackTrace }
    if ($applying) {
        for ($index=$changed.Count-1; $index -ge 0; $index--) {
            $item = $changed[$index]
            $destination = Inside $install $item.path
            Plain $destination
            if (Test-Path -LiteralPath $destination -PathType Leaf) { Remove-Item -LiteralPath $destination }
            if ($item.existing) { Move-Item -LiteralPath (Inside $backup $item.path) -Destination $destination }
        }
    }
    if ($lock) { $lock.Dispose() }
    # Local status contains no account information, server data or request text.
    @{status='failed'; rolled_back=$applying} | ConvertTo-Json | Set-Content -Encoding UTF8 -LiteralPath (Inside $work 'result.json')
    Write-Error 'Update could not be completed; managed files were restored.' -ErrorAction Continue
    if ($Mode -eq 'Apply' -and -not $NoRestart) {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show('Update failed. The previous version has been restored. Please try again.', 'Xingyu') | Out-Null
        Start-Process -FilePath (Inside $install 'Xingyu.exe') -WorkingDirectory $install
    }
    exit 1
}
