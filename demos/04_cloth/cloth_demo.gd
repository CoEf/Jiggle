class_name ClothDemo
extends JiggleDemo

## 데모 04 — 천 Verlet (치마 · 커튼)
##
## 데모 03의 사슬을 [b]격자[/b]로 넓힌 것이 전부다. 솔버는 [JiggleVerletBody] 로 완전히 동일하고,
## 제약만 세 종류로 늘어난다.
##
## [b]본이 없다는 점[/b]도 중요하다. 사슬은 결과를 본 회전으로 읽었지만,
## 천은 파티클 위치가 곧 메쉬 정점이다. 스키닝 단계가 아예 없고,
## 대신 매 프레임 [ArrayMesh] 를 다시 굽는다.

const GROUND_COLOR := Color(0.10, 0.11, 0.13)
const COLOR_CONTACT := Color(1.0, 0.25, 0.35)
const COLOR_STRUCTURAL := Color(1.0, 1.0, 1.0, 0.45)
const COLOR_SHEAR := Color(0.35, 0.75, 1.0, 0.40)
const COLOR_BEND := Color(1.0, 0.65, 0.25, 0.30)
const WIND_DIRECTION := Vector3(0.30, 0.10, 1.0)

## 천은 양면이 다 보인다. 컬링을 끄면 뒷면도 [b]앞면과 같은 법선[/b]으로 그려져
## 새까맣게 나오므로, 뒷면일 때 법선을 뒤집어 준다.
## [StandardMaterial3D] 로는 못 하는 유일한 부분이라 셰이더를 직접 쓴다.
const CLOTH_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 cloth_color : source_color = vec3(0.72, 0.30, 0.38);
uniform float cloth_roughness : hint_range(0.0, 1.0) = 0.75;

void fragment() {
	ALBEDO = cloth_color;
	ROUGHNESS = cloth_roughness;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}
