# Runs all GUT unit tests headless. Exit code is non-zero if any test fails.
# Usage: .\tools\run_tests.ps1

. "$PSScriptRoot\godot_path.ps1"

# Make sure imports/class caches are up to date before running tests.
& $Godot --headless --path $ProjectRoot --import | Out-Null

& $Godot --headless --path $ProjectRoot -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json
exit $LASTEXITCODE
