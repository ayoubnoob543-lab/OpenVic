extends Resource
class_name SaveResource

signal file_flushed(path: String)
signal file_loaded
signal file_moved_to_trash
signal file_deleted
signal trash_moved
signal deleted

# Save files are versioned independently of their display metadata. The simulation
# payload is deliberately kept separate so future native serializers can extend it
# without breaking existing ConfigFile metadata.
const SAVE_SCHEMA_VERSION: int = 1
const GAME_STATE_SECTION: String = "GameState"

var save_name: StringName:
	get: return save_name
	set(v):
		save_name = v
		file.set_value("Save", "name", save_name)
		emit_changed()
var session_tag: StringName:
	get: return session_tag
	set(v):
		session_tag = v
		file.set_value("Save", "session_tag", v)
		emit_changed()
var file_path: String:
	get: return file_path
	set(v):
		file_path = v
		emit_changed()
var file: ConfigFile = ConfigFile.new()


func set_file_path(name: StringName, path: String) -> void:
	file_path = path
	save_name = name


func set_game_state(state: Dictionary) -> Error:
	if state.is_empty():
		push_error("Refusing to write an empty game-state snapshot.")
		return Error.ERR_INVALID_DATA

	# Validate the entire payload before mutating the ConfigFile.
	for key: Variant in state:
		if str(key).strip_edges().is_empty() or str(key) == "schema_version":
			push_error("Invalid reserved or empty game-state key: ", key)
			return Error.ERR_INVALID_PARAMETER

	# Replace the snapshot as a whole; keeping keys from an older snapshot
	# could silently resurrect stale state after a later load.
	file.erase_section(GAME_STATE_SECTION)
	file.set_value(GAME_STATE_SECTION, "schema_version", SAVE_SCHEMA_VERSION)
	for key: Variant in state:
		file.set_value(GAME_STATE_SECTION, str(key), state[key])
	emit_changed()
	return OK


func get_game_state() -> Dictionary:
	if not file.has_section_key(GAME_STATE_SECTION, "schema_version"):
		return {}
	var version: int = int(file.get_value(GAME_STATE_SECTION, "schema_version", 0))
	if version != SAVE_SCHEMA_VERSION:
		push_warning("Unsupported save-state schema version: ", version)
		return {}

	var state: Dictionary = {}
	for key: String in file.get_section_keys(GAME_STATE_SECTION):
		if key != "schema_version":
			state[key] = file.get_value(GAME_STATE_SECTION, key)
	return state


func has_game_state() -> bool:
	return not get_game_state().is_empty()


func flush_save() -> Error:
	if file_path.strip_edges().is_empty():
		push_error("Cannot save without a file path.")
		return Error.ERR_INVALID_PARAMETER

	# Write to a sibling temporary file first so an interrupted write cannot
	# truncate a previously valid save.
	var absolute_path: String = ProjectSettings.globalize_path(file_path)
	var temporary_path: String = absolute_path + ".tmp"
	var backup_path: String = absolute_path + ".bak"
	var result: Error = file.save(temporary_path)
	if result != OK:
		push_error("Failed to write temporary save '", temporary_path, "': ", error_string(result))
		return result

	var had_previous_save: bool = FileAccess.file_exists(absolute_path)
	if had_previous_save:
		if FileAccess.file_exists(backup_path):
			var remove_backup_error: Error = DirAccess.remove_absolute(backup_path)
			if remove_backup_error != OK:
				DirAccess.remove_absolute(temporary_path)
				push_error("Cannot replace old save backup: ", error_string(remove_backup_error))
				return remove_backup_error
		result = DirAccess.rename_absolute(absolute_path, backup_path)
		if result != OK:
			DirAccess.remove_absolute(temporary_path)
			push_error("Cannot protect existing save before replacement: ", error_string(result))
			return result

	result = DirAccess.rename_absolute(temporary_path, absolute_path)
	if result != OK:
		DirAccess.remove_absolute(temporary_path)
		if had_previous_save:
			var restore_error: Error = DirAccess.rename_absolute(backup_path, absolute_path)
			if restore_error != OK:
				push_error("CRITICAL: save replacement and backup restoration both failed. Backup remains at '", backup_path, "'.")
		push_error("Failed to commit save '", file_path, "': ", error_string(result))
		return result

	if had_previous_save and FileAccess.file_exists(backup_path):
		var cleanup_error: Error = DirAccess.remove_absolute(backup_path)
		if cleanup_error != OK:
			push_warning("Save succeeded but backup cleanup failed: ", backup_path)

	file_flushed.emit(file_path)
	# Keep the metadata in memory so later flushes do not overwrite the save
	# with an empty ConfigFile.
	return OK


