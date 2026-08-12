class_name ShaderJiggleDemo
extends JiggleDemo

## 데모 08 — 본 없이 흔들기: 정점 셰이더
##
## 왼쪽은 데모 02와 같은 [b]본 기반[/b] Jiggle, 오른쪽은 [b]스켈레톤을 아예 안 쓰고[/b]
## 정점 셰이더로 표면만 미는 방식이다. 오른쪽 몸은 스킨이 떼어져 있어 본이 움직여도 변형되지 않는다.
##
## [color=#ff8c5a]주황 마커 = 본 기반[/color] · [color=#5aa8ff]파랑 마커 = 셰이더[/color]
##
## 두 마커가 이 데모의 핵심이다. 마커는 [BoneAttachment3D] 로 가슴 본에 붙어 있다.
## 왼쪽 마커는 흔들림을 따라 움직이지만 [b]오른쪽 마커는 꿈쩍도 하지 않는다[/b] —
## 셰이더는 화면에 그려지는 정점만 밀 뿐, 씬의 어떤 것도 실제로 움직이지 않기 때문이다.

const GROUND_COLOR := Color(0.10, 0.11, 0.13)
const SLOT_X := 0.34
const MARKER_RADIUS := 0.022

## 정점 셰이더 흔들림.
##
## [code]COLOR.a[/code] 에 [JiggleBody] 가 구워 둔 Jiggle 가중치가 들어 있다.
## 가중치가 0인 곳은 전혀 안 움직이고, 1인 곳은 오프셋을 그대로 받는다.
const JIGGLE_SHADER := """
shader_type spatial;

uniform vec3 skin_color : source_color = vec3(0.84, 0.66, 0.58);
uniform vec3 jiggle_offset = vec3(0.0);
uniform float wobble_amplitude = 0.0;
uniform float wobble_frequency = 2.0;
uniform float weight_view = 0.0;

void vertex() {
	float weight = COLOR.a;

	// ① 유니폼 구동: CPU가 스프링 하나로 만든 오프셋을 가중치만큼 분배한다.
	//    본은 하나도 안 쓰지만 몸의 움직임에는 제대로 반응한다.
	vec3 offset = jiggle_offset * weight;

	// ② 시간 기반: 정점 위치로 위상을 흩어 파도를 만든다.
	//    상태가 전혀 없어서 가장 싸지만, 몸이 무엇을 하든 똑같이 출렁인다.
	float phase = VERTEX.x * 9.0 + VERTEX.y * 6.0 + VERTEX.z * 4.0;
	offset += vec3(
		sin(TIME * wobble_frequency + phase),
		sin(TIME * wobble_frequency * 1.3 + phase * 1.7),
		cos(TIME * wobble_frequency * 0.8 + phase)
	) * wobble_amplitude * weight;

	VERTEX += offset;
}

void fragment() {
	ALBEDO = mix(skin_color, COLOR.rgb, weight_view);
	ROUGHNESS = 0.55;
}
"""

@export_group("본 기반 (왼쪽)")
@export_range(0.5, 8.0, 0.05) var frequency := 2.4
@export_range(0.02, 1.2, 0.01) var damping_ratio := 0.22
@export_range(0.0, 12.0, 0.1) var gravity := 3.0
@export_range(0.0, 80.0, 1.0) var max_angle_degrees := 26.0

@export_group("셰이더 (오른쪽)")
## CPU 스프링 하나가 만든 오프셋을 정점 가중치만큼 분배한다. 몸의 움직임에 반응한다.
@export_range(0.0, 3.0, 0.05) var uniform_gain := 1.0
## 시간만으로 만드는 출렁임. 상태가 없어서 가장 싸지만 몸이 뭘 하든 똑같이 움직인다.
@export_range(0.0, 0.06, 0.002) var wobble_amplitude := 0.0
@export_range(0.2, 8.0, 0.1) var wobble_frequency := 2.0

