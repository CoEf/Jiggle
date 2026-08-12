class_name JiggleBoneDemo
extends JiggleDemo

## 데모 02 — Jiggle Bone (가슴 · 엉덩이)
##
## 데모 01의 스프링 하나를 그대로 [b]본의 회전[/b]으로 바꾼 것이 전부다.
## 파티클은 여전히 "목표를 지연·오버슈트하며 따라가는" 일만 한다.
## 달라진 건 결과를 위치가 아니라 [b]방향[/b]으로 읽는다는 점뿐이다.
##
## 파란 반투명 몸이 "흔들림이 없었다면 있었을 자세"(고스트)다.
## 두 몸이 어긋나는 정도가 곧 Jiggle의 크기다.

const GROUND_COLOR := Color(0.10, 0.11, 0.13)

@export_group("스프링")
## 1초에 몇 번 출렁이는가. 작을수록 무겁고 크게 흔들린다.
@export_range(0.5, 8.0, 0.05) var frequency := 2.4
## 감쇠비. 0.15~0.3 이 살집 있는 느낌. 1.0이면 아예 출렁이지 않는다.
@export_range(0.02, 1.2, 0.01) var damping_ratio := 0.22
## 상하 강성 배율. 키우면 위아래로 덜 흔들린다.
@export_range(0.2, 3.0, 0.01) var vertical_ratio := 1.0
## 좌우/앞뒤 강성 배율. 낮추면 옆으로 잘 출렁인다.
@export_range(0.2, 3.0, 0.01) var horizontal_ratio := 0.7

@export_group("힘")
## 아래로 당기는 상수 가속도. 0이면 정지 상태에서 rest 그대로 뻣뻣하게 멈춘다.
@export_range(0.0, 12.0, 0.1) var gravity := 3.0
## 스켈레톤 이동을 얼마나 그대로 따라갈지. 1이면 흔들림이 사라진다.
@export_range(0.0, 1.0, 0.01) var motion_inherit := 0.0

@export_group("제한 · 연출")
## 최대 스윙 각도. [b]0이면 제한 없음[/b] — 큰 자극에서 어떻게 터지는지 볼 수 있다.
@export_range(0.0, 80.0, 1.0) var max_angle_degrees := 26.0
## 끄면 덩어리가 고무줄처럼 늘었다 줄었다 한다.
@export var keep_length := true
## 휜 만큼 축 방향으로 늘리는 연출.
@export_range(0.0, 1.0, 0.01) var squash := 0.25

@export_group("자극")
@export_range(0.1, 3.0, 0.05) var stimulus_speed := 1.0
@export_range(0.0, 2.5, 0.05) var stimulus_amount := 1.0

@export_group("보기")
## 흔들리지 않는 기준 자세를 반투명으로 겹쳐 보여 준다.
@export var show_ghost := true
## 정점 색으로 구운 Jiggle 본 가중치를 보여 준다. 빨강일수록 많이 흔들린다.
@export var show_weights := false
@export var jiggle_enabled := true

var _body: JiggleBody
var _ghost: JiggleBody
var _modifiers: Array[JiggleBoneModifier3D] = []
var _breast_index := 0
var _glute_index := 2


