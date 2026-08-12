class_name Rig4Scene
extends Node3D

## adachi_rigged4 캐릭터 한 벌을 흔들어 주는 씬 스크립트.
##
## [b]이 스크립트는 시뮬레이터를 만들지 않는다.[/b] 모디파이어 · 충돌체는 전부
## [code].tscn[/code] 안에 [b]실제 노드로[/b] 들어 있다. 씬을 열면 트리에 그대로 보이고
## 인스펙터에서 값을 고칠 수 있다.
##
## 여기서 하는 일은 세 가지뿐이다.
## [codeblock]
## 자극(걷기 · 점프 …)으로 캐릭터를 움직인다  ← 흔들림은 가만히 있으면 안 보인다
## 리셋 · 껐다 켜기 같은 조작을 받는다
## 화면 위에 어떤 시뮬레이터인지 표시한다
## [/codeblock]
##
## [b]씬 두 개[/b]
## [codeblock]
## adachi_rigged4_jiggle.tscn    JiggleChainModifier3D 36개
## adachi_rigged4_springbone.tscn    SpringBoneSimulator3D 1개(설정 슬롯 36개)
## [/codeblock]
## 나란히 보려면 [code]adachi_rigged4_compare.tscn[/code] 을 연다.
##
## 씬을 다시 만들려면: [code]tools/make_rig4_scenes.gd[/code]

## 화면에 띄울 이름. 어느 쪽을 보고 있는지 스크린샷만 봐도 알 수 있게 한다.
@export var title := ""
## 캐릭터를 담고 있는 노드 이름(글b 인스턴스).
@export var character_path := NodePath("Character")

@export_group("자극")
@export var stimulus_kind: Stimulus.Kind = Stimulus.Kind.WALK
@export_range(0.1, 3.0, 0.05) var stimulus_speed := 1.0
@export_range(0.0, 2.5, 0.05) var stimulus_amount := 1.0

## 비교 씬이 켠다. 켜지면 자기 자극·HUD·무대를 쓰지 않고 밖에서 시키는 대로만 움직인다.
## [b]자극을 각자 돌리면 두 캐릭터의 위상이 어긋나 비교가 무의미해진다.[/b]
@export var external_drive := false

var character: Node3D = null
var chain_modifiers: Array[JiggleChainModifier3D] = []
var spring_simulator: SpringBoneSimulator3D = null

var _stimulus := Stimulus.new()
var _info: Label = null
var _usec := 0.0
var _simulating := true


func _ready() -> void:
	character = get_node_or_null(character_path) as Node3D
	_collect()
	_stimulus.kind = stimulus_kind
	_stimulus.speed = stimulus_speed
	_stimulus.amount = stimulus_amount
	# 비교 씬이 인스턴스로 쓸 때는 무대·HUD 를 만들지 않는다. 카메라가 둘이 되면 안 된다.
	if external_drive:
		return
	Rig4Scene.build_stage(self, character, 0.0)
	_build_hud()


func _process(delta: float) -> void:
	if external_drive:
		return
	if _simulating:
		_stimulus.step(delta)
	apply_motion(_stimulus.offset, _stimulus.euler)
	_update_hud()


func _unhandled_key_input(event: InputEvent) -> void:
	if external_drive:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			_stimulus.trigger_impulse()
		KEY_R:
			reset_simulation()
			_stimulus.reset()
		KEY_TAB:
			_simulating = not _simulating
			set_simulating(_simulating)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6:
			_stimulus.kind = (key.keycode - KEY_1) as Stimulus.Kind
			_stimulus.reset()
			reset_simulation()
		_:
			return
	get_viewport().set_input_as_handled()


# --- 밖에서 부르는 것 ---------------------------------------------------------


## 캐릭터를 자극 위치로 옮긴다. 비교 씬이 두 캐릭터에 [b]같은 값[/b]을 넣는다.
func apply_motion(offset: Vector3, euler: Vector3) -> void:
	if character != null:
		character.transform = Transform3D(Basis.from_euler(euler), offset)


func set_simulating(value: bool) -> void:
	_simulating = value
	for modifier in chain_modifiers:
		modifier.active = value
	if spring_simulator != null:
		spring_simulator.active = value


func reset_simulation() -> void:
	for modifier in chain_modifiers:
		modifier.reset_simulation()
	if spring_simulator != null:
		spring_simulator.reset()


## 이번 프레임 시뮬레이션 비용(마이크로초). 내장 쪽은 잴 방법이 없어 0이다.
func total_usec() -> int:
	var total := 0
	for modifier in chain_modifiers:
		total += modifier.last_usec
	return total


func simulator_count() -> int:
	if spring_simulator != null:
		return spring_simulator.get_setting_count()
	return chain_modifiers.size()


# --- 내부 -------------------------------------------------------------------


## 씬에 이미 들어 있는 시뮬레이터 노드를 찾아 둔다. 만들지 않는다.
func _collect() -> void:
	chain_modifiers.clear()
	spring_simulator = null
	_walk(self)


func _walk(node: Node) -> void:
	var chain := node as JiggleChainModifier3D
	if chain != null:
		chain_modifiers.append(chain)
	var spring := node as SpringBoneSimulator3D
	if spring != null:
		spring_simulator = spring
	for child in node.get_children():
		_walk(child)


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
	heading.add_theme_font_size_override("font_size", 26)
	heading.text = title
	column.add_child(heading)

	_info = Label.new()
	_info.add_theme_font_size_override("font_size", 15)
	column.add_child(_info)


