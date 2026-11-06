extends GutTest

const ROUNDTRIP_CASES: Array = [
	["192.168.1.42", 7777],
	["10.0.0.1", 1],
	["255.255.255.255", 65535],
	["0.0.0.0", 7777],
	["100.101.102.103", 40000],
]


func test_encode_decode_roundtrip() -> void:
	for case: Array in ROUNDTRIP_CASES:
		var code: String = JoinCode.encode(case[0], case[1])
		var decoded: Dictionary = JoinCode.decode(code)
		assert_eq(decoded.get("address"), case[0], "address for %s" % code)
		assert_eq(decoded.get("port"), case[1], "port for %s" % code)


func test_code_format_is_two_groups_of_five() -> void:
	var code: String = JoinCode.encode("192.168.1.42", 7777)
	var regex := RegEx.create_from_string("^[0-9A-Z]{5}-[0-9A-Z]{5}$")
	assert_not_null(regex.search(code), "unexpected code format: %s" % code)


func test_decode_is_forgiving_about_case_dashes_and_lookalikes() -> void:
	var code: String = JoinCode.encode("192.168.1.42", 7777)
	var expected: Dictionary = {"address": "192.168.1.42", "port": 7777}
	assert_eq(JoinCode.decode(code.to_lower()), expected)
	assert_eq(JoinCode.decode(code.replace("-", "")), expected)
	assert_eq(JoinCode.decode("  " + code.replace("-", " ") + " "), expected)
	assert_eq(JoinCode.decode(code.replace("0", "O").replace("1", "I")), expected)


func test_encode_rejects_invalid_input() -> void:
	assert_eq(JoinCode.encode("300.1.1.1", 7777), "")
	assert_eq(JoinCode.encode("1.2.3", 7777), "")
	assert_eq(JoinCode.encode("1.2.3.4", 0), "")
	assert_eq(JoinCode.encode("1.2.3.4", 70000), "")


func test_decode_rejects_invalid_codes() -> void:
	assert_eq(JoinCode.decode(""), {})
	assert_eq(JoinCode.decode("ABC"), {})
	assert_eq(JoinCode.decode("UUUUU-UUUUU"), {}, "U is not in the alphabet")
	assert_eq(JoinCode.decode("ZZZZZ-ZZZZZ"), {}, "more than 48 bits")
	assert_eq(JoinCode.decode("00000-00000"), {}, "port 0")


func test_parse_target_accepts_addresses() -> void:
	assert_eq(JoinCode.parse_target("192.168.1.5"), {"address": "192.168.1.5", "port": Protocol.DEFAULT_PORT})
	assert_eq(JoinCode.parse_target(" 192.168.1.5:9000 "), {"address": "192.168.1.5", "port": 9000})
	assert_eq(JoinCode.parse_target("localhost"), {"address": "localhost", "port": Protocol.DEFAULT_PORT})
	assert_eq(JoinCode.parse_target("localhost:8000"), {"address": "localhost", "port": 8000})
	assert_eq(JoinCode.parse_target("my-pc.lan"), {"address": "my-pc.lan", "port": Protocol.DEFAULT_PORT})
	assert_eq(JoinCode.parse_target("gamebox"), {"address": "gamebox", "port": Protocol.DEFAULT_PORT})


func test_parse_target_accepts_join_codes() -> void:
	var code: String = JoinCode.encode("10.1.2.3", 7778)
	assert_eq(JoinCode.parse_target(code), {"address": "10.1.2.3", "port": 7778})


func test_parse_target_rejects_garbage() -> void:
	for bad: String in ["", "   ", "1.2.3.4:abc", "1.2.3.4:70000", "1.2.3.4:", "999.1.1.1", "1.2.3", "a:b:c", "!!!", "bad_host.lan"]:
		assert_eq(JoinCode.parse_target(bad), {}, "should reject '%s'" % bad)
