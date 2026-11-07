class_name IdentityFilter
extends RefCounted
## One condition on an identity pack's field, e.g. "born before 1980" or "genres has
## rock". The terminal combines them into an IdentityQuery; stock questions carry one as
## what a "Yes" means, and negated() is what a "No" means.
##
## An entry whose field is unknown is kept by every filter: missing data must never
## cross out the right answer.

## Operators per field type, in pairs that negate each other.
const OPS: Dictionary = {
	"enum": ["is", "is_not"],
	"year": ["before", "from", "between", "not_between"],
	"bool": ["is"],
	"tags": ["has", "has_not"],
}
const _NEGATIONS: Dictionary = {
	"is_not": "is", "before": "from", "from": "before", "between": "not_between",
	"not_between": "between", "has": "has_not", "has_not": "has",
}

var field: IdentityPack.Field
var op: String
## String (enum, tags), int (before, from), Vector2i (between, inclusive) or bool.
var value: Variant


func _init(p_field: IdentityPack.Field, p_op: String, p_value: Variant) -> void:
	field = p_field
	op = p_op
	value = p_value


## Builds a filter from untrusted data ({field, op, value}), checked against [param pack].
## Returns null if anything doesn't fit the field.
static func from_untrusted(data: Variant, pack: IdentityPack) -> IdentityFilter:
	if not data is Dictionary:
		return null
	var d: Dictionary = data
	if typeof(d.get("field")) != TYPE_STRING or typeof(d.get("op")) != TYPE_STRING:
		return null
	var target: IdentityPack.Field = pack.get_field(d["field"])
	if target == null or not (OPS[target.type] as Array).has(d["op"]):
		return null
	var operation: String = d["op"]
	var raw: Variant = d.get("value")
	var clean: Variant = null
	if operation in ["between", "not_between"]:
		if raw is Array and (raw as Array).size() == 2:
			var low: Variant = IdentityPack.clean_value("year", raw[0])
			var high: Variant = IdentityPack.clean_value("year", raw[1])
			if low != null and high != null:
				clean = Vector2i(mini(int(low), int(high)), maxi(int(low), int(high)))
	elif target.type == "tags":
		clean = IdentityPack.clean_value("enum", raw)
	else:
		clean = IdentityPack.clean_value(target.type, raw)
	if clean == null:
		return null
	return IdentityFilter.new(target, operation, clean)


## The opposite condition (what a "No" to this filter's question means).
func negated() -> IdentityFilter:
	if op == "is" and field.type == "bool":
		return IdentityFilter.new(field, "is", not bool(value))
	var opposite: String = _NEGATIONS.get(op, "is_not")
	return IdentityFilter.new(field, opposite, value)


func matches(entry: IdentityPack.Entry) -> bool:
	if not entry.has_value(field.id):
		return true
	var actual: Variant = entry.value(field.id)
	match op:
		"is":
			return actual == value
		"is_not":
			return actual != value
		"before":
			return int(actual) < int(value)
		"from":
			return int(actual) >= int(value)
		"between":
			return int(actual) >= (value as Vector2i).x and int(actual) <= (value as Vector2i).y
		"not_between":
			return int(actual) < (value as Vector2i).x or int(actual) > (value as Vector2i).y
		"has":
			return (actual as PackedStringArray).has(value)
		"has_not":
			return not (actual as PackedStringArray).has(value)
	return true


## The filter as data again (what from_untrusted() reads).
func to_dict() -> Dictionary:
	var raw: Variant = value
	if value is Vector2i:
		raw = [(value as Vector2i).x, (value as Vector2i).y]
	return {"field": field.id, "op": op, "value": raw}


## A short label for the terminal's filter chips: "Born before 1980".
func describe() -> String:
	match op:
		"is":
			if field.type == "bool":
				return "%s: %s" % [field.name, "yes" if value else "no"]
			return "%s is %s" % [field.name, value]
		"is_not":
			return "%s is not %s" % [field.name, value]
		"before":
			return "%s before %d" % [field.name, value]
		"from":
			return "%s %d or later" % [field.name, value]
		"between":
			return "%s %d–%d" % [field.name, (value as Vector2i).x, (value as Vector2i).y]
		"not_between":
			return "%s not %d–%d" % [field.name, (value as Vector2i).x, (value as Vector2i).y]
		"has":
			return "%s: %s" % [field.name, value]
		"has_not":
			return "%s: not %s" % [field.name, value]
	return field.name
