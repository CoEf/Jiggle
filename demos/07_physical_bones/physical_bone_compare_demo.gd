class_name PhysicalBoneCompareDemo
extends JiggleDemo

## 데모 07 — 자작 Verlet 사슬 vs 내장 [PhysicalBoneSimulator3D] (래그돌)
##
## 같은 꼬리를 두 개 매달아 놓고, 왼쪽은 Verlet 사슬로, 오른쪽은 [b]진짜 강체 물리[/b]로 흔든다.
## 오른쪽은 본 하나하나가 [PhysicalBone3D](= [RigidBody3D])이고, 관절은 콘 조인트다.
##
## [color=#ff8c5a]주황 = 자작[/color] · [color=#5aa8ff]파랑 = 물리 본[/color]
##
## [b]결론부터[/b]: 가슴·머리카락 같은 "보이기용 흔들림"에 래그돌을 쓰는 것은 거의 항상 과하다.
## 이 데모는 그 이유를 [b]직접 만져 보고 납득하기 위한 것[/b]이다.

const GROUND_COLOR := Color(0.10, 0.11, 0.13)
const CUSTOM_COLOR := Color(0.80, 0.40, 0.20)
const BUILTIN_COLOR := Color(0.30, 0.50, 0.85)
const SLOT_X := 0.30

@export_group("공통")
## 바꾸면 양쪽 꼬리를 다시 만든다.
@export_range(2, 10, 1) var segments := 5
@export_range(0.05, 0.2, 0.005) var segment_length := 0.11

@export_group("자작 (Verlet)")
@export_range(1, 16, 1) var iterations := 6
@export_range(0.0, 4.0, 0.05) var restore_frequency := 0.8
@export_range(0.0, 0.2, 0.005) var drag := 0.02
@export_range(0.0, 90.0, 1.0) var angle_limit_degrees := 40.0

@export_group("물리 본 (래그돌)")
## 콘 조인트가 허용하는 스윙 각도.
@export_range(1.0, 90.0, 1.0) var swing_span := 30.0
@export_range(0.05, 5.0, 0.05) var bone_mass := 0.3
## 각속도 감쇠. 이것 말고는 "얼마나 출렁일지"를 직접 지정할 방법이 없다.
@export_range(0.0, 20.0, 0.1) var angular_damp := 2.0
@export_range(0.0, 4.0, 0.05) var gravity_scale := 1.0

@export_group("자극")
@export_range(0.1, 3.0, 0.05) var stimulus_speed := 1.0
@export_range(0.0, 2.5, 0.05) var stimulus_amount := 1.0

@export_group("보기")
@export var show_custom := true
@export var show_builtin := true

var _custom_rig: TailRig
var _builtin_rig: TailRig
var _modifier: JiggleChainModifier3D
var _simulator: PhysicalBoneSimulator3D
var _reader: JigglePoseReader3D
var _physical_bones: Array[PhysicalBone3D] = []
var _structure := Vector2.ZERO
var _custom_usec := 0.0
var _physics_msec := 0.0
var _frame_msec := 0.0


func _build() -> void:
	stimulus.kind = Stimulus.Kind.SIDE_STEP

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

	_rebuild()


func _rebuild() -> void:
	for rig in [_custom_rig, _builtin_rig]:
		if rig != null:
			remove_child(rig)
			rig.queue_free()
	_physical_bones.clear()

	_custom_rig = TailRig.new()
	_custom_rig.name = "CustomTail"
	add_child(_custom_rig)
	_custom_rig.build(segments, segment_length, CUSTOM_COLOR)

	_modifier = JiggleChainModifier3D.new()
	_modifier.name = "Chain"
	_modifier.root_bone_name = _custom_rig.bone_names[0]
	_modifier.end_bone_name = _custom_rig.bone_names[segments - 1]
	_modifier.tip_axis = Vector3.DOWN
	_modifier.tip_length = segment_length
	_custom_rig.skeleton.add_child(_modifier)

	_builtin_rig = TailRig.new()
	_builtin_rig.name = "BuiltinTail"
	add_child(_builtin_rig)
	_builtin_rig.build(segments, segment_length, BUILTIN_COLOR)
	_build_physical_bones()

	_structure = Vector2(segments, segment_length)
	_apply_params()


