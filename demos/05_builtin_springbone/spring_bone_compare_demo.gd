class_name SpringBoneCompareDemo
extends JiggleDemo

## 데모 05 — 자작 Verlet 사슬 vs 내장 [SpringBoneSimulator3D]
##
## [b]완전히 같은 리그[/b]([HairRig])를 두 개 놓고, 왼쪽은 데모 03의 자작 모디파이어로,
## 오른쪽은 Godot 4.4+ 내장 [SpringBoneSimulator3D] 로 흔든다.
## 같은 자극을 동시에 받으므로 차이가 곧 [b]구현의 차이[/b]다.
##
## [color=#ff8c5a]주황 머리 = 자작[/color] · [color=#5aa8ff]파랑 머리 = 내장[/color]

const GROUND_COLOR := Color(0.10, 0.11, 0.13)
const CUSTOM_COLOR := Color(0.62, 0.28, 0.14)
const BUILTIN_COLOR := Color(0.16, 0.30, 0.58)
const SLOT_X := 0.36
## 내장 stiffness(0~1, 단위 없음)를 자작 복원 진동수(Hz)로 옮기는 계수.
## 정확한 대응이 아니라 "눈으로 비슷해 보이는" 값이다 — 그게 이 데모의 요점 중 하나다.
const STIFFNESS_TO_HZ := 3.5
## 내장 drag(0~1)를 자작 drag(스텝당 속도 감쇠율)로 옮기는 계수.
const DRAG_SCALE := 0.12
## [b]내장 [code]gravity[/code] 는 m/s² 가 아니다.[/b] VRM SpringBone 계열의 무단위 "중력 세기"라
## 스프링 항과 같은 축척으로 더해진다. 실제 중력값 9.8을 그대로 넣으면 중력 항이 다른 모든 항을
## 압도해 머리카락이 아래로 못 박히고 [b]흔들림이 통째로 사라진다[/b].
##
## 실측으로 맞춘 환산 계수(자작 9.0 m/s² ↔ 내장 1.0 일 때 진폭이 0.077 vs 0.0787 로 일치):
const GRAVITY_TO_POWER := 1.0 / 9.0

@export_group("공통 파라미터")
## 내장 [code]stiffness[/code] 에 그대로 들어가고, 자작에는 Hz로 환산되어 들어간다.
@export_range(0.0, 1.0, 0.01) var stiffness := 0.5
## 내장 [code]drag[/code] 에 그대로, 자작에는 스텝당 감쇠율로 환산.
@export_range(0.0, 1.0, 0.01) var damping := 0.3
## 자작 기준 m/s². 내장 쪽에는 [constant GRAVITY_TO_POWER] 로 환산해 넣는다
## — 내장 [code]gravity[/code] 는 단위가 없는 "중력 세기"라 9.8을 그대로 넣으면 안 된다.
@export_range(0.0, 20.0, 0.5) var gravity := 9.0
## 충돌 두께. 내장 [code]radius[/code] ↔ 자작 [code]particle_radius[/code].
@export_range(0.002, 0.05, 0.002) var thickness := 0.008
@export var collision_enabled := true
## 양쪽 모두 같은 이름의 외력 속성으로 들어간다.
@export_range(0.0, 30.0, 0.5) var wind := 0.0

@export_group("자작에만 있는 것")
## 내장에는 대응하는 개념이 아예 없다. 길이는 항상 고정이다.
@export_range(1, 16, 1) var iterations := 6
## 내장에는 각도 제한이 없다. 0이면 끔.
@export_range(0.0, 90.0, 1.0) var angle_limit_degrees := 35.0

@export_group("자극")
@export_range(0.1, 3.0, 0.05) var stimulus_speed := 1.0
@export_range(0.0, 2.5, 0.05) var stimulus_amount := 1.0

@export_group("보기")
@export var show_custom := true
@export var show_builtin := true
@export var show_trails := true

var _custom_rig: HairRig
var _builtin_rig: HairRig
var _modifiers: Array[JiggleChainModifier3D] = []
var _simulator: SpringBoneSimulator3D
var _head_collision: SpringBoneCollisionSphere3D
var _reader: JigglePoseReader3D
var _custom_usec := 0.0
var _frame_msec := 0.0
var _no_colliders: Array[JiggleVerletBody.Collider] = []