func _build() -> void:
	stimulus.kind = Stimulus.Kind.WALK

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(8.0, 8.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = GROUND_COLOR
	ground_material.roughness = 0.95
	ground.material_override = ground_material
	add_child(ground)

	# 고스트를 먼저 넣어 실제 몸이 위에 그려지도록 한다.
	_ghost = JiggleBody.new()
	add_child(_ghost)
	_ghost.build(true)

	_body = JiggleBody.new()
	add_child(_body)
	_body.build(false)

	# 모디파이어는 반드시 Skeleton3D 의 직속 자식이어야 한다.
	_modifiers.append(_add_modifier(JiggleBody.BREAST_L, JiggleBoneModifier3D.TipAxis.Z, 0.075))
	_modifiers.append(_add_modifier(JiggleBody.BREAST_R, JiggleBoneModifier3D.TipAxis.Z, 0.075))
	_modifiers.append(_add_modifier(JiggleBody.GLUTE_L, JiggleBoneModifier3D.TipAxis.NEG_Z, 0.080))
	_modifiers.append(_add_modifier(JiggleBody.GLUTE_R, JiggleBoneModifier3D.TipAxis.NEG_Z, 0.080))


func _add_modifier(
	bone_name: StringName, axis: JiggleBoneModifier3D.TipAxis, length: float
) -> JiggleBoneModifier3D:
	var modifier := JiggleBoneModifier3D.new()
	modifier.name = String(bone_name) + "Jiggle"
	modifier.bone_name = String(bone_name)
	modifier.tip_axis = axis
	modifier.tip_length = length
	_body.skeleton.add_child(modifier)
	return modifier


func _frame_update(_delta: float) -> void:
	# 자극은 캐릭터 [b]전체[/b]를 움직인다. 본을 직접 흔드는 게 아니다.
	# 흔들림은 그 이동을 파티클이 못 따라가면서 저절로 생긴다.
	var transform := Transform3D(Basis.from_euler(stimulus.euler), stimulus.offset)
	_body.transform = transform
	_ghost.transform = transform


func reset_demo() -> void:
	stimulus.reset()
	for modifier in _modifiers:
		modifier.reset_simulation()
	if _body != null:
		_body.reset_pose()
		_body.transform = Transform3D.IDENTITY
		_ghost.transform = Transform3D.IDENTITY


func on_params_changed() -> void:
	stimulus.speed = stimulus_speed
	stimulus.amount = stimulus_amount
	if _body == null:
		return
	_ghost.visible = show_ghost
	_body.set_weight_view(show_weights)
	for modifier in _modifiers:
		modifier.frequency = frequency
		modifier.damping_ratio = damping_ratio
		modifier.vertical_ratio = vertical_ratio
		modifier.horizontal_ratio = horizontal_ratio
		modifier.gravity = gravity
		modifier.motion_inherit = motion_inherit
		modifier.max_angle_degrees = max_angle_degrees
		modifier.keep_length = keep_length
		modifier.squash = squash
		modifier.active = jiggle_enabled
	if not jiggle_enabled:
		# 모디파이어를 끄면 마지막 포즈가 그대로 남는다. 직접 되돌려 줘야 한다.
		_body.reset_pose()


func _draw_debug() -> void:
	_draw_grid()
	for modifier in _modifiers:
		# 본 자체(원점 → 파티클). 이 선이 곧 회전 결과다.
		# 살색 몸 위에 겹치므로 반투명하게 두면 그대로 묻힌다.
		debug.line(modifier.bone_origin, modifier.particle_position, Color(1.0, 1.0, 1.0, 0.95))
		# 본 원점도 찍어 준다. 회전의 중심이 어디인지 보여야 스윙이 이해된다.
		debug.cross_mark(modifier.bone_origin, 0.018, Color(1.0, 1.0, 1.0, 0.95))
		debug.spring_gizmo(
			modifier.target_position,
			modifier.particle_position,
			modifier.particle_velocity,
			0.030,
			modifier.limit_radius
		)


func sample_plot() -> Dictionary:
	var breast := _modifiers[_breast_index]
	var glute := _modifiers[_glute_index]
	return {
		"breast": breast.particle_position.y - breast.target_position.y,
		"glute": glute.particle_position.y - glute.target_position.y,
	}


func get_plot_series() -> Array[Dictionary]:
	return [
		{"id": "breast", "color": Color(1.0, 0.45, 0.55)},
		{"id": "glute", "color": Color(0.55, 0.80, 1.0)},
	]


func get_plot_info() -> String:
	var angle := rad_to_deg(_modifiers[_breast_index].swing_angle) if not _modifiers.is_empty() else 0.0
	return "목표 대비 상하 변위   |   f = %.2f Hz   ζ = %.2f   |   현재 스윙 %.1f°" % [
		frequency, damping_ratio, angle
	]


func get_demo_title() -> String:
	return "02 · Jiggle Bone (가슴 / 엉덩이)"


func get_demo_description() -> String:
	return """[b]스프링 하나를 본 회전으로 바꾸면 그게 곧 가슴·엉덩이 Jiggle이다.[/b]
파티클은 월드 공간에 있고 목표는 스켈레톤을 따라 움직인다 → [b]관성이 공짜로 생긴다[/b]. 가속도를 재서 힘으로 바꾸는 코드는 없다.
[color=#26ff73]초록 구 = 목표(흔들림 없을 때의 끝점)[/color] · [color=#ffee26]노랑 = 파티클(실제 위치)[/color] · [color=#ff59e6]자홍 화살표 = 속도[/color] · [color=#ff4752]빨간 구 = 최대 각도 울타리[/color] · 흰 선 = 본 원점 → 파티클(이 방향이 곧 회전 결과).
[color=#8ab4ff]해볼 것[/color]  ① [b]웨이트 보기[/b]를 켜서 어느 정점이 어느 본에 얼마나 묶였는지 확인 → 빨간 부분만 흔들린다. 뿌리의 전이 구간이 없으면 표면이 꺾인다.
② [b]최대 각도[/b]를 0(제한 없음)으로 두고 자극을 '급정거'로 바꾸면 본이 뒤집히며 메쉬가 터진다. 클램프가 왜 필수인지 보여 주는 장면.
③ [b]좌우 강성[/b]만 0.3으로 내리면 옆으로만 출렁인다 — 비등방 스프링. 실제 연부 조직과 완벽한 구슬을 가르는 차이.
④ [b]중력[/b]을 0으로 하면 정지 상태에서 rest에 딱 붙어 뻣뻣해진다. 중력에 의한 처짐이 자연스러움의 절반이다.
⑤ [b]이동 상속[/b]을 1로 올리면 흔들림이 완전히 사라진다. 이 값이 "관성을 얼마나 허용할지"의 손잡이다."""


func get_param_labels() -> Dictionary:
	return {
		&"show_debug": "디버그 표시",
		&"frequency": "진동수 (Hz)",
		&"damping_ratio": "감쇠비 ζ",
		&"vertical_ratio": "상하 강성 배율",
		&"horizontal_ratio": "좌우 강성 배율",
		&"gravity": "중력 (처짐)",
		&"motion_inherit": "이동 상속 (0=관성최대)",
		&"max_angle_degrees": "최대 각도 (0=무제한)",
		&"keep_length": "길이 유지",
		&"squash": "스쿼시 & 스트레치",
		&"stimulus_speed": "자극 속도",
		&"stimulus_amount": "자극 세기",
		&"show_ghost": "고스트(기준 자세)",
		&"show_weights": "웨이트 보기",
		&"jiggle_enabled": "Jiggle 켜기",
	}


func get_presets() -> Dictionary:
	return {
		"기본": {
			&"frequency": 2.4,
			&"damping_ratio": 0.22,
			&"vertical_ratio": 1.0,
			&"horizontal_ratio": 0.7,
			&"gravity": 3.0,
			&"motion_inherit": 0.0,
			&"max_angle_degrees": 26.0,
			&"keep_length": true,
			&"squash": 0.25,
		},
		"글래머": {
			&"frequency": 1.5,
			&"damping_ratio": 0.13,
			&"horizontal_ratio": 0.5,
			&"gravity": 5.0,
			&"max_angle_degrees": 40.0,
			&"squash": 0.4,
		},
		"탄탄": {
			&"frequency": 4.6,
			&"damping_ratio": 0.45,
			&"horizontal_ratio": 1.0,
			&"gravity": 1.2,
			&"max_angle_degrees": 14.0,
			&"squash": 0.12,
		},
		"물풍선": {
			&"frequency": 1.0,
			&"damping_ratio": 0.05,
			&"horizontal_ratio": 0.35,
			&"gravity": 6.0,
			&"max_angle_degrees": 55.0,
			&"keep_length": false,
			&"squash": 0.7,
		},
		"터뜨리기": {
			&"frequency": 1.2,
			&"damping_ratio": 0.04,
			&"max_angle_degrees": 0.0,
			&"keep_length": false,
			&"stimulus_amount": 2.5,
		},
	}


func get_unstable_presets() -> PackedStringArray:
	# 이 프리셋은 "각도 제한을 끄면 본이 뒤집힌다"를 보여 주는 것이 목적이다.
	return PackedStringArray(["터뜨리기"])


func smoke_check() -> String:
	for modifier in _modifiers:
		if modifier.target_position.is_equal_approx(Vector3.ZERO):
			return "%s: 모디파이어 콜백이 돌지 않았다 (Skeleton3D 직속 자식인지 확인)" % modifier.name
		if modifier.swing_angle > deg_to_rad(179.0):
			return "%s: 스윙 각도가 뒤집혔다 (%.1f°)" % [
				modifier.name, rad_to_deg(modifier.swing_angle)
			]
	return ""


func get_camera_focus() -> Vector3:
	return Vector3(0.0, 1.05, 0.0)


func get_camera_distance() -> float:
	return 1.9


func _draw_grid() -> void:
	var color := Color(1.0, 1.0, 1.0, 0.05)
	for i in range(-8, 9):
		var t := float(i) * 0.25
		debug.line(Vector3(t, 0.001, -2.0), Vector3(t, 0.001, 2.0), color)
		debug.line(Vector3(-2.0, 0.001, t), Vector3(2.0, 0.001, t), color)
