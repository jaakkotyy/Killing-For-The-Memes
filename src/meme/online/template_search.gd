class_name TemplateSearch
extends Node
## Template search on the host, for every player: Imgflip's template search plus GIPHY
## (with the host's key, which never leaves the host), or the fresh memes of a subreddit
## when the query is "r/<name>". Players send only the query; the host answers with
## validated catalogue entries, which the player's client validates again.

signal finished(peer_id: int, query: String, entries: Array[Dictionary])

const MAX_QUERY_LENGTH: int = 60
const MAX_RESULTS: int = 40
const GIPHY_RESULTS: int = 20
const REDDIT_RESULTS: int = 40
## One search per player at a time, and no more than one a second.
const MIN_INTERVAL_MSEC: int = 1000

## The host's GIPHY key; empty searches Imgflip only. Never logged.
var giphy_api_key: String = ""

var _busy: Dictionary = {}  # peer id -> true while their search runs
var _last_msec: Dictionary = {}  # peer id -> when their last search started


## A query from an untrusted source, cleaned; "" if there is nothing to search for.
static func clean_query(query: Variant) -> String:
	return MemeSpec.sanitize_caption(query).substr(0, MAX_QUERY_LENGTH).strip_edges()


## Searches for [param peer_id]; [signal finished] answers, with nothing for a refused or
## empty query, so the player's editor never waits forever.
func request(peer_id: int, query: Variant) -> void:
	var clean: String = clean_query(query)
	var now: int = Time.get_ticks_msec()
	if clean.is_empty() or _busy.has(peer_id) or now - int(_last_msec.get(peer_id, -MIN_INTERVAL_MSEC)) < MIN_INTERVAL_MSEC:
		finished.emit(peer_id, clean, [] as Array[Dictionary])
		return
	_busy[peer_id] = true
	_last_msec[peer_id] = now
	var entries: Array[Dictionary] = await search(clean)
	_busy.erase(peer_id)
	finished.emit(peer_id, clean, entries)


func search(query: String) -> Array[Dictionary]:
	var subreddit: String = RedditCatalogue.subreddit_in(query)
	if not subreddit.is_empty():
		var reddit: PackedStringArray = await HttpText.fetch_all(self, [RedditCatalogue.api_url(subreddit, REDDIT_RESULTS)])
		return RedditCatalogue.parse_response(reddit[0], MAX_RESULTS)
	var urls: PackedStringArray = [ImgflipCatalogue.search_url(query)]
	if not giphy_api_key.is_empty():
		urls.append(GiphyCatalogue.search_url(giphy_api_key, query, GIPHY_RESULTS))
	var bodies: PackedStringArray = await HttpText.fetch_all(self, urls)
	var stills: Array[Dictionary] = ImgflipCatalogue.parse_html(bodies[0])
	var gifs: Array[Dictionary] = GiphyCatalogue.parse_response(bodies[1]) if bodies.size() > 1 else [] as Array[Dictionary]
	return interleave(stills, gifs, MAX_RESULTS)


## Stills and GIFs taking turns, so both kinds show near the top.
static func interleave(first: Array[Dictionary], second: Array[Dictionary], limit: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var i: int = 0
	while result.size() < limit and (i < first.size() or i < second.size()):
		if i < first.size():
			result.append(first[i])
		if i < second.size() and result.size() < limit:
			result.append(second[i])
		i += 1
	return result
