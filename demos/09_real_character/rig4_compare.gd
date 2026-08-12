class_name Rig4Compare
extends Node3D

## 직접 만든 모디파이어와 내장 [SpringBoneSimulator3D] 를 [b]나란히[/b] 놓고 비교하는 씬.
##
## 두 캐릭터 씬을 인스턴스로 가져와 좌우에 세우고, [b]자극 하나로 둘 다 움직인다.[/b]
## 각자 자기 자극을 돌리게 두면 위상이 조금씩 어긋나 "어느 쪽이 더 흔들리는가"를
## 판단할 수 없게 된다 — 같은 순간에 같은 힘을 받아야 비교가 성립한다.
##
## [codeblock]
## Rig4Compare
##  ├─ Jiggle      adachi_rigged4_jiggle.tscn  (external_drive = true)
##  ├─ SpringBone  adachi_rigged4_springbone.tscn  (external_drive = true)
##  └─ Stage       카메라 · 조명 · 바닥 (하나만 있다)
## [/codeblock]
##
## 씬을 다시 만들려면: [code]tools/make_rig4_scenes.gd[/code]

@export var left_path := NodePath("Jiggle")
@export var right_path := NodePath("SpringBone")
## 두 캐릭터가 좌우로 벌어진 거리(m). 카메라를 그만큼 뒤로 뺀다.
@export var spread := 0.30

@export_group("자극")
@export var stimulus_kind: Stimulus.Kind = Stimulus.Kind.WALK
@export_range(0.1, 3.0, 0.05) var stimulus_speed := 1.0
@export_range(0.0, 2.5, 0.05) var stimulus_amount := 1.0

var left: Rig4Scene = null
var right: Rig4Scene = null

var _stimulus := Stimulus.new()
var _info: Label = null
var _usec := 0.0
var _simulating := true


func _ready() -> void:
	left = get_node_or_null(left_path) as Rig4Scene
	right = get_node_or_null(right_path) as Rig4Scene
	# 인스턴스된 씬이 자기 자극·무대·HUD 를 쓰지 않게 한다.
	# _ready() 순서상 자식이 먼저 돌므로, 씬 파일에서 미리 켜 둔 값을 여기서 덮지 않는다.
	_stimulus.kind = stimulus_kind
	_stimulus.speed = stimulus_speed
	_stimulus.amount = stimulus_amount
	# 무대는 [b]하나만[/b] 만든다. 두 캐릭터 씬은 external_drive 라 각자 만들지 않는다.
	if left != null and left.character != null:
		Rig4Scene.build_stage(self, left.character, spread)
	_build_hud()


func _process(delta: float) -> void:
	if _simulating:
		_stimulus.step(delta)
	# 같은 값을 양쪽에 넣는다. 이 한 줄이 비교의 전제다.
	if left != null:
		left.apply_motion(_stimulus.offset, _stimulus.euler)
	if right != null:
		right.apply_motion(_stimulus.offset, _stimulus.euler)
	_update_hud()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			_stimulus.trigger_impulse()
		KEY_R:
			_reset()
		KEY_TAB:
			_simulating = not _simulating
			_for_both(func(scene: Rig4Scene) -> void: scene.set_simulating(_simulating))
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_stimulus.kind = (key.keycode - KEY_1) as Stimulus.Kind
			_reset()
		_:
			return
	get_viewport().set_input_as_handled()


func _reset() -> void:
	_stimulus.reset()
	_for_both(func(scene: Rig4Scene) -> void: scene.reset_simulation())


func _for_both(action: Callable) -> void:
	if left != null:
		action.call(left)
	if right != null:
		action.call(right)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_WIDE)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_top", 14)
	layer.add_child(margin)

	var column := VBoxContainer.new()
	margin.add_child(column)

	var heading := Label.new()
	heading.add_theme_font_size_override("font_size", 24)
	heading.text = "왼쪽 = JiggleChainModifier3D    ·    오른쪽 = 내장 SpringBoneSimulator3D"
	column.add_child(heading)

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 15)
	column.add_child(_info)


func _update_hud() -> void:
	if _info == null:
		return
	if left != null:
		_usec = lerpf(_usec, float(left.total_usec()), 0.08)
	_info.text = (
		"같은 캐릭터 · 같은 자극(%s) · 같은 파라미터 — 차이는 시뮬레이터에서만 온다\n"
		+ "Jiggle %.2f ms · 사슬 %d    |    내장은 비용을 잴 방법이 없다\n"
		+ "치맛자락과 앞리본을 보라. 내장에는 모양 유지(shape_stiffness)에 해당하는 항이 없다\n"
		+ "[1~6] 자극  [Space] 임펄스  [R] 리셋  [Tab] 시뮬레이션 %s"
		+ "    |    카메라: 우클릭 드래그 회전 · 휠 줌 · 가운데 드래그 이동"
	) % [
		Rig4Scene.stimulus_name(_stimulus.kind),
		_usec * 0.001,
		left.simulator_count() if left != null else 0,
		"끄기" if _simulating else "켜기",
	]
