extends Control

@export var _save_scene: PackedScene
@export_group("Nodes")
@export var _label: Label
@export var _scroll_list: BoxContainer
@export var _save_line_edit: LineEdit
@export var _save_load_button: Button
@export var _tag_selection_tab: TabBar
@export var _delete_dialog: ConfirmationDialog
@export var _overwrite_dialog: ConfirmationDialog

var is_save_menu: bool = true
var _id_to_tag: Array[StringName] = []
var _submitted_text: String = ""
var _requested_node_to_delete: Control
var _selected_save_resource: SaveResource


func filter_for_tag(tag: StringName) -> void:
	for child: Control in _scroll_list.get_children():
		if tag.is_empty():
			child.show()
		else:
			if tag == child.resource.session_tag:
				child.show()
			else:
				child.hide()


# Requirements
# * UIFUN-78


func show_for_load() -> void:
	_label.text = "Load Menu"
	_save_load_button.text = "Load"
	_save_line_edit.editable = false
	is_save_menu = false
	_selected_save_resource = null
	_save_load_button.disabled = true
	show()


# Requirements
# * UIFUN-77


func show_for_save() -> void:
	_label.text = "Save Menu"
	_save_load_button.text = "Save"
	_save_line_edit.editable = true
	is_save_menu = true
	_selected_save_resource = null
	_save_load_button.disabled = false
	show()


func _build_save_list() -> void:
	# The scene starts with an "All" tab; only recreate it after the list was cleared.
	if _tag_selection_tab.tab_count == 0:
		_tag_selection_tab.add_tab("All")
	for save_name: StringName in SaveManager._save_dictionary:
		var save: SaveResource = SaveManager._save_dictionary[save_name]
		var save_node := _create_save_node(save)
		_scroll_list.add_child(save_node)
		if not _id_to_tag.has(save.session_tag):
			_id_to_tag.append(save.session_tag)
			_tag_selection_tab.add_tab(save.session_tag)


func _create_save_node(resource: SaveResource) -> Control:
	var save_node = _save_scene.instantiate()
	save_node.resource = resource
	save_node.pressed.connect(_on_save_node_pressed.bind(save_node))
	save_node.request_to_delete.connect(_on_save_node_delete_requested.bind(save_node))
	return save_node


func _queue_clear_scroll_list() -> void:
	for child: Node in _scroll_list.get_children():
		child.queue_free()
	_tag_selection_tab.clear_tabs()
	_id_to_tag.clear()


# REQUIREMENTS:
# * UIFUN-84
# * UIFUN-89


func _on_close_button_pressed() -> void:
	hide()


func _on_delete_dialog_confirmed() -> void:
	if _requested_node_to_delete == null:
		return

	var delete_error: Error = _requested_node_to_delete.resource.delete()
	if delete_error != OK:
		return

	_requested_node_to_delete.queue_free()
	_requested_node_to_delete = null


# REQUIREMENTS:
# * UIFUN-83


func _on_overwrite_dialog_confirmed() -> void:
	var new_save: SaveResource = SaveManager.make_new_save(_submitted_text)
	if GameSingleton.is_game_session_active():
		# This is a versioned session checkpoint, not yet a full simulation dump:
		# economy, POPs, armies, diplomacy and RNG state need native serializers.
		var checkpoint: Dictionary = {
			"snapshot_kind": "session_reference",
			"simulation_state_complete": false,
			"current_date": GameSingleton.get_current_date_string(),
			"player_country": PlayerSingleton.get_player_country_identifier(),
			"selected_province": PlayerSingleton.get_selected_province_number(),
			"mapmode_index": GameSingleton.get_current_mapmode_index(),
			"bookmark_start_position": GameSingleton.get_bookmark_start_position(),
			"saved_at_unix": Time.get_unix_time_from_system(),
		}
		var snapshot_error: Error = new_save.set_game_state(checkpoint)
		if snapshot_error != OK:
			push_error("Could not prepare game-state checkpoint.")
			return
	SaveManager.add_or_replace_save(new_save)
	var flush_error: Error = SaveManager.flush_save()
	if flush_error != OK:
		push_error("Could not write save file; the save menu will remain open.")
		return
	_on_close_button_pressed()


func _on_save_line_edit_text_submitted(new_text: String) -> void:
	_submitted_text = new_text.strip_edges()
	if _submitted_text.is_empty():
		push_warning("Save name cannot be empty.")
		_save_line_edit.grab_focus()
		return

	if SaveManager.has_save(_submitted_text):
		_overwrite_dialog.dialog_text = tr("Are you sure you want to overwrite {file_name}?").format({ "file_name": _submitted_text })
		_overwrite_dialog.title = tr("Overwrite {file_name}").format({ "file_name": _submitted_text })
		_overwrite_dialog.popup_centered()
		return
	_on_overwrite_dialog_confirmed()


func _on_save_load_button_pressed() -> void:
	if is_save_menu:
		_save_line_edit.text_submitted.emit(_save_line_edit.text)
		return

	if _selected_save_resource == null:
		push_warning("Select a save before attempting to load it.")
		return

	var state: Dictionary = _selected_save_resource.get_game_state()
	if state.is_empty():
		push_warning("This save contains metadata only and cannot restore a game session.")
		_label.text = tr("This save has no simulation state")
		return

	if not bool(state.get("simulation_state_complete", false)):
		push_warning("This file is only a session checkpoint; full simulation restore is not implemented yet.")
		_label.text = tr("Full game-state loading is not available for this checkpoint")
		return

	# Do not report a successful load until a native simulation restore routine exists.
	push_error("The save contains a full-state marker, but no native restore routine is connected.")


func _on_save_node_delete_requested(node: Control) -> void:
	_requested_node_to_delete = node
	_delete_dialog.dialog_text = tr("Are you sure you want to delete {file_name}?").format({ "file_name": _requested_node_to_delete.resource.save_name })
	_delete_dialog.title = tr("Delete {file_name}").format({ "file_name": _requested_node_to_delete.resource.save_name })
	_delete_dialog.popup_centered()


# REQUIREMENTS:
# * UIFUN-81
# * UIFUN-86


func _on_save_node_pressed(node: Control) -> void:
	_selected_save_resource = node.resource
	if is_save_menu:
		_save_line_edit.text = node.resource.save_name
	else:
		_save_load_button.disabled = _selected_save_resource == null
		_label.text = tr("Selected save: {save_name}").format({
			"save_name": _selected_save_resource.save_name,
		})


func _on_tag_selection_tab_bar_tab_changed(tab) -> void:
	if tab == 0:
		filter_for_tag(&"")
	else:
		filter_for_tag(_id_to_tag[tab - 1])


func _on_visibility_changed() -> void:
	if visible:
		_selected_save_resource = null
		if not is_save_menu:
			_save_load_button.disabled = true
		_build_save_list()
	else:
		_selected_save_resource = null
		_queue_clear_scroll_list()
		SaveManager.flush_save()
