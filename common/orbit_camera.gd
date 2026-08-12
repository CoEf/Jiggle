class_name OrbitCamera
extends Camera3D

## 초점을 중심으로 도는 카메라.
## 우클릭 드래그 = 회전, 휠 = 줌, 가운데 버튼 드래그 = 초점 이동.

@export var focus := Vector3(0.0, 1.1, 0.0)
@export var distance := 3.2
@export var min_distance := 0.6
@export var max_distance := 30.0
@export var yaw := 0.5
@export var pitch := -0.12
@export var sensitivity := 0.006
@export var zoom_step := 1.12

var _orbiting := false
var _panning := false


func _ready() -> void:
	_apply()


## 데모를 바꿀 때 카메라를 그 데모에 맞게 옮긴다.
func frame_target(new_focus: Vector3, new_distance: float) -> void:
	focus = new_focus
	distance = new_distance
	_apply()


func _unhandled_input(event: InputEvent) -> void:
	var button := event as InputEventMouseButton
	if button != null:
		match button.button_index:
			MOUSE_BUTTON_RIGHT:
				_orbiting = button.pressed
			MOUSE_BUTTON_MIDDLE:
				_panning = button.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					distance /= zoom_step
					_apply()
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					distance *= zoom_step
					_apply()
		return

	var motion := event as InputEventMouseMotion
	if motion == null:
		return
	if _orbiting:
		yaw -= motion.relative.x * sensitivity
		pitch -= motion.relative.y * sensitivity
		_apply()
	elif _panning:
		# 화면 기준으로 초점을 민다. 거리에 비례시켜야 줌 상태와 무관하게 같은 속도로 느껴진다.
		var scale := distance * sensitivity * 0.6
		focus -= global_basis.x * motion.relative.x * scale
		focus += global_basis.y * motion.relative.y * scale
		_apply()


func _apply() -> void:
	pitch = clampf(pitch, -1.45, 1.45)
	distance = clampf(distance, min_distance, max_distance)
	var orbit := Basis.from_euler(Vector3(pitch, yaw, 0.0))
	global_position = focus + orbit * Vector3(0.0, 0.0, distance)
	look_at(focus, Vector3.UP)
