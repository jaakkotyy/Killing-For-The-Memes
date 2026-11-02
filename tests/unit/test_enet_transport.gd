extends GutTest


func test_home_lan_addresses_rank_before_virtual_adapters() -> void:
	assert_lt(EnetTransport.address_rank("192.168.1.10"), EnetTransport.address_rank("10.0.0.5"))
	assert_lt(EnetTransport.address_rank("10.0.0.5"), EnetTransport.address_rank("100.101.1.2"))
	assert_lt(EnetTransport.address_rank("100.101.1.2"), EnetTransport.address_rank("172.30.144.1"))
	assert_lt(EnetTransport.address_rank("85.10.20.30"), EnetTransport.address_rank("172.17.0.1"))


func test_local_addresses_exclude_loopback() -> void:
	for address: String in EnetTransport.local_ipv4_addresses():
		assert_false(address.begins_with("127."), "loopback should be filtered: %s" % address)
		assert_true(JoinCode.is_valid_ipv4(address))