func _update_hud() -> void:
	if _info == null:
		return
	_usec = lerpf(_usec, float(total_usec()), 0.08)
	var cost := "" if spring_simulator != null else "  ·  %.2f ms" % (_usec * 0.001)
	_info.text = (
		"사슬 %d · 자극 %s%s\n[1~6] 자극  [Space] 임펄스  [R] 리셋  [Tab] 시뮬레이션 %s"
		+ "\n카메라: 우클릭 드래그 회전 · 휠 줌 · 가운데 드래그 이동"
	) % [
		simulator_count(),
		Rig4Scene.stimulus_name(_stimulus.kind),
		cost,
		"끄기" if _simulating else "켜기",
	]


# --- 무대 --------------------------------------------------------------------


## 카메라 · 조명 · 하늘 · 바닥을 만들어 [param parent] 에 붙인다.
##
## [b]씬 파일에 넣지 않고 코드로 만든다.[/b] 씬에 들어가야 하는 것은 "무엇을 흔드는가"
## (모디파이어 · 충돌체)이지 조명이 아니다. 무대까지 씬에 넣으면 비교 씬이 인스턴스로
## 가져올 때 카메라가 둘이 되고, 그걸 끄는 코드가 또 필요해진다.
##
## [param spread] 는 좌우로 벌어진 폭. 나란히 놓을 때 둘 다 화면에 넣으려고 뒤로 뺀다.
static func build_stage(parent: Node3D, character: Node3D, spread: float) -> void:
	var metrics := measure(character)
	var focus: Vector3 = metrics["focus"]
	var height: float = metrics["height"]
	# 나란히 놓았을 때는 둘의 가운데를 본다. 한쪽 캐릭터 기준으로 잡으면 화면이 치우친다.
	if spread > 0.0:
		focus.x = 0.0

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.10, 0.11, 0.13)
	material.roughness = 0.95
	ground.material_override = material
	ground.position = Vector3(0.0, metrics["ground_y"], 0.0)
	parent.add_child(ground)

	var light := DirectionalLight3D.new()
	light.name = "Sun"
	light.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(-38.0), 0.0)
	light.light_energy = 1.15
	light.shadow_enabled = true
	parent.add_child(light)

	var environment := WorldEnvironment.new()
	environment.name = "WorldEnvironment"
	var settings := Environment.new()
	settings.background_mode = Environment.BG_SKY
	settings.sky = Sky.new()
	settings.sky.sky_material = ProceduralSkyMaterial.new()
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	settings.ambient_light_energy = 0.45
	environment.environment = settings
	parent.add_child(environment)

	# 데모 허브와 같은 궤도 카메라. 우클릭 드래그로 돌려 보고 휠로 확대해야
	# 치맛자락 안쪽이나 뒤통수처럼 [b]정면에서 안 보이는 곳[/b]을 확인할 수 있다.
	var camera := OrbitCamera.new()
	camera.name = "OrbitCamera"
	camera.focus = focus
	camera.distance = height * 1.35 + spread * 1.6
	# 나란히 놓을 때는 정면에서 봐야 좌우 비교가 공평하다. 하나만 볼 때는 살짝 돌려 입체감을 준다.
	camera.yaw = 0.0 if spread > 0.0 else deg_to_rad(26.0)
	camera.pitch = deg_to_rad(-6.0)
	# 이 캐릭터는 월드 기준 90cm 남짓이라 기본 최소 거리(0.6m)로는 가까이 못 간다.
	camera.min_distance = 0.12
	camera.current = true
	parent.add_child(camera)


## 카메라를 어디에 둘지 리그 치수에서 뽑는다. 모델이 바뀌어도 다시 맞출 필요가 없다.
static func measure(character: Node3D) -> Dictionary:
	var skeleton := _find_skeleton(character)
	if skeleton == null:
		return {"focus": Vector3(0.0, 1.0, 0.0), "height": 1.7, "ground_y": 0.0}
	var world := skeleton.global_transform
	var head := (world * skeleton.get_bone_global_pose(skeleton.find_bone("Head"))).origin
	var foot := (world * skeleton.get_bone_global_pose(skeleton.find_bone("foot.L"))).origin
	var hip := (world * skeleton.get_bone_global_pose(skeleton.find_bone("spine"))).origin
	# Head 본은 목 밑이라 머리카락 높이가 빠진다. 그만큼 얹어 실제 실루엣에 맞춘다.
	var height := maxf(head.y - foot.y, 0.3) * 1.25
	return {
		"focus": Vector3(hip.x, (head.y + foot.y) * 0.5 + height * 0.10, hip.z),
		"height": height,
		"ground_y": foot.y,
	}


static func _find_skeleton(node: Node) -> Skeleton3D:
	var found := node as Skeleton3D
	if found != null:
		return found
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result != null:
			return result
	return null


static func stimulus_name(kind: Stimulus.Kind) -> String:
	match kind:
		Stimulus.Kind.IDLE:
			return "정지"
		Stimulus.Kind.BOUNCE:
			return "점프"
		Stimulus.Kind.SIDE_STEP:
			return "좌우 이동"
		Stimulus.Kind.TWIST:
			return "몸통 회전"
		Stimulus.Kind.SHOCK:
			return "급정거"
		_:
			return "걷기"