func _build() -> void:
	stimulus.kind = Stimulus.Kind.TWIST

	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = GROUND_COLOR
	ground_material.roughness = 0.95
	ground.material_override = ground_material
	add_child(ground)

	_custom_rig = _make_rig("CustomRig", CUSTOM_COLOR)
	_builtin_rig = _make_rig("BuiltinRig", BUILTIN_COLOR)

	# --- 왼쪽: 자작 모디파이어. 다발마다 하나씩 붙인다. ---
	for strand in _custom_rig.strands:
		var modifier := JiggleChainModifier3D.new()
		modifier.name = "Chain_%s" % strand["root"]
		modifier.root_bone_name = String(strand["root"])
		modifier.end_bone_name = String(strand["end"])
		modifier.tip_axis = strand["tip_axis"]
		modifier.tip_length = strand["tip_length"]
		_custom_rig.skeleton.add_child(modifier)
		_modifiers.append(modifier)

	# --- 오른쪽: 내장 시뮬레이터 하나가 모든 다발을 담당한다. ---
	# 자작은 "다발 하나 = 모디파이어 하나"였지만, 내장은 "설정 슬롯"을 여러 개 갖는다.
	_simulator = SpringBoneSimulator3D.new()
	_simulator.name = "SpringBoneSimulator3D"
	_builtin_rig.skeleton.add_child(_simulator)
	_simulator.set_setting_count(_builtin_rig.strands.size())
	for index in _builtin_rig.strands.size():
		var strand: Dictionary = _builtin_rig.strands[index]
		_simulator.set_root_bone_name(index, String(strand["root"]))
		_simulator.set_end_bone_name(index, String(strand["end"]))
		# 마지막 본에는 자식이 없다. 끝점을 만들어 달라고 알려 줘야 한다.
		_simulator.set_extend_end_bone(index, true)
		_simulator.set_end_bone_direction(index, SkeletonModifier3D.BONE_DIRECTION_FROM_PARENT)
		_simulator.set_end_bone_length(index, strand["tip_length"])
		_simulator.set_enable_all_child_collisions(index, true)
	_head_collision = _builtin_rig.add_spring_bone_collider()

	# 시뮬레이터 [b]뒤에[/b] 붙여야 그 결과를 읽을 수 있다. 자식 순서가 곧 실행 순서다.
	# get_bone_global_pose() 를 밖에서 부르면 모디파이어 이전 값(rest)이 나온다.
	_reader = JigglePoseReader3D.new()
	_reader.name = "PoseReader"
	_builtin_rig.skeleton.add_child(_reader)


func _make_rig(rig_name: String, color: Color) -> HairRig:
	var rig := HairRig.new()
	rig.name = rig_name
	add_child(rig)
	rig.build(8, 6, 0.055)
	rig.set_hair_color(color)
	return rig


func _frame_update(_delta: float) -> void:
	var basis := Basis.from_euler(stimulus.euler)
	_custom_rig.transform = Transform3D(basis, stimulus.offset + Vector3(-SLOT_X, 0.0, 0.0))
	_builtin_rig.transform = Transform3D(basis, stimulus.offset + Vector3(SLOT_X, 0.0, 0.0))
	_custom_rig.refresh_colliders()
	_custom_rig.visible = show_custom
	_builtin_rig.visible = show_builtin

	var total := 0
	for modifier in _modifiers:
		total += modifier.last_usec
	_custom_usec = lerpf(_custom_usec, float(total), 0.08)
	_frame_msec = lerpf(_frame_msec, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.08)


func reset_demo() -> void:
	stimulus.reset()
	if _custom_rig == null:
		return
	for rig in [_custom_rig, _builtin_rig]:
		rig.transform = Transform3D.IDENTITY
		rig.reset_pose()
	_custom_rig.refresh_colliders()
	for modifier in _modifiers:
		modifier.reset_simulation()
	if _simulator != null:
		_simulator.reset()


