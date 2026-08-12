class_name ParamPanel
extends VBoxContainer

## 데모 스크립트의 [code]@export[/code] 변수를 읽어 슬라이더/체크박스/드롭다운을
## 자동으로 만들어 주는 패널.
##
## 데모마다 UI를 손으로 짜면 파라미터를 하나 추가할 때마다 UI도 고쳐야 한다.
## 여기서는 [method Script.get_script_property_list] 로 스크립트에 선언된 export 변수만
## 골라내 UI를 생성하므로, 데모는 변수만 추가하면 슬라이더가 저절로 생긴다.

signal parameter_changed

## 사용자가 만든 프리셋이 저장되는 곳.
## [code]user://[/code] 는 내보낸 게임에서도 쓸 수 있는 유일한 쓰기 가능 경로다.
## (Windows 기준 [code]%APPDATA%\Godot\app_userdata\Jiggle\[/code])
const SAVE_PATH := "user://presets.json"

var _target: Object = null
var _labels: Dictionary = {}
var _refreshers: Array[Callable] = []
var _suppress := false
var _status_label: Label = null


## [param target] 의 export 변수로 패널을 다시 만든다.
## [param target] 이 [code]get_param_labels()[/code] 를 가지고 있으면 한글 라벨로 바꿔 준다.
## [code]get_presets()[/code] 를 가지고 있으면 프리셋 버튼도 만든다.
func build_for(target: Object) -> void:
	_target = target
	_refreshers.clear()
	_labels = {}
	_status_label = null
	add_theme_constant_override("separation", 6)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if target == null:
		return

	if target.has_method(&"get_param_labels"):
		_labels = target.call(&"get_param_labels")
	if target.has_method(&"get_presets"):
		_add_presets(target.call(&"get_presets"))
	_add_save_row()

	var script := target.get_script() as Script
	if script == null:
		return
	for info in script.get_script_property_list():
		var usage: int = info.usage
		if (usage & PROPERTY_USAGE_CATEGORY) != 0:
			continue
		if (usage & (PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP)) != 0:
			_add_header(String(info.name))
			continue
		if (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		_add_property(info)

	refresh_values()


## 데모가 코드로 값을 바꿨을 때 UI를 동기화한다(프리셋 적용 등).
func refresh_values() -> void:
	_suppress = true
	for refresher in _refreshers:
		refresher.call()
	_suppress = false


func _display_name(property: StringName) -> String:
	if _labels.has(property):
		return String(_labels[property])
	return String(property).capitalize()


func _add_header(text: String) -> void:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 8.0)
	add_child(spacer)
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	label.add_theme_font_size_override("font_size", 13)
	add_child(label)


func _add_presets(presets: Dictionary) -> void:
	if presets.is_empty():
		return
	_add_header("프리셋")
	var flow := HFlowContainer.new()
	add_child(flow)
	for preset_name: String in presets:
		var button := Button.new()
		button.text = preset_name
		button.pressed.connect(_on_preset_pressed.bind(preset_name))
		flow.add_child(button)


func _on_preset_pressed(preset_name: String) -> void:
	if _target != null and _target.has_method(&"apply_preset"):
		_target.call(&"apply_preset", preset_name)
	refresh_values()
	parameter_changed.emit()


## 지금 만진 값을 파일로 남기고 다시 불러오는 줄.
## 슬라이더를 한참 만져 마음에 드는 느낌을 찾았는데 데모를 바꾸면 날아가는 게 제일 아깝다.
func _add_save_row() -> void:
	_add_header("내 설정")
	var row := HBoxContainer.new()
	add_child(row)

	var save_button := Button.new()
	save_button.text = "저장"
	save_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	save_button.pressed.connect(save_current)
	row.add_child(save_button)

	var load_button := Button.new()
	load_button.text = "불러오기"
	load_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	load_button.pressed.connect(load_saved)
	row.add_child(load_button)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.85))
	_status_label.text = "저장된 설정 있음" if _has_saved() else "저장된 설정 없음"
	add_child(_status_label)