static func _is_readable_config(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var candidate: ConfigFile = ConfigFile.new()
	if candidate.load(path) != OK:
		return false
	if not candidate.has_section_key("Save", "name"):
		return false
	return not str(candidate.get_value("Save", "name", "")).strip_edges().is_empty()


static func recover_interrupted_save(path: String) -> Error:
	# Recover a save interrupted between the backup and final rename operations.
	# Never promote an artifact unless ConfigFile can parse it successfully.
	var absolute_path: String = ProjectSettings.globalize_path(path)
	var temporary_path: String = absolute_path + ".tmp"
	var backup_path: String = absolute_path + ".bak"

	if _is_readable_config(absolute_path):
		if FileAccess.file_exists(temporary_path):
			DirAccess.remove_absolute(temporary_path)
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_path)
		return OK

	var recovery_path: String = ""
	if _is_readable_config(backup_path):
		recovery_path = backup_path
	elif _is_readable_config(temporary_path):
		recovery_path = temporary_path

	if recovery_path.is_empty():
		return ERR_FILE_CORRUPT if FileAccess.file_exists(absolute_path) else ERR_FILE_NOT_FOUND

	# Preserve an existing corrupt target for diagnosis instead of deleting it.
	var corrupt_path: String = absolute_path + ".corrupt"
	if FileAccess.file_exists(absolute_path):
		if FileAccess.file_exists(corrupt_path):
			push_error("Cannot recover save because a previous corrupt file already exists: ", corrupt_path)
			return ERR_ALREADY_EXISTS
		var preserve_error: Error = DirAccess.rename_absolute(absolute_path, corrupt_path)
		if preserve_error != OK:
			return preserve_error

	var restore_error: Error = DirAccess.rename_absolute(recovery_path, absolute_path)
	if restore_error != OK:
		if FileAccess.file_exists(corrupt_path) and not FileAccess.file_exists(absolute_path):
			DirAccess.rename_absolute(corrupt_path, absolute_path)
		return restore_error

	if FileAccess.file_exists(temporary_path):
		DirAccess.remove_absolute(temporary_path)
	if FileAccess.file_exists(backup_path):
		DirAccess.remove_absolute(backup_path)
	return OK


func load_save(path: String = file_path) -> Error:
	# Load into a temporary ConfigFile so a corrupt file cannot partially replace
	# metadata that is already associated with this resource.
	var loaded_file: ConfigFile = ConfigFile.new()
	var result: Error = loaded_file.load(path)
	if result != OK:
		return result

	var loaded_save_name: String = str(loaded_file.get_value("Save", "name", save_name))
	var loaded_session_tag: String = str(loaded_file.get_value("Save", "session_tag", session_tag))
	file = loaded_file
	file_path = path
	save_name = StringName(loaded_save_name)
	session_tag = StringName(loaded_session_tag)
	file_loaded.emit()
	return OK


func get_save_file_time() -> int:
	return FileAccess.get_modified_time(file_path)


func move_to_trash() -> Error:
	var absolute_file_path: String = ProjectSettings.globalize_path(file_path)
	var result: Error = OS.move_to_trash(absolute_file_path)
	if result != OK:
		push_error("Failed to move save to trash '", file_path, "': ", error_string(result))
		return result

	trash_moved.emit()
	file_moved_to_trash.emit()
	return OK


func delete() -> Error:
	var absolute_file_path: String = ProjectSettings.globalize_path(file_path)
	var result: Error = DirAccess.remove_absolute(absolute_file_path)
	if result != OK:
		push_error("Failed to delete save '", file_path, "': ", error_string(result))
		return result

	deleted.emit()
	file_deleted.emit()
	return OK