func on_params_changed() -> void:
	stimulus.speed = stimulus_speed
	stimulus.amount = stimulus_amount
	if _custom_rig == null:
		return

	# --- 자작 ---
	var restore := JiggleSpring.params_from_frequency(stiffness * STIFFNESS_TO_HZ, 1.0).x
	for modifier in _modifiers:
		var chain := modifier.chain
		chain.iterations = iterations
		chain.restore_stiffness = restore if stiffness > 0.0 else 0.0
		chain.drag = damping * DRAG_SCALE
		chain.gravity = Vector3.DOWN * gravity
		chain.particle_radius = thickness
		chain.angle_limit = deg_to_rad(angle_limit_degrees)
		chain.external_force = Vector3.BACK * wind
		chain.colliders = _custom_rig.head_collider_only() if collision_enabled else _no_colliders
		modifier.active = show_custom

	# --- 내장 ---
	# 이름이 같은 것끼리 이어 붙였을 뿐, 단위가 같다는 보장은 없다.
	for index in _simulator.get_setting_count():
		_simulator.set_stiffness(index, stiffness)
		_simulator.set_drag(index, damping)
		# 여기가 이 데모에서 가장 중요한 한 줄이다. 같은 이름이라고 같은 단위가 아니다.
		_simulator.set_gravity(index, gravity * GRAVITY_TO_POWER)
		_simulator.set_gravity_direction(index, Vector3.DOWN)
		_simulator.set_radius(index, thickness)
		_simulator.set_enable_all_child_collisions(index, collision_enabled)
	_simulator.external_force = Vector3.BACK * wind
	_simulator.active = show_builtin


func _draw_debug() -> void:
	if not show_trails:
		return
	if show_custom:
		for modifier in _modifiers:
			debug.polyline(modifier.reconstructed, Color(1.0, 0.65, 0.35, 0.6))
	if show_builtin and show_custom:
		# 같은 위치로 겹쳐 그려 두 결과가 얼마나 어긋나는지 직접 비교한다.
		for index in _builtin_rig.strands.size():
			var points := _builtin_chain_points(index)
			for i in points.size():
				points[i] -= Vector3(SLOT_X * 2.0, 0.0, 0.0)
			debug.polyline(points, Color(0.45, 0.75, 1.0, 0.6))
	if show_builtin:
		for index in _builtin_rig.strands.size():
			debug.polyline(_builtin_chain_points(index), Color(0.45, 0.75, 1.0, 0.6))


## 내장 쪽 결과를 읽는다.
##
## 자작 쪽은 파티클 위치를 그대로 들여다볼 수 있지만, 내장은 [b]본 포즈밖에[/b] 볼 수 없다.
## 게다가 그 포즈조차 [JigglePoseReader3D] 를 뒤에 붙여야 읽힌다.
func _builtin_chain_points(index: int) -> PackedVector3Array:
	var skeleton := _builtin_rig.skeleton
	var points := PackedVector3Array()
	if _reader == null or _reader.world_positions.size() != skeleton.get_bone_count():
		return points
	var bone := skeleton.find_bone(_simulator.get_root_bone_name(index))
	var end_bone := skeleton.find_bone(_simulator.get_end_bone_name(index))
	while bone >= 0:
		points.append(_reader.world_positions[bone])
		if bone == end_bone:
			break
		var children := skeleton.get_bone_children(bone)
		bone = children[0] if not children.is_empty() else -1
	return points


## 양쪽 [b]마지막 본의 원점[/b]이 rest에서 얼마나 벗어났는지를 비교한다.
## 두 리그는 X로 SLOT_X*2 만큼 떨어져 있을 뿐 기하가 완전히 같으므로 rest를 공유할 수 있다.
func sample_plot() -> Dictionary:
	if _modifiers.is_empty():
		return {}
	var strand := _modifiers.size() / 2
	var modifier := _modifiers[strand]
	if modifier.rest_points.size() < 2:
		return {}
	var last_bone := modifier.rest_points.size() - 2
	var rest := modifier.rest_points[last_bone]

	var custom_offset := 0.0
	if modifier.reconstructed.size() > last_bone:
		custom_offset = modifier.reconstructed[last_bone].distance_to(rest)

	var builtin_offset := 0.0
	var builtin_points := _builtin_chain_points(strand)
	if not builtin_points.is_empty():
		var mirrored := rest + Vector3(SLOT_X * 2.0, 0.0, 0.0)
		builtin_offset = builtin_points[builtin_points.size() - 1].distance_to(mirrored)
	return {"custom": custom_offset, "builtin": builtin_offset}


func get_plot_series() -> Array[Dictionary]:
	return [
		{"id": "custom", "color": Color(1.0, 0.62, 0.30)},
		{"id": "builtin", "color": Color(0.45, 0.75, 1.0)},
	]


func get_plot_info() -> String:
	return "rest 대비 변위 m (주황=자작 · 파랑=내장)   |   자작 %.2fms 직접 계측   |   전체 프레임 %.2fms" % [
		_custom_usec / 1000.0, _frame_msec
	]


func get_demo_title() -> String:
	return "05 · 내장 SpringBone 비교"


