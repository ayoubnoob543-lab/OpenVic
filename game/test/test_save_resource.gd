extends GdUnitTestSuite


func test_metadata_survives_repeated_successful_flushes() -> void:
	var save_resource: SaveResource = SaveResource.new()
	var save_path: String = ProjectSettings.globalize_path(
		"user://save-resource-test-%s.cfg" % Time.get_ticks_usec()
	)
	save_resource.set_file_path(&"test-save", save_path)
	save_resource.session_tag = &"first-session"

	assert_int(save_resource.flush_save()).is_equal(OK)

	# A later metadata update must not erase the save name from the next write.
	save_resource.session_tag = &"second-session"
	assert_int(save_resource.flush_save()).is_equal(OK)

	var loaded_file: ConfigFile = ConfigFile.new()
	assert_int(loaded_file.load(save_path)).is_equal(OK)
	assert_str(str(loaded_file.get_value("Save", "name", ""))).is_equal("test-save")
	assert_str(str(loaded_file.get_value("Save", "session_tag", ""))).is_equal("second-session")

	DirAccess.remove_absolute(save_path)
