class_name Portrait
extends RefCounted
## Where an identity's picture comes from: a Wikimedia Commons file name in the pack
## (`image`), turned into a thumbnail URL on upload.wikimedia.org. The URL is always
## rebuilt here from the file name, never taken from data, so a pack can only ever point
## at Commons thumbnails. Each file has its own license, so the pictures are fetched at
## run time (PortraitCache) and never shipped.

const HOST: String = "https://upload.wikimedia.org/wikipedia/commons/thumb/"
## One of Commons' standard thumbnail widths (other widths may be refused).
const WIDTH: int = 250
const MAX_NAME_LENGTH: int = 200
## Extensions whose thumbnails we can decode; SVGs are rendered to PNG by Commons.
const EXTENSIONS: PackedStringArray = ["jpg", "jpeg", "png", "gif", "svg"]


## The thumbnail URL for Commons file [param file_name] ("Some photo.jpg"), or "" if the
## name isn't a plain file name we can show.
static func url_for(file_name: String) -> String:
	var name: String = file_name.strip_edges().replace(" ", "_")
	if name.is_empty() or name.length() > MAX_NAME_LENGTH:
		return ""
	for bad: String in ["/", "\\", "?", "#", "%", ":", "\n", "\t"]:
		if name.contains(bad):
			return ""
	var extension: String = name.get_extension().to_lower()
	if not EXTENSIONS.has(extension):
		return ""
	var hash: String = name.md5_text()
	var encoded: String = name.uri_encode()
	var thumb: String = "%dpx-%s" % [WIDTH, encoded]
	if extension == "svg":
		thumb += ".png"
	return HOST + "%s/%s/%s/%s" % [hash.substr(0, 1), hash.substr(0, 2), encoded, thumb]
