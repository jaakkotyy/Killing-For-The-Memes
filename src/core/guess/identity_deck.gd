class_name IdentityDeck
extends RefCounted
## Deals secret identities from a pack. Only the [member pool_size] best known entries are
## dealt (everyone should have heard of their identity), while the terminal searches the
## whole pack. No identity is dealt twice until the pool runs out.

const DEFAULT_POOL_SIZE: int = 300

var pool_size: int

var _pool: PackedStringArray = []
var _order: PackedStringArray = []
var _rng: RandomNumberGenerator


func _init(pack: IdentityPack, rng: RandomNumberGenerator = null, p_pool_size: int = DEFAULT_POOL_SIZE) -> void:
	_rng = rng if rng != null else RandomNumberGenerator.new()
	pool_size = maxi(1, p_pool_size)
	var ranked: Array[IdentityPack.Entry] = pack.entries().duplicate()
	ranked.sort_custom(func(a: IdentityPack.Entry, b: IdentityPack.Entry) -> bool:
		return a.fame > b.fame if a.fame != b.fame else a.id < b.id)
	for i: int in range(mini(pool_size, ranked.size())):
		_pool.append(ranked[i].id)


func size() -> int:
	return _pool.size()


## [param count] different entry ids (fewer only if the pool is smaller than that).
func deal(count: int) -> PackedStringArray:
	var hand: PackedStringArray = []
	while hand.size() < mini(count, _pool.size()):
		if _order.is_empty():
			_reshuffle(hand)
		var id: String = _order[_order.size() - 1]
		_order.remove_at(_order.size() - 1)
		if not hand.has(id):
			hand.append(id)
	return hand


## Refills the order with the whole pool, never starting with ids already in [param hand].
func _reshuffle(hand: PackedStringArray) -> void:
	var shuffled: Array[String] = []
	shuffled.assign(_pool)
	# Fisher-Yates with the injected RNG so matches are reproducible from a seed.
	for i: int in range(shuffled.size() - 1, 0, -1):
		var j: int = _rng.randi_range(0, i)
		var swap: String = shuffled[i]
		shuffled[i] = shuffled[j]
		shuffled[j] = swap
	var fresh: Array[String] = []
	fresh.assign(shuffled.filter(func(id: String) -> bool: return not hand.has(id)))
	_order = PackedStringArray(fresh)
