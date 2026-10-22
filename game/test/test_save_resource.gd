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


func test_atomic_replacement_keeps_latest_complete_payload() -> void:
	var save_resource: SaveResource = SaveResource.new()
	var save_path: String = ProjectSettings.globalize_path(
		"user://save-atomic-test-%s.cfg" % Time.get_ticks_usec()
	)
	save_resource.set_file_path(&"atomic-save", save_path)
	assert_int(save_resource.set_game_state({"snapshot_kind": "first"})).is_equal(OK)
	assert_int(save_resource.flush_save()).is_equal(OK)

	assert_int(save_resource.set_game_state({"snapshot_kind": "second", "selected_province": 42})).is_equal(OK)
	assert_int(save_resource.flush_save()).is_equal(OK)

	var loaded_resource: SaveResource = SaveResource.new()
	assert_int(loaded_resource.load_save(save_path)).is_equal(OK)
	var loaded_state: Dictionary = loaded_resource.get_game_state()
	assert_str(str(loaded_state["snapshot_kind"])).is_equal("second")
	assert_int(int(loaded_state["selected_province"])).is_equal(42)
	assert_bool(FileAccess.file_exists(save_path + ".tmp")).is_false()
	assert_bool(FileAccess.file_exists(save_path + ".bak")).is_false()

	DirAccess.remove_absolute(save_path)


func test_unsupported_game_state_schema_is_not_loaded() -> void:
	var save_resource: SaveResource = SaveResource.new()
	var save_path: String = ProjectSettings.globalize_path(
		"user://save-schema-test-%s.cfg" % Time.get_ticks_usec()
	)
	var file: ConfigFile = ConfigFile.new()
	file.set_value("Save", "name", "future-schema")
	file.set_value("GameState", "schema_version", SaveResource.SAVE_SCHEMA_VERSION + 1)
	file.set_value("GameState", "player_country", "USA")
	assert_int(file.save(save_path)).is_equal(OK)

	assert_int(save_resource.load_save(save_path)).is_equal(OK)
	assert_bool(save_resource.has_game_state()).is_false()

	DirAccess.remove_absolute(save_path)


func test_replacing_snapshot_removes_stale_keys() -> void:
	var save_resource: SaveResource = SaveResource.new()
	assert_int(save_resource.set_game_state({
		"snapshot_kind": "session_reference",
		"obsolete_key": "stale",
	})).is_equal(OK)
	assert_int(save_resource.set_game_state({
		"snapshot_kind": "session_reference",
		"player_country": "USA",
	})).is_equal(OK)

	var state: Dictionary = save_resource.get_game_state()
	assert_bool(state.has("obsolete_key")).is_false()
	assert_str(str(state["player_country"])).is_equal("USA")



func test_recovery_restores_backup_when_final_rename_was_interrupted() -> void:
	var save_path: String = ProjectSettings.globalize_path(
		"user://save-recovery-test-%s.cfg" % Time.get_ticks_usec()
	)
	var backup: ConfigFile = ConfigFile.new()
	backup.set_value("Save", "name", "recovered-save")
	backup.set_value("Save", "session_tag", "recovery-test")
	backup.set_value("GameState", "schema_version", SaveResource.SAVE_SCHEMA_VERSION)
	backup.set_value("GameState", "snapshot_kind", "session_reference")
	assert_int(backup.save(save_path + ".bak")).is_equal(OK)

	assert_int(SaveResource.recover_interrupted_save(save_path)).is_equal(OK)
	assert_bool(FileAccess.file_exists(save_path)).is_true()
	assert_bool(FileAccess.file_exists(save_path + ".bak")).is_false()
	var recovered: ConfigFile = ConfigFile.new()
	assert_int(recovered.load(save_path)).is_equal(OK)
	assert_str(str(recovered.get_value("Save", "name", ""))).is_equal("recovered-save")

	DirAccess.remove_absolute(save_path)


