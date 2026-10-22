extends HBoxContainer


# REQUIREMENTS:
# * 1.4 Game Lobby Menu
# * SS-12

signal back_button_pressed
signal save_game_selected(save: SaveResource)
signal start_date_selected(index: int)

@export var lobby_panel_button: PackedScene
@export var save_scene: PackedScene
@export_group("Nodes")
@export var game_select_start_date: BoxContainer
@export var game_select_save_tab: TabBar
@export var game_select_save_list: BoxContainer
@export var start_button: BaseButton
@export var session_tag_line_edit: LineEdit
@export var session_tag_dialog: ConfirmationDialog
@export var delete_dialog: ConfirmationDialog
@export var map_view: MapView
@export var selected_country_name_label: Label

var _id_to_tag: Array[StringName] = []
var _requested_node_to_delete: Control
var _start_date_index: int = -1
var _game_setup_date_index: int = -1


func _ready() -> void:
	if selected_country_name_label != null:
		selected_country_name_label.text = tr("Select a country on the map")


func filter_for_tag(tag: StringName) -> void:
	for child: Control in game_select_save_list.get_children():
		if tag.is_empty():
			child.show()
		else:
			if tag == child.resource.session_tag:
				child.show()
			else:
				child.hide()


func _build_date_list() -> void:
	const bookmark_info_name_key: StringName = &"bookmark_name"
	const bookmark_info_date_key: StringName = &"bookmark_date"

	for bookmark_dict: Dictionary in GameSingleton.get_bookmark_info():
		var start_date := lobby_panel_button.instantiate()
		start_date.set_name_text(bookmark_dict.get(bookmark_info_name_key, "MISSING BOOKMARK NAME"))
		start_date.set_date_text(bookmark_dict.get(bookmark_info_date_key, "MISSING BOOKMARK DATE"))
		start_date.pressed.connect(_on_start_date_panel_button_pressed.bind(start_date))
		game_select_start_date.add_child(start_date)


# Requirements
# * FS-8


func _build_save_list() -> void:
	# The scene starts with an "All" tab; only recreate it after the list was cleared.
	if game_select_save_tab.tab_count == 0:
		game_select_save_tab.add_tab("All")
	for save_name: StringName in SaveManager._save_dictionary:
		var save: SaveResource = SaveManager._save_dictionary[save_name]
		var save_node := _create_save_node(save)
		game_select_save_list.add_child(save_node)
		if not _id_to_tag.has(save.session_tag):
			_id_to_tag.append(save.session_tag)
			game_select_save_tab.add_tab(save.session_tag)


func _create_save_node(resource: SaveResource) -> Control:
	var save_node := save_scene.instantiate()
	save_node.resource = resource
	save_node.pressed.connect(_on_save_node_pressed.bind(save_node))
	save_node.request_to_delete.connect(_on_save_node_delete_requested.bind(save_node))
	return save_node


func _queue_clear_lists() -> void:
	var full_list := game_select_start_date.get_children()
	full_list.append_array(game_select_save_list.get_children())
	for child: Node in full_list:
		child.queue_free()
	game_select_save_tab.clear_tabs()
	_id_to_tag.clear()


# REQUIREMENTS:
# * SS-16
# * UIFUN-40


func _on_back_button_pressed() -> void:
	print("Returning to Main Menu.")
	SaveManager.current_session_tag = ""
	SaveManager.current_save = null

	# Country selection may have initialised a game instance before Start was pressed.
	# Tear it down here so a later lobby can load a different bookmark.
	if GameSingleton.is_game_instance_setup() and not GameSingleton.is_game_session_active():
		if GameSingleton.end_game_session() != OK:
			push_warning("Failed to clean up the unstarted game instance.")

	_game_setup_date_index = -1
	_start_date_index = -1
	start_button.disabled = true
	if selected_country_name_label != null:
		selected_country_name_label.text = tr("Select a country on the map")
	back_button_pressed.emit()


# REQUIREMENTS:
# * SS-21


func _on_start_button_pressed() -> void:
	print("Starting new game.")
	if SaveManager.current_session_tag == "":
		# TODO: Get country tag as well
		var datetime := Time.get_datetime_dict_from_system()
		SaveManager.current_session_tag = "%s/%s/%s-%s:%s:%s" % [
			datetime["day"],
			datetime["month"],
			datetime["year"],
			datetime["hour"],
			datetime["minute"],
			datetime["second"],
		]
	if SaveManager.current_save == null and SaveManager.current_session_tag in _id_to_tag:
		session_tag_dialog.dialog_text = tr("Are you sure you want to override {session_tag} as a previous session?").format({ "session_tag": SaveManager.current_session_tag })
		session_tag_dialog.title = tr("Override {session_tag}").format({ "session_tag": SaveManager.current_session_tag })
		session_tag_dialog.popup_centered()
	else:
		_on_session_tag_dialog_confirmed()


# REQUIREMENTS:
# * SS-19


func _on_game_select_list_item_selected(index) -> void:
	print("Selected save game: ", index)
	save_game_selected.emit(index)