## 물리 본 리그를 조립한다. [b]자작 쪽 한 줄짜리 설정과 비교해 보라.[/b]
##
## 본 하나마다 [PhysicalBone3D](강체) + [CollisionShape3D] + 조인트 설정이 필요하고,
## 노드 이름이 본 이름과 정확히 일치해야 결합된다.
func _build_physical_bones() -> void:
	var skeleton := _builtin_rig.skeleton
	_simulator = PhysicalBoneSimulator3D.new()
	_simulator.name = "PhysicalBoneSimulator3D"
	skeleton.add_child(_simulator)

	# 사슬의 [b]뿌리 본에도[/b] 물리 본이 있어야 한다.
	# 없으면 부모를 거슬러 올라가다 -1에서 끊겨 엔진이 에러를 낸다.
	# 대신 시뮬레이션 대상에서 빼면 애니메이션을 그대로 따라가는 고정점이 된다.
	_add_physical_bone("Anchor", 0.05, false)
	for index in segments:
		_add_physical_bone(_builtin_rig.bone_names[index], segment_length, true)

	_reader = JigglePoseReader3D.new()
	_reader.name = "PoseReader"
	skeleton.add_child(_reader)
	_start_simulation()


func _add_physical_bone(bone_name: String, length: float, simulated: bool) -> void:
	var physical := PhysicalBone3D.new()
	physical.name = bone_name
	_simulator.add_child(physical)
	# [b]노드 이름만으로는 본과 결합되지 않는다.[/b] bone_name 은 클래스에 선언된 속성이 아니라
	# 스켈레톤의 본 목록으로 만들어지는 동적 속성이라, add_child 뒤에 set() 으로 넣어야 한다.
	# 이걸 빠뜨리면 강체들이 아무 본에도 안 붙은 채 관절만 걸려 그대로 폭발한다.
	physical.set("bone_name", bone_name)

	physical.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
	# [b]body_offset 은 0으로 둔다.[/b]
	# "강체 중심을 마디 가운데로" 라고 생각해서 (0, -L/2, 0) 을 넣으면 조인트까지 같이 내려가
	# 마디마다 반 칸씩 겹쳐 붙는다. 실측: 사슬 길이가 기대값의 80%로 [b]쪼그라들었다[/b].
	#   offset -L/2 → 0.442 m (80%) · offset 0 → 0.578 m (105%) · offset +L/2 → 0.820 m (149%)
	physical.body_offset = Transform3D.IDENTITY
	physical.can_sleep = false

	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	# 이웃 마디의 캡슐과 겹치지 않게 마디 길이를 넘지 않는 크기로 만든다.
	# 겹쳐 두면 물리 엔진이 서로 밀어내며 사슬이 뻣뻣해지고 위로 들린다.
	capsule.radius = _builtin_rig.radius * 0.8
	capsule.height = length
	shape.shape = capsule
	physical.add_child(shape)
	if simulated:
		_physical_bones.append(physical)


## 꼬리 마디만 시뮬레이션한다. 앵커는 빠져 있으므로 스켈레톤을 그대로 따라간다.
func _start_simulation() -> void:
	var names := PackedStringArray()
	for physical in _physical_bones:
		names.append(String(physical.name))
	_simulator.physical_bones_start_simulation(names)


func _frame_update(_delta: float) -> void:
	var basis := Basis.from_euler(stimulus.euler)
	_custom_rig.transform = Transform3D(basis, stimulus.offset + Vector3(-SLOT_X, 0.0, 0.0))
	_builtin_rig.transform = Transform3D(basis, stimulus.offset + Vector3(SLOT_X, 0.0, 0.0))
	_custom_rig.visible = show_custom
	_builtin_rig.visible = show_builtin
	_custom_usec = lerpf(_custom_usec, float(_modifier.last_usec), 0.08)
	_physics_msec = lerpf(
		_physics_msec, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.08
	)
	_frame_msec = lerpf(
		_frame_msec, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.08
	)


func reset_demo() -> void:
	stimulus.reset()
	if _custom_rig == null:
		return
	for rig in [_custom_rig, _builtin_rig]:
		rig.transform = Transform3D.IDENTITY
		rig.reset_pose()
	_modifier.reset_simulation()
	if _simulator != null:
		# 래그돌은 "리셋"이 없다. 시뮬레이션을 껐다 켜는 것이 유일한 방법이다.
		_simulator.physical_bones_stop_simulation()
		_start_simulation()