@export_group("자극")
@export_range(0.1, 3.0, 0.05) var stimulus_speed := 1.0
@export_range(0.0, 2.5, 0.05) var stimulus_amount := 1.0

@export_group("보기")
## 정점 색으로 구운 Jiggle 가중치를 보여 준다. 셰이더가 읽는 값이 바로 이것이다.
@export var show_weights := false
## 본에 붙은 마커. 셰이더 쪽이 왜 "화면만 속이는" 것인지 보여 준다.
@export var show_markers := true

var _bone_body: JiggleBody
var _shader_body: JiggleBody
var _modifiers: Array[JiggleBoneModifier3D] = []
var _material := ShaderMaterial.new()
var _spring := JiggleSpring.new()
var _bone_marker: BoneAttachment3D
var _shader_marker: BoneAttachment3D
var _anchor_local := Vector3.ZERO
var _initialized := false


func _build() -> void:
	stimulus.kind = Stimulus.Kind.WALK

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

	# --- 왼쪽: 데모 02와 같은 본 기반 ---
	_bone_body = JiggleBody.new()
	_bone_body.name = "BoneBody"
	add_child(_bone_body)
	_bone_body.build(false)
	_add_modifier(JiggleBody.BREAST_L, JiggleBoneModifier3D.TipAxis.Z, 0.075)
	_add_modifier(JiggleBody.BREAST_R, JiggleBoneModifier3D.TipAxis.Z, 0.075)
	_add_modifier(JiggleBody.GLUTE_L, JiggleBoneModifier3D.TipAxis.NEG_Z, 0.080)
	_add_modifier(JiggleBody.GLUTE_R, JiggleBoneModifier3D.TipAxis.NEG_Z, 0.080)

	# --- 오른쪽: 스킨을 떼고 셰이더만 ---
	_shader_body = JiggleBody.new()
	_shader_body.name = "ShaderBody"
	add_child(_shader_body)
	_shader_body.build(false)
	_shader_body.detach_skin()

	var shader := Shader.new()
	shader.code = JIGGLE_SHADER
	_material.shader = shader
	_material.set_shader_parameter("skin_color", JiggleBody.SKIN_COLOR)
	_shader_body.mesh_instance.material_override = _material

	# 가슴 본에 붙인 마커. 왼쪽은 따라 움직이고 오른쪽은 가만히 있는다.
	_bone_marker = _add_marker(_bone_body, Color(1.0, 0.55, 0.25))
	_shader_marker = _add_marker(_shader_body, Color(0.35, 0.65, 1.0))

	# 셰이더를 구동할 스프링 하나. 가슴 본 위치를 기준점으로 쓴다.
	_anchor_local = _bone_body.bone_rest_position(_bone_body.bone(JiggleBody.BREAST_L))


func _add_modifier(
	bone_name: StringName, axis: JiggleBoneModifier3D.TipAxis, length: float
) -> void:
	var modifier := JiggleBoneModifier3D.new()
	modifier.name = String(bone_name) + "Jiggle"
	modifier.bone_name = String(bone_name)
	modifier.tip_axis = axis
	modifier.tip_length = length
	_bone_body.skeleton.add_child(modifier)
	_modifiers.append(modifier)


## 가슴 본에 붙는 작은 구. [BoneAttachment3D] 는 모디파이어 [b]결과[/b]를 따라간다.
func _add_marker(body: JiggleBody, color: Color) -> BoneAttachment3D:
	var attachment := BoneAttachment3D.new()
	attachment.name = "Marker"
	attachment.bone_name = String(JiggleBody.BREAST_L)
	body.skeleton.add_child(attachment)

	var marker := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = MARKER_RADIUS
	sphere.height = MARKER_RADIUS * 2.0
	marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	marker.material_override = material
	# 가슴 덩어리 앞쪽으로 조금 내밀어 눈에 띄게 한다.
	marker.position = Vector3(0.0, 0.0, 0.13)
	attachment.add_child(marker)
	return attachment


