$ErrorActionPreference = 'Stop'

$repository = Split-Path -Parent $PSScriptRoot
$scons = Join-Path (Split-Path -Parent $repository) 'tools\scons.cmd'

if (-not (Test-Path $scons)) {
    throw "SCons launcher not found: $scons"
}

Push-Location $repository
try {
    & $scons -Q
    if ($LASTEXITCODE -ne 0) {
        throw "SCons build failed with exit code $LASTEXITCODE"
    }

    & '.\build\bin\province_core_tests.exe'
    if ($LASTEXITCODE -ne 0) {
        throw "Core tests failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}