func on_params_changed() -> void:
	stimulus.speed = stimulus_speed
	stimulus.amount = stimulus_amount
	var structure := Vector2(segments, segment_length)
	if not structure.is_equal_approx(_structure):
		_rebuild()
		return
	_apply_params()


func _apply_params() -> void:
	var chain := _modifier.chain
	chain.iterations = iterations
	chain.restore_stiffness = (
		JiggleSpring.params_from_frequency(restore_frequency, 1.0).x if restore_frequency > 0.0
		else 0.0
	)
	chain.drag = drag
	chain.angle_limit = deg_to_rad(angle_limit_degrees)
	_modifier.active = show_custom

	for physical in _physical_bones:
		physical.mass = bone_mass
		physical.angular_damp_mode = PhysicalBone3D.DAMP_MODE_REPLACE
		physical.angular_damp = angular_damp
		physical.gravity_scale = gravity_scale
		# 콘 조인트 파라미터도 동적 프로퍼티라 경로로 설정한다.
		physical.set("joint_constraints/swing_span", swing_span)
		physical.set("joint_constraints/twist_span", 5.0)
		# bias / relaxation 은 [b]Jolt에서 무시된다[/b](엔진이 경고를 낸다).
		# 물리 엔진을 바꾸면 조인트 파라미터의 일부가 조용히 사라진다는 뜻이다.
		# 자작 쪽에는 이런 엔진 의존성이 아예 없다.


func _draw_debug() -> void:
	if show_custom:
		debug.polyline(_modifier.reconstructed, Color(1.0, 0.65, 0.35, 0.7))
	if show_builtin:
		debug.polyline(_builtin_points(), Color(0.45, 0.75, 1.0, 0.7))


## 물리 본의 결과도 [JigglePoseReader3D] 를 거쳐야 읽을 수 있다.
func _builtin_points() -> PackedVector3Array:
	var points := PackedVector3Array()
	var skeleton := _builtin_rig.skeleton
	if _reader == null or _reader.world_positions.size() != skeleton.get_bone_count():
		return points
	for name in _builtin_rig.bone_names:
		var bone := skeleton.find_bone(name)
		if bone >= 0:
			points.append(_reader.world_positions[bone])
	return points


func sample_plot() -> Dictionary:
	if _modifier == null or _modifier.rest_points.size() < 2:
		return {}
	var last := _modifier.rest_points.size() - 2
	var rest := _modifier.rest_points[last]
	var custom_offset := 0.0
	if _modifier.reconstructed.size() > last:
		custom_offset = _modifier.reconstructed[last].distance_to(rest)
	var builtin_offset := 0.0
	var points := _builtin_points()
	if not points.is_empty():
		builtin_offset = points[points.size() - 1].distance_to(
			rest + Vector3(SLOT_X * 2.0, 0.0, 0.0)
		)
	return {"custom": custom_offset, "builtin": builtin_offset}


func get_plot_series() -> Array[Dictionary]:
	return [
		{"id": "custom", "color": Color(1.0, 0.62, 0.30)},
		{"id": "builtin", "color": Color(0.45, 0.75, 1.0)},
	]


func get_plot_info() -> String:
	return "끝 마디의 rest 대비 변위 m   |   자작 %.2fms   |   물리 프레임 %.2fms   |   전체 %.2fms" % [
		_custom_usec / 1000.0, _physics_msec, _frame_msec
	]


func get_demo_title() -> String:
	return "07 · 물리 본(래그돌) 비교"


