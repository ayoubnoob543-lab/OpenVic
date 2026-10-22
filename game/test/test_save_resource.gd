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


func test_versioned_game_state_survives_flush_and_reload() -> void:
	var save_resource: SaveResource = SaveResource.new()
	var save_path: String = ProjectSettings.globalize_path(
		"user://save-state-test-%s.cfg" % Time.get_ticks_usec()
	)
	save_resource.set_file_path(&"state-test", save_path)
	var expected_state: Dictionary = {
		"snapshot_kind": "session_reference",
		"player_country": "USA",
		"selected_province": 1,
		"mapmode_index": 0,
		"bookmark_start_position": Vector2(0.5, 0.5),
	}
	assert_int(save_resource.set_game_state(expected_state)).is_equal(OK)
	assert_int(save_resource.flush_save()).is_equal(OK)

	var loaded_resource: SaveResource = SaveResource.new()
	assert_int(loaded_resource.load_save(save_path)).is_equal(OK)
	assert_bool(loaded_resource.has_game_state()).is_true()
	var loaded_state: Dictionary = loaded_resource.get_game_state()
	assert_str(str(loaded_state["player_country"])).is_equal("USA")
	assert_int(int(loaded_state["selected_province"])).is_equal(1)
	assert_int(int(loaded_state["mapmode_index"])).is_equal(0)
	assert_float(loaded_state["bookmark_start_position"].x).is_equal(0.5)
	assert_float(loaded_state["bookmark_start_position"].y).is_equal(0.5)

	DirAccess.remove_absolute(save_path)


func test_empty_game_state_is_rejected() -> void:
	var save_resource: SaveResource = SaveResource.new()
	assert_int(save_resource.set_game_state({})).is_equal(ERR_INVALID_DATA)