"""

@export_group("천 구조")
## 바꾸면 천을 다시 만든다.
@export_enum("치마 (원통):0", "커튼 (평면):1") var shape: int = 0
@export_range(6, 32, 1) var columns := 16
@export_range(4, 24, 1) var rows := 11
## 커튼일 때만 의미가 있다. 모서리만 고정하면 전단 제약의 효과가 극적으로 보인다.
@export_enum("윗변 전체:0", "양쪽 위 모서리만:1") var pin_mode: int = 0

@export_group("제약")
## 제약 반복 횟수. 천의 뻣뻣함을 정하는 가장 중요한 값.
@export_range(1, 16, 1) var iterations := 6
## 가로세로 이웃. 천이 늘어나는 것을 막는다.
@export_range(0.1, 1.0, 0.01) var structural_stiffness := 1.0
## 대각선 이웃. 정사각형이 마름모로 무너지는 것을 막는다.
@export var shear_enabled := true
@export_range(0.0, 1.0, 0.01) var shear_stiffness := 0.7
## 한 칸 건너뛴 이웃. 종이처럼 접히는 것을 막는다.
@export var bend_enabled := true
@export_range(0.0, 1.0, 0.01) var bend_stiffness := 0.3

@export_group("힘")
@export_range(0.0, 20.0, 0.5) var gravity := 9.0
@export_range(0.0, 0.15, 0.005) var drag := 0.02
## 표면이 정면으로 맞을수록 세게 미는 바람. 0이면 없음.
@export_range(0.0, 40.0, 0.5) var wind := 0.0
@export_range(0.2, 4.0, 0.1) var wind_gust := 1.0

@export_group("충돌")
@export var collision_enabled := true
@export_enum("① 위치만 밀기 (폭주):0", "② 속도 보존 (표면에서 튐):1", "③ 접촉 안정화 (권장):2")
var collision_response: int = 2
@export_range(0.0, 1.0, 0.02) var collision_friction := 0.3

@export_group("자극")
@export_range(0.1, 3.0, 0.05) var stimulus_speed := 1.0
@export_range(0.0, 2.5, 0.05) var stimulus_amount := 1.0
## 다리를 앞뒤로 흔드는 각도. 치마를 안쪽에서 밀어낸다.
@export_range(0.0, 1.0, 0.02) var leg_swing := 0.45

@export_group("보기")
## 제약을 색으로 구분해 그린다. 흰=구조 · 파랑=전단 · 주황=굽힘.
@export var show_constraints := false
@export var show_particles := false
@export var show_colliders := true

var _cloth := JiggleVerletCloth.new()
var _mesh := ArrayMesh.new()
var _mesh_instance: MeshInstance3D
var _body: ClothMannequin
var _material := ShaderMaterial.new()

var _rest_local := PackedVector3Array()
var _pinned := PackedInt32Array()
var _structure := Vector4.ZERO
var _no_colliders: Array[JiggleVerletBody.Collider] = []
var _wind_time := 0.0
var _sim_usec := 0.0
var _mesh_usec := 0.0


func _build() -> void:
	stimulus.kind = Stimulus.Kind.WALK
	# 천은 파티클이 많아 120Hz 서브스텝이 비싸다. 60Hz로도 충분히 안정적이다.
	set_substep_hz(60.0)

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

	_body = ClothMannequin.new()
	_body.name = "Mannequin"
	add_child(_body)
	_body.build()

	var shader := Shader.new()
	shader.code = CLOTH_SHADER
	_material.shader = shader
	_material.set_shader_parameter("cloth_color", Color(0.66, 0.24, 0.31))
	_material.set_shader_parameter("cloth_roughness", 0.72)

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Cloth"
	_mesh_instance.mesh = _mesh
	_mesh_instance.material_override = _material
	# 파티클 좌표가 곧 월드 좌표다. 노드는 반드시 원점에 있어야 한다.
	_mesh_instance.custom_aabb = AABB(Vector3(-3.0, -1.0, -3.0), Vector3(6.0, 5.0, 6.0))
	add_child(_mesh_instance)

	_rebuild_cloth()


## 구조 파라미터가 바뀌면 격자를 통째로 다시 만든다.
func _rebuild_cloth() -> void:
	var points := PackedVector3Array()
	var wrap := shape == 0
	_pinned = PackedInt32Array()

	if wrap:
		_build_skirt(points)
	else:
		_build_curtain(points)

	_rest_local = points.duplicate()
	_cloth.build(points, columns, rows, wrap)
	for index in _pinned:
		_cloth.pin(index)

	_body.visible = wrap
	_structure = Vector4(shape, columns, rows, pin_mode)
	_apply_simulation_params()
	_update_mesh()


## 치마: 허리에서 밑단으로 갈수록 넓어지는 원통.
##
## 허리 반지름은 [b]골반 충돌체 바깥[/b]에 오도록 잡았다.
## rest 자세가 충돌체 안에 파묻히면 복원력과 충돌이 영원히 싸운다(데모 03 참고).
func _build_skirt(points: PackedVector3Array) -> void:
	var waist_y := 0.97
	var hem_y := 0.50
	var waist_radius := 0.180
	var hem_radius := 0.300
	for row in rows + 1:
		var t := float(row) / float(rows)
		var y := lerpf(waist_y, hem_y, t)
		var radius := lerpf(waist_radius, hem_radius, t)
		for column in columns:
			var angle := TAU * float(column) / float(columns)
			points.append(Vector3(cos(angle) * radius, y, sin(angle) * radius))
			if row == 0:
				_pinned.append(points.size() - 1)


## 커튼: 평면 격자. 제약 종류별 차이를 보기에는 이쪽이 훨씬 선명하다.
func _build_curtain(points: PackedVector3Array) -> void:
	var width := 0.85
	var height := 0.72
	var top := 1.18
	for row in rows + 1:
		for column in columns + 1:
			var x := (float(column) / float(columns) - 0.5) * width
			var y := top - float(row) / float(rows) * height
			points.append(Vector3(x, y, 0.0))
			if row != 0:
				continue
			# 윗변 전체를 고정하면 커튼, 모서리만 고정하면 늘어진 천이 된다.
			if pin_mode == 0 or column == 0 or column == columns:
				_pinned.append(points.size() - 1)


func _frame_update(delta: float) -> void:
	_wind_time += delta * wind_gust
	var transform := Transform3D(Basis.from_euler(stimulus.euler), stimulus.offset)
	_body.transform = transform
	_body.set_leg_swing(sin(stimulus.cycle * PI) * leg_swing)
	_body.refresh_colliders()

	# rest 위치와 고정점을 몸에 맞춰 옮긴다.
	# 고정점은 시뮬레이션이 아니라 애니메이션이 위치를 정하는 지점이다.
	var rest := PackedVector3Array()
	rest.resize(_rest_local.size())
	for i in _rest_local.size():
		rest[i] = transform * _rest_local[i]
	_cloth.set_rest(rest)
	for index in _pinned:
		_cloth.move_pinned(index, rest[index])

	# 돌풍. 세기만 흔들어 줘도 펄럭임이 훨씬 살아난다.
	var gust := 0.55 + 0.45 * sin(_wind_time * 1.7) * sin(_wind_time * 0.53 + 1.1)
	_cloth.apply_wind(WIND_DIRECTION.normalized(), wind * gust)


func _simulate(delta: float) -> void:
	var start := Time.get_ticks_usec()
	_cloth.step(delta)
	_sim_usec = lerpf(_sim_usec, float(Time.get_ticks_usec() - start), 0.08)


func _post_simulate(_delta: float) -> void:
	_update_mesh()


## 매 프레임 ArrayMesh 를 다시 굽는다.
##
## 인덱스와 UV는 안 변하므로 미리 만들어 두고 정점·법선만 갱신한다.
## 그래도 [method ArrayMesh.add_surface_from_arrays] 는 배열을 복사하므로 공짜가 아니다.
## 오른쪽 아래 그래프에 실제 비용(ms)이 찍힌다.
func _update_mesh() -> void:
	var start := Time.get_ticks_usec()
	_cloth.update_normals()
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _cloth.mesh_arrays())
	_mesh_usec = lerpf(_mesh_usec, float(Time.get_ticks_usec() - start), 0.08)


func reset_demo() -> void:
	stimulus.reset()
	_wind_time = 0.0
	if _body == null:
		return
	_body.transform = Transform3D.IDENTITY
	_body.set_leg_swing(0.0)
	_body.refresh_colliders()
	_cloth.reset_to(_rest_local)
	_update_mesh()


func on_params_changed() -> void:
	stimulus.speed = stimulus_speed
	stimulus.amount = stimulus_amount
	var structure := Vector4(shape, columns, rows, pin_mode)
	if not structure.is_equal_approx(_structure):
		_rebuild_cloth()
		return
	_apply_simulation_params()


func _apply_simulation_params() -> void:
	_cloth.iterations = iterations
	_cloth.structural_stiffness = structural_stiffness
	_cloth.shear_enabled = shear_enabled
	_cloth.shear_stiffness = shear_stiffness
	_cloth.bend_enabled = bend_enabled
	_cloth.bend_stiffness = bend_stiffness
	_cloth.gravity = Vector3.DOWN * gravity
	_cloth.drag = drag
	_cloth.collision_response = collision_response as JiggleVerletBody.CollisionResponse
	_cloth.collision_friction = collision_friction
	var use_colliders := collision_enabled and shape == 0
	_cloth.colliders = _body.colliders if use_colliders else _no_colliders


func _draw_debug() -> void:
	if show_colliders and shape == 0:
		for collider in _cloth.colliders:
			debug.capsule(
				collider.point_a, collider.point_b, collider.radius, Color(0.35, 0.75, 1.0, 0.22)
			)
	if show_constraints:
		_draw_pairs(_cloth.structural_pairs(), COLOR_STRUCTURAL)
		if shear_enabled:
			_draw_pairs(_cloth.shear_pairs(), COLOR_SHEAR)
		if bend_enabled:
			_draw_pairs(_cloth.bend_pairs(), COLOR_BEND)
	if not show_particles:
		return
	for i in _cloth.positions.size():
		if _cloth.contact_normals[i].length_squared() > 0.000001:
			debug.sphere(_cloth.positions[i], 0.014, COLOR_CONTACT, 8)
		elif _cloth.inverse_mass[i] <= 0.0:
			debug.cross_mark(_cloth.positions[i], 0.014, JiggleDebugDraw.COLOR_TARGET)
		else:
			debug.cross_mark(_cloth.positions[i], 0.008, JiggleDebugDraw.COLOR_ACTUAL)


func _draw_pairs(pairs: PackedInt32Array, color: Color) -> void:
	for k in pairs.size() / 2:
		debug.line(_cloth.positions[pairs[k * 2]], _cloth.positions[pairs[k * 2 + 1]], color)


func sample_plot() -> Dictionary:
	return {
		"stretch": _cloth.average_stretch() * 1000.0,
		"cost": (_sim_usec + _mesh_usec) / 1000.0,
	}


func get_plot_series() -> Array[Dictionary]:
	return [
		{"id": "stretch", "color": Color(0.45, 0.95, 0.60)},
		{"id": "cost", "color": Color(1.0, 0.70, 0.35)},
	]


func get_plot_info() -> String:
	return "입자 %d · 제약 %d   |   늘어남 %.2fmm   |   시뮬 %.2fms + 메쉬 %.2fms" % [
		_cloth.positions.size(),
		_cloth.constraint_count(),
		_cloth.average_stretch() * 1000.0,
		_sim_usec / 1000.0,
		_mesh_usec / 1000.0,
	]


func get_demo_title() -> String:
	return "04 · 천 Verlet (치마 / 커튼)"


func get_demo_description() -> String:
	return """[b]천은 사슬을 격자로 넓힌 것이다.[/b] 솔버는 데모 03과 [b]완전히 같고[/b], 제약만 세 종류로 늘어난다 — [color=#ffffff]구조(가로세로)[/color] · [color=#59bfff]전단(대각선)[/color] · [color=#ffa640]굽힘(한 칸 건너)[/color]. 셋 다 똑같은 거리 제약이고, 누구와 누구를 잇느냐만 다르다.
본이 없다는 점도 다르다. [b]파티클 위치가 곧 메쉬 정점[/b]이라 스키닝 단계가 없고, 대신 매 프레임 ArrayMesh를 다시 굽는다(비용이 그래프에 찍힌다).
[color=#8ab4ff]해볼 것[/color]  ① [b]커튼[/b] + [b]양쪽 위 모서리만[/b] 고정 → [b]전단[/b]을 끈다. 천이 정사각형을 유지하지 못하고 마름모로 주저앉는다. 다시 켜면 즉시 복구된다.
② 같은 상태에서 [b]굽힘[/b]을 끈다 → 접힌 자국이 칼처럼 날카로워진다. 켜면 종이가 아니라 두꺼운 천처럼 완만해진다.
③ [b]바람[/b]을 20까지 올린다 → 표면이 정면으로 맞을수록 세게 밀리므로 펄럭인다. 법선을 안 쓰면 그냥 밀리기만 한다.
④ [b]치마[/b] + 자극 [b]걷기[/b] → 다리가 안쪽에서 치마를 밀어낸다. 빨간 구가 지금 닿아 있는 입자다.
⑤ [b]가로 칸수[/b]를 32로 올린다 → 주황 그래프(프레임 비용)가 어떻게 뛰는지 본다. 제약 수는 칸수의 제곱으로 늘어난다."""


func get_param_labels() -> Dictionary:
	return {
		&"show_debug": "디버그 표시",
		&"shape": "모양 ⟲",
		&"columns": "가로 칸수 ⟲",
		&"rows": "세로 칸수 ⟲",
		&"pin_mode": "고정 방식 ⟲ (커튼)",
		&"iterations": "제약 반복 횟수",
		&"structural_stiffness": "구조 제약 강도",
		&"shear_enabled": "전단 제약",
		&"shear_stiffness": "전단 강도",
		&"bend_enabled": "굽힘 제약",
		&"bend_stiffness": "굽힘 강도",
		&"gravity": "중력",
		&"drag": "공기 저항",
		&"wind": "바람 세기",
		&"wind_gust": "돌풍 주기",
		&"collision_enabled": "충돌 (치마)",
		&"collision_response": "충돌 응답 방식",
		&"collision_friction": "충돌 마찰",
		&"stimulus_speed": "자극 속도",
		&"stimulus_amount": "자극 세기",
		&"leg_swing": "다리 스윙",
		&"show_constraints": "제약 표시",
		&"show_particles": "파티클 표시",
		&"show_colliders": "충돌체 표시",
	}


func get_presets() -> Dictionary:
	return {
		"치마": {
			&"shape": 0,
			&"columns": 16,
			&"rows": 11,
			&"iterations": 6,
			&"shear_enabled": true,
			&"shear_stiffness": 0.7,
			&"bend_enabled": true,
			&"bend_stiffness": 0.3,
			&"wind": 0.0,
			&"leg_swing": 0.45,
		},
		"커튼": {&"shape": 1, &"pin_mode": 0, &"columns": 16, &"rows": 12, &"wind": 12.0},
		"전단 실험": {
			&"shape": 1,
			&"pin_mode": 1,
			&"columns": 14,
			&"rows": 12,
			&"wind": 0.0,
			&"shear_enabled": false,
			&"bend_enabled": true,
		},
		"종이처럼": {&"shape": 1, &"pin_mode": 0, &"bend_enabled": false, &"wind": 16.0},
		"깃발": {&"shape": 1, &"pin_mode": 1, &"wind": 26.0, &"wind_gust": 2.2, &"drag": 0.01},
	}


func get_camera_focus() -> Vector3:
	return Vector3(0.0, 0.82, 0.0)


func get_camera_distance() -> float:
	return 2.1


func smoke_check() -> String:
	if _cloth.positions.is_empty():
		return "천이 만들어지지 않았다"
	if _cloth.average_stretch() > 0.5:
		return "천이 평균 %.2fm 늘어났다" % _cloth.average_stretch()
	if _mesh.get_surface_count() == 0:
		return "메쉬가 만들어지지 않았다"
	return ""
