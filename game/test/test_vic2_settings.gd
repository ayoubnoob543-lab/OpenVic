extends GdUnitTestSuite


func test_empty_path_is_rejected_with_a_specific_error() -> void:
	assert_str(Vic2Settings.get_base_path_validation_error("")).is_equal(
		"No Victoria II directory was provided."
	)


func test_relative_path_is_rejected() -> void:
	assert_str(Vic2Settings.get_base_path_validation_error("relative/victoria2")).is_equal(
		"The Victoria II directory must be an absolute path."
	)


func test_existing_non_game_directory_reports_missing_data() -> void:
	var error: String = Vic2Settings.get_base_path_validation_error(OS.get_user_data_dir())
	assert_str(error).starts_with("Missing required Victoria II data: ")
	assert_str(error).contains("map/provinces.bmp")
	assert_str(error).contains("common/countries/")
	assert_str(error).contains("history/countries/")