func test_recovery_preserves_corrupt_target_and_restores_valid_backup() -> void:
	var save_path: String = ProjectSettings.globalize_path(
		"user://save-corrupt-recovery-test-%s.cfg" % Time.get_ticks_usec()
	)
	var corrupt_file: FileAccess = FileAccess.open(save_path, FileAccess.WRITE)
	assert_bool(corrupt_file != null).is_true()
	corrupt_file.store_string("this is not a valid ConfigFile [")
	corrupt_file.close()

	var backup: ConfigFile = ConfigFile.new()
	backup.set_value("Save", "name", "backup-save")
	backup.set_value("Save", "session_tag", "recovery-test")
	assert_int(backup.save(save_path + ".bak")).is_equal(OK)

	assert_int(SaveResource.recover_interrupted_save(save_path)).is_equal(OK)
	assert_bool(FileAccess.file_exists(save_path)).is_true()
	assert_bool(FileAccess.file_exists(save_path + ".corrupt")).is_true()
	var recovered: ConfigFile = ConfigFile.new()
	assert_int(recovered.load(save_path)).is_equal(OK)
	assert_str(str(recovered.get_value("Save", "name", ""))).is_equal("backup-save")

	DirAccess.remove_absolute(save_path)
	DirAccess.remove_absolute(save_path + ".corrupt")



func test_recovery_promotes_valid_temporary_file_when_target_and_backup_are_missing() -> void:
	var save_path: String = ProjectSettings.globalize_path(
		"user://save-temporary-recovery-test-%s.cfg" % Time.get_ticks_usec()
	)
	var temporary: ConfigFile = ConfigFile.new()
	temporary.set_value("Save", "name", "temporary-save")
	temporary.set_value("Save", "session_tag", "recovery-test")
	assert_int(temporary.save(save_path + ".tmp")).is_equal(OK)

	assert_int(SaveResource.recover_interrupted_save(save_path)).is_equal(OK)
	assert_bool(FileAccess.file_exists(save_path)).is_true()
	assert_bool(FileAccess.file_exists(save_path + ".tmp")).is_false()
	var recovered: ConfigFile = ConfigFile.new()
	assert_int(recovered.load(save_path)).is_equal(OK)
	assert_str(str(recovered.get_value("Save", "name", ""))).is_equal("temporary-save")

	DirAccess.remove_absolute(save_path)



func test_recovery_rejects_parseable_config_without_save_metadata() -> void:
	var save_path: String = ProjectSettings.globalize_path(
		"user://save-invalid-recovery-test-%s.cfg" % Time.get_ticks_usec()
	)
	var invalid_temporary: ConfigFile = ConfigFile.new()
	invalid_temporary.set_value("NotASave", "value", 1)
	assert_int(invalid_temporary.save(save_path + ".tmp")).is_equal(OK)

	assert_int(SaveResource.recover_interrupted_save(save_path)).is_equal(ERR_FILE_NOT_FOUND)
	assert_bool(FileAccess.file_exists(save_path)).is_false()
	assert_bool(FileAccess.file_exists(save_path + ".tmp")).is_true()

	DirAccess.remove_absolute(save_path + ".tmp")



func test_recovery_prefers_latest_valid_temporary_file_over_backup() -> void:
	var save_path: String = ProjectSettings.globalize_path(
		"user://save-recovery-preference-test-%s.cfg" % Time.get_ticks_usec()
	)
	var backup: ConfigFile = ConfigFile.new()
	backup.set_value("Save", "name", "older-backup")
	assert_int(backup.save(save_path + ".bak")).is_equal(OK)

	var temporary: ConfigFile = ConfigFile.new()
	temporary.set_value("Save", "name", "latest-temporary")
	assert_int(temporary.save(save_path + ".tmp")).is_equal(OK)

	assert_int(SaveResource.recover_interrupted_save(save_path)).is_equal(OK)
	var recovered: ConfigFile = ConfigFile.new()
	assert_int(recovered.load(save_path)).is_equal(OK)
	assert_str(str(recovered.get_value("Save", "name", ""))).is_equal("latest-temporary")
	assert_bool(FileAccess.file_exists(save_path + ".bak")).is_false()
	assert_bool(FileAccess.file_exists(save_path + ".tmp")).is_false()

	DirAccess.remove_absolute(save_path)
