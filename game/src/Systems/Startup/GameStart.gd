extends Control

const LoadingScreen := preload("res://src/Systems/Startup/LoadingScreen.gd")
const GameMenuScene := preload("res://src/UI/GameMenu/GameMenu/GameMenu.tscn")

@export_subgroup("Nodes")
@export var loading_screen: LoadingScreen


func _enter_tree() -> void:
	Keychain.keep_binding_check = func(action_name: StringName) -> bool:
		return action_name.begins_with("button_") and action_name.ends_with("_hotkey")


func _ready() -> void:
	if ArgumentParser.get_option_value(&"help"):
		# For some reason this doesn't get freed properly
		# Godot will always quit before it frees the active StreamPlayback resource
		# This hack fixes that
		MusicManager.queue_free()
		get_tree().quit()
		return

	await _setup_compatibility_mode_paths()
	await loading_screen.start_loading_screen(_initialize_game)


func _setup_compatibility_mode_paths() -> void:
	# To test mods, set your base path to Victoria II and then pass mods in reverse order with
	# --mod="mod" for each mod.

	var arg_base_path: String = ArgumentParser.get_option_value(&"base-path")
	var arg_search_path: String = ArgumentParser.get_option_value(&"search-path")

	var setting: Vic2Settings.Setting = Vic2Settings.get_setting(Vic2Settings.GENERAL_BASE_DEFINES_PATH)

	if arg_base_path:
		if arg_search_path:
			push_warning(
				"Exact base path and search base path arguments both used; --base-path takes priority.\nBase: ",
				arg_base_path,
				"\nSearch: ",
				arg_search_path,
			)
		var normalized_base_path: String = arg_base_path
		if normalized_base_path.is_relative_path():
			normalized_base_path = DirAccess.get_current_dir().path_join(normalized_base_path)
		normalized_base_path = normalized_base_path.simplify_path()
		setting.set_value(normalized_base_path)
		var path_error := Vic2Settings.get_base_path_validation_error(normalized_base_path)
		if not path_error.is_empty():
			push_warning("Ignoring invalid --base-path '", arg_base_path, "': ", path_error)
	elif Vic2Settings.get_base_defines_path().is_empty() and arg_search_path:
		# This will also search for a Steam install if the hint doesn't help
		var discovered_path := Vic2Settings.find_base_path(arg_search_path)
		if discovered_path.is_empty():
			push_warning("Could not find a valid Victoria II installation from --search-path: ", arg_search_path)
		else:
			setting.set_value(discovered_path)

	if Vic2Settings.get_base_defines_path().is_empty():
		# Check if the program is being run from inside the install directory,
		# and if not also search for a Steam install
		var root_base_path: String = Vic2Settings.find_base_path(".")
		if root_base_path.is_empty():
			await Vic2Settings.show_base_path_find_dialog()
		else:
			setting.set_value(root_base_path)

	# Add mod paths
	var load_list_setting: ModSettings.Setting = ModSettings.get_setting(ModSettings.MODS_LOAD_LIST)
	var load_list: PackedStringArray = ModSettings.get_load_list()
	for mod in ArgumentParser.get_option_value(&"mod"):
		if mod not in load_list and mod != "":
			load_list.append(mod)
	load_list_setting.set_value(load_list)


func _load_compatibility_mode() -> Error:
	if GameSingleton.set_compatibility_mode_roots(Vic2Settings.get_base_defines_path()) != OK:
		push_error("Errors setting game roots!")
		return FAILED

	CursorManager.initial_cursor_setup()
	setup_title_theme()

	var load_error: Error = GameSingleton.load_defines_compatibility_mode(ModSettings.get_load_list())
	if load_error != OK:
		push_error("Errors loading game defines!")
		return load_error

	SoundSingleton.load_sounds()
	SoundSingleton.load_music()
	MusicManager.add_compat_songs()
	return OK


func setup_title_theme() -> void:
	SoundSingleton.load_title_theme()

	MusicManager.setup_compat_song(SoundSingleton.title_theme)

	var song_paths = MusicManager.get_all_song_paths()
	var title_index = song_paths.find(SoundSingleton.title_theme)
	if title_index != -1:
		MusicManager.start_song_by_index.call_deferred(title_index)
	if len(MusicManager._available_songs) <= 0:
		push_error("No song available to play")
	else:
		MusicManager.start_current_song.call_deferred()

# REQUIREMENTS
# * FS-333, FS-334, FS-335, FS-341


func _initialize_game() -> void:
	if Vic2Settings.get_base_defines_path().is_empty():
		call_deferred("_show_initialization_error")
		return

	var start := Time.get_ticks_usec()
	loading_screen.try_update_loading_screen(0)
	GameSingleton.setup_logger()

	loading_screen.try_update_loading_screen(15, true)

	if _load_compatibility_mode() != OK:
		call_deferred("_show_initialization_error")
		return
	loading_screen.try_update_loading_screen(75, true)

	loading_screen.try_update_loading_screen(100)

	var end := Time.get_ticks_usec()
	print("Loading took ", float(end - start) / 1_000_000, " seconds")

	# change scene in a thread-safe way
	get_tree().change_scene_to_packed.call_deferred(GameMenuScene)


func _show_initialization_error() -> void:
	loading_screen.progress_bar.value = 100
	loading_screen.quote_label.text = tr(
		"Failed to load Victoria II data. Check the game directory and application logs, then restart OpenVic."
	)
	loading_screen.animation_player.stop()


func _on_splash_container_splash_end() -> void:
	loading_screen.show()
