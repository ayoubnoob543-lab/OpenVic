@tool
extends "res://addons/kenyoni/app_settings/app_settings.gd"

const LEGACY_SETTINGS_FILES: PackedStringArray = []
const BASE_DEFINES_LEGACY_PATHS: PackedStringArray = [
	"general/base_defines_path",
]
#
# File
const SETTINGS_FILE: String = "user://vic2.cfg"
#
# General Settings
const GENERAL_BASE_DEFINES_PATH := &"victoria_2/base_defines_path"

var _base_path_find_dialog := FileDialog.new()


func _init() -> void:
	self.add_setting(Setting.new(GENERAL_BASE_DEFINES_PATH, "")
		.set_validate_fn(_base_defines_path_validate)
		.add_meta(&"type", TYPE_STRING)
		.add_meta(&"hint", PROPERTY_HINT_DIR)
		.add_meta(&"legacy_paths", BASE_DEFINES_LEGACY_PATHS))

	if Engine.is_editor_hint(): return

	self.load()
	self.apply_all()

	for setting: Setting in get_section("", -1, func(_stg: Setting) -> bool: return true):
		if not setting.validate(setting.value()):
			setting._set_value_no_validation(setting.default_value())

	_base_path_find_dialog.mode_overrides_title = false
	_base_path_find_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
	_base_path_find_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_base_path_find_dialog.show_hidden_files = true
	_base_path_find_dialog.title = "Select your Victoria 2 Game Directory"
	_base_path_find_dialog.cancel_button_text = "Cancel"
	_base_path_find_dialog.ok_button_text = "Select"
	_base_path_find_dialog.size = Vector2i(935, 175)
	_base_path_find_dialog.disable_3d = true
	_base_path_find_dialog.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_base_path_find_dialog)


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST: return
	save()


func save() -> Error:
	return self.to_config().save(SETTINGS_FILE)


func load() -> Error:
	var cfg := ConfigFile.new()
	var err: Error

	var settings_with_legacy: Array[Setting] = get_section("", -1, func(stg: Setting) -> bool: return stg.has_meta(&"legacy_paths"))

	for path: String in LEGACY_SETTINGS_FILES:
		err = cfg.load(path)
		if err != OK: continue
		for setting: Setting in settings_with_legacy:
			_load_legacy_value(cfg, setting)

	cfg.clear()
	err = cfg.load(SETTINGS_FILE)
	if err == Error.ERR_FILE_NOT_FOUND: return Error.OK
	if err != Error.OK: return err

	for setting: Setting in settings_with_legacy:
		_load_legacy_value(cfg, setting, true)

	self.from_config(cfg)

	return Error.OK


func get_base_defines_path() -> String:
	return get_setting(GENERAL_BASE_DEFINES_PATH).value()


func find_base_path(search_path: String) -> String:
	var result := GameSingleton.search_for_game_path(search_path)
	if result.is_empty() or not _is_valid_victoria_2_directory(result):
		push_warning("Failed to find a valid Victoria II installation using ", search_path)
		return ""
	return result.simplify_path()


func _is_valid_victoria_2_directory(path: String) -> bool:
	if path.is_empty() or not path.is_absolute_path():
		return false
	if not DirAccess.dir_exists_absolute(path):
		return false

	# These files are part of the base game layout and distinguish a game
	# installation from an arbitrary directory or an incomplete Steam library.
	return (
		FileAccess.file_exists(path.path_join("map/provinces.bmp"))
		and FileAccess.file_exists(path.path_join("map/definition.csv"))
		and FileAccess.file_exists(path.path_join("common/countries.txt"))
		and FileAccess.file_exists(path.path_join("common/goods.txt"))
		and DirAccess.dir_exists_absolute(path.path_join("history/countries"))
	)


func show_base_path_find_dialog() -> void:
	var setting := get_setting(GENERAL_BASE_DEFINES_PATH)

	get_tree().paused = true
	var ok_button := _base_path_find_dialog.get_ok_button()
	ok_button.auto_translate = true
	var cancel_button := _base_path_find_dialog.get_cancel_button()
	cancel_button.auto_translate = true
	_base_path_find_dialog.canceled.connect(_on_base_path_find_dialog_failed, CONNECT_ONE_SHOT)
	_base_path_find_dialog.dir_selected.connect(_on_base_path_find_dialog_dir_selected)
	while not setting.value():
		_show_alert()
		_base_path_find_dialog.popup_centered_ratio()
		await _base_path_find_dialog.dir_selected
	_base_path_find_dialog.canceled.disconnect(_on_base_path_find_dialog_failed)
	get_tree().paused = false


func _base_defines_path_validate(_stg: Setting, val: Variant) -> bool:
	if not val is String:
		return false
	return _is_valid_victoria_2_directory(val)


func _show_alert() -> void:
	OS.alert(
		tr("Failed to find Victoria II"),
		tr(
			"OpenVic couldn't find a copy of Victoria II installed on your computer! " +
			"If you do have Victoria II installed, please specify the path to your " +
			"game directory with the \"search-path\" command line option."
		)
	)


func _on_base_path_find_dialog_failed() -> void:
	get_window().mode = Window.MODE_WINDOWED
	_show_alert()
	get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)
	get_tree().quit()


func _on_base_path_find_dialog_dir_selected(dir: String) -> void:
	var setting := get_setting(GENERAL_BASE_DEFINES_PATH)
	var detected_path := find_base_path(dir)
	if detected_path.is_empty():
		push_warning("The selected directory is not a valid Victoria II installation: ", dir)
		setting.set_value("")
		return
	setting.set_value(detected_path)


func _load_legacy_value(
	config: ConfigFile,
	setting: Setting,
	skip_non_legacy: bool = false,
) -> void:
	var split: PackedStringArray

	var legacy_paths: PackedStringArray = setting.get_meta(&"legacy_paths")
	for legacy_setting_path in legacy_paths:
		split = legacy_setting_path.rsplit("/", true, 1)
		if not config.has_section_key(split[0], split[1]): continue
		setting.set_value(config.get_value(split[0], split[1]))
	if skip_non_legacy: return

	split = setting.key().rsplit("/", true, 1)
	if not config.has_section_key(split[0], split[1]): return
	setting.set_value(config.get_value(split[0], split[1]))
