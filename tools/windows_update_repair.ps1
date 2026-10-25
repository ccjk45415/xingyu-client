param([string]$InstallPath, [string]$Package, [switch]$NoRestart)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
try {
    if (-not $Package) { $Package = Join-Path $PSScriptRoot 'Xingyu-Windows-0.7.0-x64.zip' }
    $Package = [IO.Path]::GetFullPath($Package)
    $expected = '819e915410b270d51a5ea6cebc7aa94d17bb15388b1ebb802598fa9b45de7413'
    $stream = [IO.File]::OpenRead($Package)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { $actual = [BitConverter]::ToString($algorithm.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
    finally { $stream.Dispose(); $algorithm.Dispose() }
    if ($actual -ne $expected) { throw '安装包校验失败，请使用原始的 0.7.0 安装包。' }
    if (-not $InstallPath) {
        $picker = New-Object Windows.Forms.OpenFileDialog
        $picker.Title = '选择原来启动星屿的 Xingyu.exe（请先保存内容并退出客户端）'
        $picker.Filter = '星屿客户端 (Xingyu.exe)|Xingyu.exe'
        $picker.InitialDirectory = [Environment]::GetFolderPath('Desktop')
        if ($picker.ShowDialog() -ne [Windows.Forms.DialogResult]::OK) { exit 0 }
        $InstallPath = [IO.Path]::GetDirectoryName($picker.FileName)
    }
    $InstallPath = [IO.Path]::GetFullPath($InstallPath)
    $exe = Join-Path $InstallPath 'Xingyu.exe'
    if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw '所选目录没有 Xingyu.exe。' }
    foreach ($app in @(Get-Process -Name Xingyu -ErrorAction SilentlyContinue)) {
        if ($app.Path -and [IO.Path]::GetFullPath($app.Path) -eq $exe) {
            throw '请先保存正在编辑的内容，完全退出星屿，再运行修复工具。工具不会强制关闭客户端。'
        }
    }
    $versionFile = Join-Path $InstallPath 'VERSION.json'
    if (Test-Path -LiteralPath $versionFile) {
        $version = Get-Content -LiteralPath $versionFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ([int]$version.versionCode -gt 27) { throw '当前版本高于 0.7.0，此工具不会降级客户端。' }
    }
    $work = Join-Path ([IO.Path]::GetTempPath()) ('xingyu-update-repair-' + [Guid]::NewGuid().ToString('N'))
    [IO.Directory]::CreateDirectory($work) | Out-Null
    $job = Join-Path $work 'job.json'
    @{archive=$Package;install=$InstallPath;parentPid=0;versionName='0.7.0';versionCode=27;sha256=$expected} |
        ConvertTo-Json | Set-Content -LiteralPath $job -Encoding UTF8
    $engine = Join-Path $PSScriptRoot 'windows-update-repair-engine.ps1'
    & $engine -Mode Prepare -Job $job -NoRestart
    if ($LASTEXITCODE -ne 0) { throw '准备更新失败，原客户端未被替换。' }
    & $engine -Mode Apply -Job $job -NoRestart
    if ($LASTEXITCODE -ne 0) { throw '更新失败，已尝试恢复原版本。请保留临时目录中的 result.json 以便排查。' }
    if (-not $NoRestart) {
        $start = New-Object Diagnostics.ProcessStartInfo
        $start.FileName = $exe
        $start.WorkingDirectory = $InstallPath
        $start.UseShellExecute = $true
        [Diagnostics.Process]::Start($start) | Out-Null
    }
    Write-Output 'Installed official Windows 0.7.0 (27).'
    exit 0
} catch {
    if ($NoRestart) { Write-Error $_ -ErrorAction Continue }
    else { [Windows.Forms.MessageBox]::Show($_.Exception.Message, '星屿更新修复') | Out-Null }
    exit 1
}
