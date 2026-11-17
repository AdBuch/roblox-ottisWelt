# Installs the PINNED tools of the release pipeline (release/tools.json) into <repo>/.tools:
# rojo and the Luau runtime (luau, luau-analyze, luau-compile). Every download is a release
# asset of the pinned version, and its SHA-256 must equal the hash in tools.json before it is
# unpacked; an asset without a recorded hash is refused. Used by CI and by anyone who wants
# exactly the pipeline's versions beside an Aftman installation.
#
#   .\scripts\release\Install-Tools.ps1              # rojo + luau
#   .\scripts\release\Install-Tools.ps1 -Tool rojo
param(
    [ValidateSet('all', 'rojo', 'luau')][string]$Tool = 'all',
    [ValidateSet('windows-x86_64', 'linux-x86_64')][string]$Platform
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'ReleaseCommon.ps1')

$root = Get-RepoRoot
$tools = Get-PinnedTools $root
$dir = Get-ToolsDir $root
New-Item -ItemType Directory -Force -Path $dir | Out-Null
if (-not $Platform) {
    # Windows PowerShell 5.1 has no $IsLinux: ask the runtime
    $onWindows = [System.Runtime.InteropServices.RuntimeInformation]::IsOSPlatform([System.Runtime.InteropServices.OSPlatform]::Windows)
    $Platform = if ($onWindows) { 'windows-x86_64' } else { 'linux-x86_64' }
}

function Install-One([string]$Name) {
    $spec = $tools.$Name
    $asset = $spec.assets.$Platform
    if (-not $asset) { Fail "$Name has no asset for $Platform in release/tools.json" }
    if ([string]::IsNullOrWhiteSpace($asset.sha256)) { Fail ("$Name " + $spec.version + " (" + $asset.file + "): no SHA-256 recorded in release/tools.json. Verify a download by hand and fill it in (docs/RELEASE_PROCESS.md, Tools).") }
    $tag = if ($Name -eq 'rojo') { 'v' + $spec.version } else { $spec.version }
    $url = "https://github.com/$($spec.repository)/releases/download/$tag/$($asset.file)"
    $zip = Join-Path $dir $asset.file
    Write-Step ("$Name " + $spec.version + " from " + $url)
    $previous = $ProgressPreference
    $ProgressPreference = 'SilentlyContinue'
    try { Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing } finally { $ProgressPreference = $previous }
    $hash = Get-Sha256 $zip
    if ($hash -ne $asset.sha256.ToLowerInvariant()) {
        Remove-Item -LiteralPath $zip -Force
        Fail ("$Name download hash " + $hash + " does not equal the pinned " + $asset.sha256 + ". Not installed.")
    }
    Write-Ok ("sha256 " + $hash)
    Expand-Archive -LiteralPath $zip -DestinationPath $dir -Force
    Remove-Item -LiteralPath $zip -Force
    if ($Platform -eq 'linux-x86_64') {
        foreach ($bin in @('rojo', 'luau', 'luau-analyze', 'luau-compile')) {
            $p = Join-Path $dir $bin
            if (Test-Path -LiteralPath $p) { & chmod +x $p }
        }
    }
    Write-Ok ("installed into " + $dir)
}

if ($Tool -in @('all', 'rojo')) { Install-One 'rojo' }
if ($Tool -in @('all', 'luau')) { Install-One 'luau' }
if ($Tool -in @('all', 'rojo')) {
    $rojo = Join-Path $dir $(if ($Platform -eq 'windows-x86_64') { 'rojo.exe' } else { 'rojo' })
    $v = Get-RojoVersion $rojo
    if ($v -ne $tools.rojo.version) { Fail "installed rojo reports $v, pinned is $($tools.rojo.version)" }
    Write-Ok ("rojo --version: " + $v)
}
