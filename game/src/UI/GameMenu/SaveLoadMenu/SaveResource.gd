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

	file.set_value(GAME_STATE_SECTION, "schema_version", SAVE_SCHEMA_VERSION)
	for key: Variant in state:
		if str(key).strip_edges().is_empty() or str(key) == "schema_version":
			push_error("Invalid reserved or empty game-state key: ", key)
			return Error.ERR_INVALID_PARAMETER
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
	var result: Error = file.save(file_path)
	if result != OK:
		push_error("Failed to save game to '", file_path, "': ", error_string(result))
		return result

	file_flushed.emit(file_path)
	# Keep the metadata in memory so a later flush cannot overwrite the save
	# with an empty ConfigFile after the first successful write.
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
