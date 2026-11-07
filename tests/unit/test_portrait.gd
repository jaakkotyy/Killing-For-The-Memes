extends GutTest
## Portrait URLs: Commons thumbnails rebuilt from a pack's file name, nothing else.


func test_a_photo_becomes_its_commons_thumbnail() -> void:
	assert_eq(Portrait.url_for("Michael Jackson 1983 (3x4 cropped) (contrast).jpg"),
		"https://upload.wikimedia.org/wikipedia/commons/thumb/b/b9/"
		+ "Michael_Jackson_1983_%283x4_cropped%29_%28contrast%29.jpg/"
		+ "250px-Michael_Jackson_1983_%283x4_cropped%29_%28contrast%29.jpg")


func test_svgs_are_rendered_to_png() -> void:
	assert_true(Portrait.url_for("Logo.svg").ends_with("/250px-Logo.svg.png"))


func test_only_plain_file_names_of_pictures() -> void:
	for bad: String in ["", "   ", "../x.jpg", "a/b.jpg", "x.jpg?y=1", "x.jpg#1", "File:x.jpg",
			"x%2F.jpg", "notes.txt", "scan.tif", "noextension", "a".repeat(250) + ".jpg"]:
		assert_eq(Portrait.url_for(bad), "", bad)


func test_every_url_points_at_commons_thumbnails() -> void:
	for entry: IdentityPack.Entry in IdentityPack.load_pack("musicians").entries():
		var url: String = Portrait.url_for(entry.image)
		if not url.is_empty():
			assert_true(url.begins_with(Portrait.HOST), url)
			# hash / hash / file / thumb: a name can't add path segments.
			assert_eq(url.substr(Portrait.HOST.length()).split("/").size(), 4, url)
