extends Node

@export var _map_view: MapView
@export var _model_manager: ModelManager
@export var _game_session_menu: Control

var _session_started: bool = false


func _ready() -> void:
	if PlayerSingleton.get_player_country_identifier().is_empty():
		push_error("Cannot start a game session without a selected player country.")
		set_process(false)
		if _map_view != null:
			_map_view.disable_processing()
		return

	if GameSingleton.start_game_session() != OK:
		push_error("Failed to start game session")
		set_process(false)
		if _map_view != null:
			_map_view.disable_processing()
		return

	_session_started = true
	_model_manager.generate_units()
	_model_manager.generate_buildings()
	MusicManager.generate_playlist()
	MusicManager.select_next_song()
	# In game, the province selector uses the normal glove cursor.
	CursorManager.set_compat_cursor(&"normal", Input.CURSOR_IBEAM)


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_PREDELETE:
			if _session_started:
				_session_started = false
				if GameSingleton.end_game_session() != OK:
					push_error("Failed to end game session")


func _process(_delta: float) -> void:
	if _session_started:
		GameSingleton.update_clock()

# REQUIREMENTS:
# * SS-42


func _on_game_session_menu_button_pressed() -> void:
	_game_session_menu.visible = not _game_session_menu.visible


func _on_map_view_ready() -> void:
	# Prefer the player's capital, then the selected bookmark's initial camera position.
	var start_position: Vector2 = PlayerSingleton.get_player_country_capital_position()
	if start_position == Vector2.ZERO:
		if GameSingleton.is_bookmark_loaded():
			start_position = GameSingleton.get_bookmark_start_position()
		else:
			start_position = Vector2(0.5, 0.5)
	_map_view.look_at_map_position(start_position)


func _on_map_view_province_hovered(province_number: int) -> void:
	_map_view.set_hovered_province_number(province_number)


func _on_map_view_province_unhovered() -> void:
	_map_view.unset_hovered_province()


func _on_map_view_province_clicked(province_number: int) -> void:
	PlayerSingleton.set_selected_province_by_number(province_number)


func _on_map_view_province_right_clicked(province_number: int) -> void:
	if province_number <= 0:
		return
	# Right-click currently emits a context action only. It must never change
	# the active player country; diplomacy and movement commands will be added here.