# If the date is double-clicked, start the game!


func _on_game_select_list_item_activated(index) -> void:
	_on_game_select_list_item_selected(index)
	_on_start_button_pressed()


func _on_session_tag_edit_text_submitted(new_text: String) -> void:
	SaveManager.current_session_tag = new_text
	_on_start_button_pressed()


func _on_session_tag_dialog_confirmed() -> void:
	if _start_date_index < 0:
		push_error("Cannot setup game, no start date selected!")
		return

	# The game instance may already have been created when the player selected a country.
	if GameSingleton.is_game_instance_setup():
		if _game_setup_date_index != _start_date_index:
			push_warning("The selected start date differs from the loaded game. Return to the lobby and choose the date before selecting a country.")
			return
	else:
		if GameSingleton.setup_game(_start_date_index) != OK:
			push_error("Failed to setup game")
			return
		_game_setup_date_index = _start_date_index

	get_tree().change_scene_to_file("res://src/Systems/Session/GameSession.tscn")


func _on_save_node_delete_requested(node: Control) -> void:
	_requested_node_to_delete = node
	delete_dialog.dialog_text = tr("Are you sure you want to delete {file_name}?").format({ "file_name": _requested_node_to_delete.resource.save_name })
	delete_dialog.title = tr("Delete {file_name}").format({ "file_name": _requested_node_to_delete.resource.save_name })
	delete_dialog.popup_centered()


func _on_start_date_panel_button_pressed(node: Control) -> void:
	var requested_date_index: int = node.get_index(true)
	if requested_date_index == _start_date_index:
		_on_start_button_pressed()
		return
	if GameSingleton.is_game_instance_setup() and requested_date_index != _game_setup_date_index:
		push_warning("The start date cannot be changed after a country has been selected. Return to the main menu to choose another bookmark.")
		return
	_start_date_index = requested_date_index
	start_button.disabled = false
	start_date_selected.emit(_start_date_index)


func _on_save_node_pressed(node: Control) -> void:
	if SaveManager.current_save != null and SaveManager.current_save == node.resource:
		SaveManager.current_session_tag = SaveManager.current_save.session_tag
		_on_start_button_pressed()
		return
	SaveManager.current_save = node.resource
	if SaveManager.current_save != null:
		session_tag_line_edit.text = SaveManager.current_save.session_tag
	else:
		session_tag_line_edit.text = ""
	start_button.disabled = false
	save_game_selected.emit(SaveManager.current_save)


func _on_game_select_save_tab_tab_changed(tab: int) -> void:
	if tab == 0:
		filter_for_tag(&"")
	else:
		filter_for_tag(_id_to_tag[tab - 1])


func _on_delete_dialog_confirmed() -> void:
	if _requested_node_to_delete == null:
		return

	var delete_error: Error = _requested_node_to_delete.resource.delete()
	if delete_error != OK:
		return

	_requested_node_to_delete.queue_free()
	_requested_node_to_delete = null


func _on_visibility_changed() -> void:
	if visible:
		_build_date_list()
		_build_save_list()
	else:
		_queue_clear_lists()


func _on_map_view_ready() -> void:
	if GameSingleton.is_bookmark_loaded():
		map_view._camera.position = map_view._map_to_world_coords(GameSingleton.get_bookmark_start_position())


func _on_map_view_province_clicked(province_number: int) -> void:
	if province_number <= 0:
		return
	if _start_date_index < 0:
		push_warning("Select a start date before choosing a country.")
		if selected_country_name_label != null:
			selected_country_name_label.text = tr("Select a start date first")
		return

	# The simulation instance is created lazily, on the first country selection.
	if not GameSingleton.is_game_instance_setup():
		if GameSingleton.setup_game(_start_date_index) != OK:
			push_error("Could not load the selected bookmark; country selection was cancelled.")
			return
		_game_setup_date_index = _start_date_index

	if not PlayerSingleton.set_player_country_by_province_number(province_number):
		if selected_country_name_label != null:
			selected_country_name_label.text = tr("Select an owned province")
		return
	var country_identifier: String = PlayerSingleton.get_player_country_identifier()
	if country_identifier.is_empty():
		push_warning("The clicked province has no selectable country.")
		return

	if selected_country_name_label != null:
		selected_country_name_label.text = tr(country_identifier)

	# Prefer the political mapmode so country ownership and the current player are visible.
	for mapmode_index: int in range(GameSingleton.get_mapmode_count()):
		var mapmode_identifier: String = GameSingleton.get_mapmode_identifier(mapmode_index).to_lower()
		if mapmode_identifier == "political" or mapmode_identifier.ends_with("_political"):
			if GameSingleton.set_mapmode(mapmode_index) != OK:
				push_warning("Country selected, but the political mapmode could not be activated.")
			break

	var capital_position: Vector2 = PlayerSingleton.get_player_country_capital_position()
	if capital_position != Vector2.ZERO and map_view._camera != null:
		map_view._camera.position = map_view._map_to_world_coords(capital_position)
