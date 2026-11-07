class_name IdentityQuery
extends RefCounted
## A terminal search: filters that must all hold, a name search, and the candidates the
## player crossed out by hand. Results come in fame order (best known first), so the
## likely answers are at the top.

var filters: Array[IdentityFilter] = []
## Case-insensitive substring of the name; "" matches everything.
var text: String = ""
## Entry ids the player crossed out.
var struck: Dictionary = {}  # entry id -> true
## Crossed-out entries stay in the results (greyed, at the end) instead of disappearing.
var keep_struck: bool = true


func add_filter(filter: IdentityFilter) -> void:
	if filter != null:
		filters.append(filter)


func remove_filter(index: int) -> void:
	if index >= 0 and index < filters.size():
		filters.remove_at(index)


func toggle_struck(entry_id: String) -> void:
	if struck.has(entry_id):
		struck.erase(entry_id)
	else:
		struck[entry_id] = true


func is_struck(entry_id: String) -> bool:
	return struck.has(entry_id)


func clear() -> void:
	filters.clear()
	text = ""
	struck.clear()


func matches(entry: IdentityPack.Entry) -> bool:
	if not text.is_empty() and entry.name.findn(text.strip_edges()) == -1:
		return false
	for filter: IdentityFilter in filters:
		if not filter.matches(entry):
			return false
	return true


## The matching entries: best known first, crossed-out ones last (or left out).
func run(pack: IdentityPack) -> Array[IdentityPack.Entry]:
	var open: Array[IdentityPack.Entry] = []
	var crossed: Array[IdentityPack.Entry] = []
	for entry: IdentityPack.Entry in pack.entries():
		if not matches(entry):
			continue
		if struck.has(entry.id):
			if keep_struck:
				crossed.append(entry)
		else:
			open.append(entry)
	var by_fame: Callable = func(a: IdentityPack.Entry, b: IdentityPack.Entry) -> bool:
		return a.fame > b.fame if a.fame != b.fame else a.name < b.name
	open.sort_custom(by_fame)
	crossed.sort_custom(by_fame)
	return open + crossed


## How many candidates are still open (matching and not crossed out).
func count_open(pack: IdentityPack) -> int:
	var count: int = 0
	for entry: IdentityPack.Entry in pack.entries():
		if not struck.has(entry.id) and matches(entry):
			count += 1
	return count