func _frame_update(delta: float) -> void:
	var basis := Basis.from_euler(stimulus.euler)
	var transform := Transform3D(basis, stimulus.offset)
	_bone_body.transform = Transform3D(basis, stimulus.offset + Vector3(-SLOT_X, 0.0, 0.0))
	_shader_body.transform = Transform3D(basis, stimulus.offset + Vector3(SLOT_X, 0.0, 0.0))
	_bone_marker.visible = show_markers
	_shader_marker.visible = show_markers

	# CPU 스프링 하나로 "몸이 움직여서 생기는 관성"을 만든다.
	# 데모 02와 완전히 같은 원리인데, 결과를 본 회전이 아니라 셰이더 유니폼으로 보낸다.
	var target := _shader_body.global_transform * _anchor_local
	if not _initialized:
		_spring.reset_to(target)
		_initialized = true
	var kc := JiggleSpring.params_from_frequency(frequency, damping_ratio)
	_spring.stiffness = Vector3.ONE * kc.x
	_spring.damping = Vector3.ONE * kc.y
	_spring.gravity = Vector3.DOWN * gravity
	_spring.max_distance = 0.12
	_spring.step(delta, target)

	# 월드 오프셋을 모델 공간으로 되돌린다. 셰이더의 VERTEX 는 모델 공간이기 때문.
	var world_offset := (_spring.position - target) * uniform_gain
	var local_offset := _shader_body.global_transform.basis.inverse() * world_offset
	_material.set_shader_parameter("jiggle_offset", local_offset)
	_material.set_shader_parameter("wobble_amplitude", wobble_amplitude)
	_material.set_shader_parameter("wobble_frequency", wobble_frequency)
	_material.set_shader_parameter("weight_view", 1.0 if show_weights else 0.0)


func reset_demo() -> void:
	stimulus.reset()
	_initialized = false
	if _bone_body == null:
		return
	for body in [_bone_body, _shader_body]:
		body.transform = Transform3D.IDENTITY
		body.reset_pose()
	for modifier in _modifiers:
		modifier.reset_simulation()


func on_params_changed() -> void:
	stimulus.speed = stimulus_speed
	stimulus.amount = stimulus_amount
	if _bone_body == null:
		return
	_bone_body.set_weight_view(show_weights)
	for modifier in _modifiers:
		modifier.frequency = frequency
		modifier.damping_ratio = damping_ratio
		modifier.gravity = gravity
		modifier.max_angle_degrees = max_angle_degrees


func _draw_debug() -> void:
	if not show_markers:
		return
	# 마커의 rest 위치. 여기서 얼마나 벗어났는지가 곧 "실제로 움직였는가"다.
	for body in [_bone_body, _shader_body]:
		var rest: Vector3 = body.global_transform * (_anchor_local + Vector3(0.0, 0.0, 0.13))
		debug.sphere(rest, MARKER_RADIUS * 1.4, JiggleDebugDraw.COLOR_TARGET, 12)


func sample_plot() -> Dictionary:
	if _bone_marker == null:
		return {}
	var bone_rest: Vector3 = (
		_bone_body.global_transform * (_anchor_local + Vector3(0.0, 0.0, 0.13))
	)
	var shader_rest: Vector3 = (
		_shader_body.global_transform * (_anchor_local + Vector3(0.0, 0.0, 0.13))
	)
	return {
		"bone": _bone_marker.global_position.distance_to(bone_rest),
		"shader": _shader_marker.global_position.distance_to(shader_rest),
	}


func get_plot_series() -> Array[Dictionary]:
	return [
		{"id": "bone", "color": Color(1.0, 0.62, 0.30)},
		{"id": "shader", "color": Color(0.45, 0.75, 1.0)},
	]


func get_plot_info() -> String:
	return "본에 붙은 마커가 rest에서 벗어난 거리 m   |   셰이더 쪽은 언제나 0 이다"


