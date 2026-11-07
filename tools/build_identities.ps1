# Rebuilds guess mode's identity packs (data/identities/*.json) from Wikidata.
# Needs Python 3 and internet. Raw answers are cached in .identity_cache/.
# Usage: .\tools\build_identities.ps1 [musicians|movies ...] [-Fresh]

param(
    [string[]]$Packs = @(),
    [switch]$Fresh
)

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$arguments = @("-I", (Join-Path $PSScriptRoot "build_identities.py")) + $Packs
if ($Fresh) { $arguments += "--fresh" }
& python @arguments
exit $LASTEXITCODE
