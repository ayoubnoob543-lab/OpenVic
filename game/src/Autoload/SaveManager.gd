extends Node

# Requirements
# * FS-28

const save_directory_setting := &"openvic/data/saves_directory"

var current_save: SaveResource
var current_session_tag: StringName
var _save_dictionary: Dictionary = {}
var _dirty_save: SaveResource


func _ready() -> void:
	var saves_dir_path: String = ProjectSettings.get_setting_with_override(save_directory_setting)
	assert(saves_dir_path != null, "'%s' setting could not be found." % save_directory_setting)

	var absolute_saves_dir_path: String = ProjectSettings.globalize_path(saves_dir_path)
	if not DirAccess.dir_exists_absolute(absolute_saves_dir_path):
		var create_error: Error = DirAccess.make_dir_recursive_absolute(absolute_saves_dir_path)
		if create_error != OK:
			push_error("Unable to create save directory '", absolute_saves_dir_path, "': ", error_string(create_error))
			return

	var saves_dir := DirAccess.open(saves_dir_path)
	if saves_dir == null:
		push_error("Unable to open save directory: ", saves_dir_path)
		return

	# Repair interrupted atomic replacements before enumerating user-visible saves.
	# Re-open the directory afterwards so the scan sees restored filenames.
	var recovery_candidates: Dictionary = {}
	for artifact_name: String in saves_dir.get_files():
		if not artifact_name.ends_with(".tmp") and not artifact_name.ends_with(".bak"):
			continue
		var base_name: String = artifact_name.trim_suffix(".tmp").trim_suffix(".bak")
		var base_path: String = saves_dir_path.path_join(base_name)
		if recovery_candidates.has(base_path):
			continue
		recovery_candidates[base_path] = true
		var recovery_error: Error = SaveResource.recover_interrupted_save(base_path)
		if recovery_error != OK:
			push_warning("Could not recover interrupted save '", base_path, "': ", error_string(recovery_error))

	saves_dir = DirAccess.open(saves_dir_path)
	if saves_dir == null:
		push_error("Unable to reopen save directory after recovery: ", saves_dir_path)
		return

	for file_name: String in saves_dir.get_files():
		# Atomic-save working files are recovery artifacts, never user-visible saves.
		if file_name.ends_with(".tmp") or file_name.ends_with(".bak") or file_name.ends_with(".corrupt") or file_name.contains(".corrupt."):
			continue
		var save := SaveResource.new()
		var save_path: String = saves_dir_path.path_join(file_name)
		var load_error: Error = save.load_save(save_path)
		if load_error != OK:
			push_warning("Skipping unreadable save file '", save_path, "': ", error_string(load_error))
			continue
		if save.save_name.is_empty():
			push_warning("Skipping save file without a save name: ", save_path)
			continue
		add_or_replace_save(save, true)


func get_save_file_name(
	save_name: StringName,
	session_tag: StringName = current_session_tag,
) -> StringName:
	return ("%s - %s" % [save_name, session_tag]).validate_filename()


func make_new_save(
	save_name: String,
	session_tag: StringName = current_session_tag,
) -> SaveResource:
	var file_name := get_save_file_name(save_name, session_tag) + ".tres"
	var new_save := SaveResource.new()
	new_save.set_file_path(
		save_name,
		ProjectSettings.get_setting_with_override(save_directory_setting).path_join(file_name),
	)
	print(new_save.file_path)
	new_save.session_tag = session_tag
	return new_save


func has_save(save_name: StringName, session_tag: StringName = current_session_tag) -> bool:
	return _save_dictionary.has(get_save_file_name(save_name, session_tag))


func add_or_replace_save(save: SaveResource, ignore_dirty: bool = false) -> void:
	var binded_func := _on_save_deleted_or_moved.bind(save)
	save.deleted.connect(binded_func)
	save.trash_moved.connect(binded_func)
	_save_dictionary[get_save_file_name(save.save_name, save.session_tag)] = save
	if not ignore_dirty:
		_dirty_save = save


func delete_save(save: SaveResource) -> void:
	save.delete()


func flush_save() -> Error:
	if _dirty_save == null:
		return OK

	var save_to_flush: SaveResource = _dirty_save
	var result: Error = save_to_flush.flush_save()
	if result == OK and _dirty_save == save_to_flush:
		_dirty_save = null
	return result


func _on_save_deleted_or_moved(save: SaveResource) -> void:
	var save_key: StringName = get_save_file_name(save.save_name, save.session_tag)
	# A replaced resource can still emit a delayed delete/trash signal. Only remove
	# the dictionary entry if it still points at that exact resource.
	if _save_dictionary.get(save_key) == save:
		_save_dictionary.erase(save_key)
	if _dirty_save == save:
		_dirty_save = null
	if current_save == save:
		current_save = null