## 현재 데모의 export 값을 전부 JSON으로 저장한다. 데모별로 따로 보관한다.
func save_current() -> void:
	if _target == null:
		return
	var all := _read_file()
	var values := {}
	for property in _editable_properties():
		values[String(property)] = _target.get(property)
	all[_demo_key()] = values

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		_set_status("저장 실패: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(all, "\t"))
	file.close()
	_set_status("%d개 값 저장됨" % values.size())


func load_saved() -> void:
	if _target == null:
		return
	var all := _read_file()
	var key := _demo_key()
	if not all.has(key):
		_set_status("이 데모의 저장본이 없다")
		return
	var values: Dictionary = all[key]
	var applied := 0
	for property in _editable_properties():
		var name := String(property)
		if not values.has(name):
			continue
		# JSON은 int를 float로 만들어 돌려준다. 원래 타입에 맞춰 되돌린다.
		var current: Variant = _target.get(property)
		var loaded: Variant = values[name]
		if typeof(current) == TYPE_INT:
			loaded = int(loaded)
		elif typeof(current) == TYPE_BOOL:
			loaded = bool(loaded)
		_target.set(property, loaded)
		applied += 1
	refresh_values()
	parameter_changed.emit()
	_set_status("%d개 값 불러옴" % applied)


func _demo_key() -> String:
	if _target.has_method(&"get_demo_title"):
		return String(_target.call(&"get_demo_title"))
	return _target.get_class()


## 저장 대상 속성 목록. UI에 뜨는 것과 정확히 같은 기준을 쓴다.
func _editable_properties() -> Array[StringName]:
	var names: Array[StringName] = []
	var script := _target.get_script() as Script
	if script == null:
		return names
	for info in script.get_script_property_list():
		var usage: int = info.usage
		if (usage & PROPERTY_USAGE_EDITOR) == 0:
			continue
		if (usage & (PROPERTY_USAGE_CATEGORY | PROPERTY_USAGE_GROUP | PROPERTY_USAGE_SUBGROUP)) != 0:
			continue
		var type: int = info.type
		if type == TYPE_BOOL or type == TYPE_INT or type == TYPE_FLOAT:
			names.append(info.name)
	return names


func _read_file() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed if parsed is Dictionary else {}


func _has_saved() -> bool:
	return _read_file().has(_demo_key())


func _set_status(message: String) -> void:
	if _status_label != null:
		_status_label.text = message


func _add_property(info: Dictionary) -> void:
	var property: StringName = info.name
	var type: int = info.type
	var hint: int = info.hint
	var hint_string: String = info.hint_string

	if type == TYPE_BOOL:
		_add_bool(property)
	elif type == TYPE_INT and hint == PROPERTY_HINT_ENUM:
		_add_enum(property, hint_string)
	elif (type == TYPE_FLOAT or type == TYPE_INT) and hint == PROPERTY_HINT_RANGE:
		_add_range(property, hint_string, type == TYPE_INT)
	# 그 외 타입(Vector3, Color 등)은 데모에서 슬라이더로 쪼개 노출한다.


func _add_bool(property: StringName) -> void:
	var check := CheckButton.new()
	check.text = _display_name(property)
	add_child(check)

	var on_toggled := func(pressed: bool) -> void:
		_on_value_changed(pressed, property)
	check.toggled.connect(on_toggled)

	var refresher := func() -> void:
		check.set_pressed_no_signal(bool(_target.get(property)))
	_refreshers.append(refresher)


func _add_enum(property: StringName, hint_string: String) -> void:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	var label := Label.new()
	label.text = _display_name(property)
	row.add_child(label)

	var option := OptionButton.new()
	row.add_child(option)

	var values: Array[int] = []
	for token in hint_string.split(",", false):
		var parts := token.split(":")
		var item_value := values.size()
		if parts.size() > 1:
			item_value = parts[1].to_int()
		option.add_item(parts[0].strip_edges(), item_value)
		values.append(item_value)

	var on_selected := func(index: int) -> void:
		_on_value_changed(option.get_item_id(index), property)
	option.item_selected.connect(on_selected)

	var refresher := func() -> void:
		var index := values.find(int(_target.get(property)))
		if index >= 0:
			option.selected = index
	_refreshers.append(refresher)


func _add_range(property: StringName, hint_string: String, is_int: bool) -> void:
	var numbers: Array[float] = []
	for token in hint_string.split(",", false):
		if token.is_valid_float():
			numbers.append(token.to_float())
	if numbers.size() < 2:
		return

	var minimum := numbers[0]
	var maximum := numbers[1]
	var step := 1.0 if is_int else (maximum - minimum) / 200.0
	if numbers.size() >= 3:
		step = numbers[2]

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)
	add_child(row)

	var header := HBoxContainer.new()
	row.add_child(header)
	var label := Label.new()
	label.text = _display_name(property)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(label)
	var value_label := Label.new()
	value_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	header.add_child(value_label)

	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.custom_minimum_size = Vector2(0.0, 18.0)
	row.add_child(slider)

	var format := "%d" if is_int else "%.3f"

	var on_changed := func(value: float) -> void:
		value_label.text = format % value
		_on_value_changed(int(value) if is_int else value, property)
	slider.value_changed.connect(on_changed)

	var refresher := func() -> void:
		var current := float(_target.get(property))
		slider.set_value_no_signal(current)
		value_label.text = format % current
	_refreshers.append(refresher)


func _on_value_changed(value: Variant, property: StringName) -> void:
	if _suppress or _target == null:
		return
	_target.set(property, value)
	parameter_changed.emit()
