extends Node
## Global access to the active PlatformService (autoload "Platform").
## Swap in a SteamPlatform here once GodotSteam is integrated.

var service: PlatformService = NullPlatform.new()