func get_demo_description() -> String:
	return """[b]같은 꼬리, 한쪽은 Verlet 사슬, 한쪽은 진짜 강체 물리.[/b] [color=#ff8c5a]왼쪽(주황) = 자작[/color] · [color=#5aa8ff]오른쪽(파랑) = PhysicalBone3D 래그돌[/color].
오른쪽은 본 하나가 곧 [RigidBody3D] 다. 관절은 콘 조인트이고, 충돌 셰이프가 본마다 필요하며, 물리 월드의 다른 물체와 실제로 부딪힌다.
[b]조립 비용 비교[/b]  자작: 모디파이어 1개에 루트/끝 본 이름만. 래그돌: 본마다 [code]PhysicalBone3D[/code] + [code]CollisionShape3D[/code] + 조인트 설정, 게다가 [code]bone_name[/code] 을 [b]동적 속성으로 따로 넣어야[/b] 결합된다(노드 이름만으로는 안 된다).
[color=#ff8080]함정[/color]  [code]body_offset[/code] 을 "강체 중심을 마디 가운데로" 라며 (0, −L/2, 0) 로 두면 조인트까지 내려가 사슬이 [b]기대 길이의 80%로 쪼그라든다[/b](실측). 0으로 두는 것이 맞다.
[color=#8ab4ff]해볼 것[/color]  ① [b]스윙 각도[/b]와 [b]각속도 감쇠[/b]만으로 원하는 출렁임을 맞춰 보라. 자작의 "진동수 몇 Hz, 감쇠비 얼마"처럼 직관적인 손잡이가 없다.
② [b]질량[/b]을 바꿔 본다 → 관절의 반응이 통째로 달라진다. 래그돌은 파라미터가 서로 얽혀 있어 한 번에 하나씩 튜닝하기 어렵다.
③ [b]리셋(R)[/b] → 래그돌은 "되돌리기"가 없어서 시뮬레이션을 껐다 켜야 한다. 자작은 rest 위치를 그냥 대입하면 끝.
④ 비용: 래그돌은 [b]물리 프레임[/b] 예산을 쓴다. 캐릭터 하나에 가슴·엉덩이·머리카락까지 래그돌로 붙이면 강체 수십 개가 늘어난다.
[color=#ff8080]결론[/color]  래그돌이 이기는 경우는 [b]물리 월드와 진짜로 상호작용해야 할 때[/b](죽은 몸이 계단을 굴러 내려가는 것)뿐이다. 보이기용 흔들림은 스프링이나 Verlet이 훨씬 싸고 통제하기 쉽다."""


func get_param_labels() -> Dictionary:
	return {
		&"show_debug": "디버그 표시",
		&"segments": "마디 수 ⟲",
		&"segment_length": "마디 길이 ⟲",
		&"iterations": "제약 반복 횟수",
		&"restore_frequency": "복원 진동수 (Hz)",
		&"drag": "공기 저항",
		&"angle_limit_degrees": "각도 제한",
		&"swing_span": "콘 스윙 각도",
		&"bone_mass": "본 질량",
		&"angular_damp": "각속도 감쇠",
		&"gravity_scale": "중력 배율",
		&"stimulus_speed": "자극 속도",
		&"stimulus_amount": "자극 세기",
		&"show_custom": "자작 보기",
		&"show_builtin": "물리 본 보기",
	}


func get_presets() -> Dictionary:
	return {
		"기본": {
			&"iterations": 6,
			&"restore_frequency": 0.8,
			&"drag": 0.02,
			&"angle_limit_degrees": 40.0,
			&"swing_span": 30.0,
			&"bone_mass": 0.3,
			&"angular_damp": 2.0,
			&"gravity_scale": 1.0,
		},
		"흐물": {&"restore_frequency": 0.2, &"angle_limit_degrees": 70.0, &"swing_span": 60.0,
			&"angular_damp": 0.4},
		"뻣뻣": {&"restore_frequency": 2.6, &"angle_limit_degrees": 12.0, &"swing_span": 8.0,
			&"angular_damp": 8.0},
		"무겁게": {&"bone_mass": 3.0, &"angular_damp": 1.0, &"restore_frequency": 0.4},
	}


func get_camera_focus() -> Vector3:
	return Vector3(0.0, 0.95, 0.0)


func get_camera_distance() -> float:
	return 1.9


func smoke_check() -> String:
	if _physical_bones.size() != segments:
		return "물리 본 개수가 맞지 않는다 (%d / %d)" % [_physical_bones.size(), segments]
	for physical in _physical_bones:
		if physical.get_bone_id() < 0:
			return "%s 가 본과 결합되지 않았다 (노드 이름 확인)" % physical.name
	if show_custom and _modifier.reconstructed.is_empty():
		return "자작 모디파이어가 돌지 않았다"
	return ""
