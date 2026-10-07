<#
.SYNOPSIS
  Builds WinScarier.sln (a self-contained Scarier.exe, with Windows Glk
  linked in statically) with MSBuild, first setting up the third-party
  libraries that Windows Glk expects.

.DESCRIPTION
  Windows Glk's project file hard-codes ..\..\..\Libraries\<name> paths, and
  Libraries is itself a submodule (DavidKinder/Libraries), so the third-party
  sources live in upstream\libs\ as submodules of this repository and are
  linked into Libraries\ with directory junctions.  Before building, this
  script makes sure that:

    * zlib, libpng, libogg, libvorbis and minimp3 are junctioned into Libraries\,
    * libpng's pnglibconf.h exists, with the write-side features removed,
    * a static 32-bit libjpeg-turbo has been built into Libraries\jpeg with CMake.

  Each step does nothing if it's already done.  The script does not touch the
  submodules themselves; clone with --recurse-submodules, or run
  "git submodule update --init" first.

  The output goes to bin\<Configuration>\.

.PARAMETER Configuration
  Release or Debug.  Default: Release.

.PARAMETER Rebuild
  Clean and build everything instead of building incrementally.

.PARAMETER Clean
  Delete the build outputs without building.
#>
[CmdletBinding()]
param(
  [ValidateSet('Release', 'Debug')] [string] $Configuration = 'Release',
  [switch] $Rebuild,
  [switch] $Clean
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$Root = $PSScriptRoot
$Libraries = Join-Path $Root 'upstream\DavidKinder\Libraries'
$Libs = Join-Path $Root 'upstream\libs'

function Invoke-Native {
  param([string] $Exe, [string[]] $Arguments)
  & $Exe @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "$Exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE"
  }
}

function Find-VisualStudio {
  $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
  if (-not (Test-Path $vswhere)) {
    throw 'vswhere.exe not found; install Visual Studio with "Desktop development with C++".'
  }
  $path = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
  if (-not $path) {
    throw 'No Visual Studio installation with the C++ toolset was found.'
  }
  return $path
}

function Find-CMake {
  param([string] $VsPath)
  $bundled = Join-Path $VsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'
  if (Test-Path $bundled) { return $bundled }
  $onPath = Get-Command cmake -ErrorAction SilentlyContinue
  if ($onPath) { return $onPath.Source }
  throw 'CMake not found; install the "C++ CMake tools for Windows" Visual Studio component.'
}

$vs = Find-VisualStudio

if (-not $Clean) {
  $submodules = @(
    (Join-Path $Root 'upstream\spatterlight'),
    (Join-Path $Root 'upstream\DavidKinder\Adv\Glk'),
    $Libraries
  ) + @('zlib', 'libpng', 'libogg', 'libvorbis', 'minimp3', 'libjpeg-turbo' |
    ForEach-Object { Join-Path $Libs $_ })
  $empty = @($submodules | Where-Object { -not (Get-ChildItem $_ -Force -ErrorAction SilentlyContinue) })
  if ($empty) {
    throw "Submodule $($empty[0]) is not checked out; run: git submodule update --init"
  }

  foreach ($name in 'zlib', 'libpng', 'libogg', 'libvorbis', 'minimp3') {
    $link = Join-Path $Libraries $name
    if (Test-Path $link) {
      if ((Get-Item $link -Force).LinkType -ne 'Junction') {
        throw "$link exists and is not a junction; move it aside and re-run."
      }
      continue
    }
    Write-Host "==> Junction Libraries\$name -> upstream\libs\$name"
    New-Item -ItemType Junction -Path $link -Target (Join-Path $Libs $name) | Out-Null
  }

  $pngDir = Join-Path $Libs 'libpng'
  $pngConf = Join-Path $pngDir 'pnglibconf.h'
  $wanted = Get-Content (Join-Path $pngDir 'scripts\pnglibconf.h.prebuilt') |
    Where-Object { $_ -notmatch '^#define PNG_(SAVE|SIMPLIFIED_WRITE|WRITE)_' }
  # Rewriting an unchanged file would make MSBuild recompile libpng and relink Glk.dll.
  $current = if (Test-Path $pngConf) { Get-Content $pngConf } else { @() }
  if (Compare-Object @($wanted) @($current) -SyncWindow 0) {
    Write-Host '==> libpng pnglibconf.h'
    $wanted | Set-Content -Encoding ascii $pngConf
  }

  if (-not (Test-Path (Join-Path $Libraries 'jpeg\lib32\jpeg-static.lib'))) {
    $cmake = Find-CMake $vs
    $buildDir = Join-Path $Root 'build\libjpeg-turbo'
    $simd = if (Get-Command nasm -ErrorAction SilentlyContinue) { 'ON' } else { 'OFF' }
    Write-Host "==> libjpeg-turbo, using $cmake (SIMD $simd)"
    Invoke-Native $cmake @(
      '-S', (Join-Path $Libs 'libjpeg-turbo'),
      '-B', $buildDir,
      '-A', 'Win32',
      "-DCMAKE_INSTALL_PREFIX=$(Join-Path $Libraries 'jpeg')",
      '-DCMAKE_INSTALL_LIBDIR=lib32',
      '-DENABLE_SHARED=OFF',
      '-DWITH_TURBOJPEG=OFF',
      "-DWITH_SIMD=$simd"
    )
    Invoke-Native $cmake @('--build', $buildDir, '--config', 'Release', '--target', 'install')
  }
}

$target = if ($Clean) { 'Clean' } elseif ($Rebuild) { 'Rebuild' } else { 'Build' }

Write-Host "==> MSBuild WinScarier.sln ($target $Configuration|x86)"
$msbuild = Join-Path $vs 'MSBuild\Current\Bin\MSBuild.exe'
Invoke-Native $msbuild @(
  (Join-Path $Root 'WinScarier.sln'),
  "/t:$target", '/m', '/nologo', '/v:minimal',
  "/p:Configuration=$Configuration", '/p:Platform=x86'
)
if (-not $Clean) {
  Write-Host "Built $(Join-Path $Root "bin\$Configuration\Scarier.exe")"
}