func get_demo_description() -> String:
	return """[b]같은 리그, 같은 자극, 다른 구현.[/b] [color=#ff8c5a]왼쪽(주황) = 데모 03의 자작 Verlet 사슬[/color] · [color=#5aa8ff]오른쪽(파랑) = 내장 SpringBoneSimulator3D[/color].
[b]파라미터 대응표[/b]  내장 [code]stiffness[/code]·[code]drag[/code]·[code]gravity[/code]는 전부 [b]단위가 없다[/b]. 특히 [color=#ff8080][code]gravity[/code]에 9.8을 넣으면 안 된다[/color] — 중력 항이 스프링 항을 압도해 머리카락이 아래로 못 박히고 흔들림이 통째로 사라진다(실측: 진폭 0.0065m vs 정상 0.079m). 이 데모는 m/s²를 1/9 로 환산해 넣는다.
[b]자작에만 있는 것[/b] 제약 반복 횟수 · 각도 제한 · 파티클 위치를 직접 들여다보기. [b]내장에만 있는 것[/b] 감쇠 커브, 회전축 제한, 에디터에서 충돌체를 눈으로 배치.
[color=#8ab4ff]해볼 것[/color]  ① [b]강성[/b]과 [b]감쇠[/b]를 같이 움직인다 → 같은 숫자를 넣어도 두 결과가 정확히 겹치지는 않는다. 내장 파라미터는 [b]단위가 없어[/b] 물리량으로 환산할 수 없기 때문.
② [b]각도 제한[/b]을 0으로 → 자작만 반응한다. 내장에는 이 개념이 없다.
③ [b]바람[/b]을 올린다 → 양쪽 다 같은 이름의 [code]external_force[/code] 로 들어가고 거의 같게 반응한다.
④ 성능: 자작은 GDScript라 직접 계측된다. 내장은 C++ 내부라 계측할 수 없으니, [b]한쪽씩 꺼서 전체 프레임 시간의 차이[/b]로 비교하라.
[color=#ff8080]함정[/color]  모디파이어의 결과는 밖에서 [code]get_bone_global_pose()[/code] 로 읽으면 [b]항상 rest 값이 나온다[/b](스켈레톤이 처리 후 로컬 포즈를 되돌린다). 이 데모는 시뮬레이터 뒤에 [code]JigglePoseReader3D[/code] 를 한 개 더 붙여서 결과를 읽는다."""


func get_param_labels() -> Dictionary:
	return {
		&"show_debug": "디버그 표시",
		&"stiffness": "강성 (stiffness)",
		&"damping": "감쇠 (drag)",
		&"gravity": "중력",
		&"thickness": "충돌 두께 (radius)",
		&"collision_enabled": "충돌",
		&"wind": "바람 (external_force)",
		&"iterations": "제약 반복 횟수",
		&"angle_limit_degrees": "각도 제한 (0=무제한)",
		&"stimulus_speed": "자극 속도",
		&"stimulus_amount": "자극 세기",
		&"show_custom": "자작 보기",
		&"show_builtin": "내장 보기",
		&"show_trails": "사슬 선 표시",
	}


func get_presets() -> Dictionary:
	return {
		"기본": {
			&"stiffness": 0.5,
			&"damping": 0.3,
			&"gravity": 9.0,
			&"thickness": 0.008,
			&"wind": 0.0,
			&"iterations": 6,
			&"angle_limit_degrees": 35.0,
		},
		"흐물흐물": {&"stiffness": 0.05, &"damping": 0.1, &"angle_limit_degrees": 0.0},
		"뻣뻣": {&"stiffness": 0.95, &"damping": 0.7},
		"바람": {&"wind": 18.0, &"stiffness": 0.25, &"damping": 0.2},
		"자작만": {&"show_builtin": false, &"show_custom": true},
		"내장만": {&"show_builtin": true, &"show_custom": false},
	}


func get_camera_focus() -> Vector3:
	return Vector3(0.0, 1.26, 0.0)


func get_camera_distance() -> float:
	return 2.3


func smoke_check() -> String:
	if show_custom:
		for modifier in _modifiers:
			if modifier.reconstructed.is_empty():
				return "%s: 자작 모디파이어가 돌지 않았다" % modifier.name
	if _simulator.get_setting_count() != _builtin_rig.strands.size():
		return "내장 시뮬레이터 설정 개수가 맞지 않는다"
	for index in _simulator.get_setting_count():
		if _builtin_chain_points(index).size() < 2:
			return "내장 쪽 본 사슬을 읽지 못했다 (설정 %d)" % index
	return ""
