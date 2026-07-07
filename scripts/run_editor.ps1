$ErrorActionPreference = 'Stop'

$repository = Split-Path -Parent $PSScriptRoot
$godot = Join-Path (Split-Path -Parent $repository) 'tools\godot-4.6.3\godot.exe'
$project = Join-Path $repository 'game\project.godot'

if (-not (Test-Path $godot)) {
    throw "Godot executable not found: $godot"
}

Start-Process -FilePath $godot -ArgumentList '--editor', '--path', (Split-Path $project) -WindowStyle Normal