func get_demo_title() -> String:
	return "08 · 정점 셰이더 흔들림"


func get_demo_description() -> String:
	return """[b]본을 하나도 안 쓰고 흔드는 법.[/b] [color=#ff8c5a]왼쪽 = 데모 02의 본 기반[/color] · [color=#5aa8ff]오른쪽 = 스킨을 떼고 정점 셰이더만[/color].
셰이더는 [JiggleBody]가 정점 색 [b]알파[/b]에 구워 둔 Jiggle 가중치를 읽어, 가중치만큼만 정점을 민다. 방식은 두 가지다 — [b]유니폼 구동[/b](CPU 스프링 1개가 만든 오프셋을 분배, 몸의 움직임에 반응)과 [b]시간 기반[/b](sin 파, 상태가 없어 가장 싸지만 몸이 뭘 하든 똑같이 출렁임).
[color=#8ab4ff]해볼 것[/color]  ① [b]마커[/b]를 보라. 둘 다 가슴 본에 붙은 [code]BoneAttachment3D[/code] 인데 [b]왼쪽만 움직인다[/b]. 그래프의 파란 선은 영원히 0이다.
② [b]웨이트 보기[/b]를 켜면 셰이더가 읽는 값(정점 색 알파)이 그대로 보인다.
③ [b]시간 기반 진폭[/b]만 올리고 자극을 [b]정지[/b]로 → 몸이 가만히 있는데도 계속 출렁인다. 싸지만 거짓말이다.
[color=#ff8080]한계[/color]  충돌 불가 · 씬의 어떤 것도 실제로 안 움직임(장신구·머리카락이 안 따라옴) · CPU에서 결과를 읽을 수 없음 · 그림자와 실루엣은 흔들리지만 물리적으로는 그 자리에 그대로 있음.
[color=#8ab4ff]그래서 언제 쓰나[/color]  군중 속 먼 캐릭터, 배경의 풀·깃발, 장비를 붙일 일이 없는 부위. [b]본이 감당 못 할 만큼 개수가 많을 때[/b] 쓰는 기법이다."""


func get_param_labels() -> Dictionary:
	return {
		&"show_debug": "디버그 표시",
		&"frequency": "진동수 (Hz)",
		&"damping_ratio": "감쇠비 ζ",
		&"gravity": "중력 (처짐)",
		&"max_angle_degrees": "최대 각도 (본 기반)",
		&"uniform_gain": "유니폼 구동 세기",
		&"wobble_amplitude": "시간 기반 진폭",
		&"wobble_frequency": "시간 기반 주파수",
		&"stimulus_speed": "자극 속도",
		&"stimulus_amount": "자극 세기",
		&"show_weights": "웨이트 보기",
		&"show_markers": "마커 보기",
	}


func get_presets() -> Dictionary:
	return {
		"기본": {
			&"frequency": 2.4,
			&"damping_ratio": 0.22,
			&"gravity": 3.0,
			&"uniform_gain": 1.0,
			&"wobble_amplitude": 0.0,
		},
		"시간 기반만": {&"uniform_gain": 0.0, &"wobble_amplitude": 0.03, &"wobble_frequency": 2.4},
		"둘 다": {&"uniform_gain": 1.0, &"wobble_amplitude": 0.014},
		"과장": {&"frequency": 1.4, &"damping_ratio": 0.1, &"uniform_gain": 2.2, &"gravity": 5.0},
	}


func get_camera_focus() -> Vector3:
	return Vector3(0.0, 1.05, 0.0)


func get_camera_distance() -> float:
	return 2.2


func smoke_check() -> String:
	if _shader_body.mesh_instance.skin != null:
		return "셰이더 쪽 몸의 스킨이 떨어지지 않았다"
	for modifier in _modifiers:
		if modifier.target_position.is_equal_approx(Vector3.ZERO):
			return "%s: 본 모디파이어가 돌지 않았다" % modifier.name
	return ""
