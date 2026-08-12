class_name SoftBodyCompareDemo
extends JiggleDemo

## 데모 06 — 자작 Verlet 천 vs 내장 [SoftBody3D]
##
## 같은 격자 메쉬를 두 장 만들어 왼쪽은 데모 04의 [JiggleVerletCloth] 로,
## 오른쪽은 Godot 내장 [SoftBody3D](Jolt) 로 시뮬레이션한다.
## 공이 두 천을 [b]동시에[/b] 통과하며 밀어내므로 반응 차이가 그대로 보인다.
##
## [color=#ff8c5a]주황 = 자작[/color] · [color=#5aa8ff]파랑 = 내장[/color]

const GROUND_COLOR := Color(0.10, 0.11, 0.13)
const CUSTOM_COLOR := Color(0.72, 0.34, 0.22)
const BUILTIN_COLOR := Color(0.22, 0.40, 0.72)
const SLOT_X := 0.55
const CLOTH_WIDTH := 0.80
const CLOTH_HEIGHT := 0.72
const CLOTH_TOP := 1.20
const BALL_RADIUS := 0.13

const CLOTH_SHADER := """
shader_type spatial;
render_mode cull_disabled, diffuse_burley;

uniform vec3 cloth_color : source_color = vec3(0.7, 0.3, 0.3);

void fragment() {
	ALBEDO = cloth_color;
	ROUGHNESS = 0.72;
	NORMAL = FRONT_FACING ? NORMAL : -NORMAL;
}
"""

@export_group("천 구조")
## 바꾸면 양쪽 천을 다시 만든다.
@export_range(6, 24, 1) var columns := 14
@export_range(6, 20, 1) var rows := 12

@export_group("공통 파라미터")
## 자작 [code]iterations[/code] ↔ 내장 [code]simulation_precision[/code].
@export_range(1, 16, 1) var iterations := 6
## 자작 구조 제약 강도 ↔ 내장 [code]linear_stiffness[/code].
@export_range(0.1, 1.0, 0.01) var stiffness := 0.9
## 자작 공기저항 ↔ 내장 [code]damping_coefficient[/code].
@export_range(0.0, 0.3, 0.005) var damping := 0.02

@export_group("자작에만 있는 것")
## 내장은 내부적으로 고정이라 끄고 켤 수 없다.
@export var shear_enabled := true
@export var bend_enabled := true
## [SoftBody3D] 에는 외력을 넣는 API가 없다. 자작 쪽에만 걸린다.
@export_range(0.0, 40.0, 0.5) var wind := 0.0

@export_group("내장에만 있는 것")
## 자작 Verlet에는 질량 개념이 아예 없다(모든 입자가 같은 역질량).
@export_range(0.1, 20.0, 0.1) var total_mass := 2.0
## 천 내부의 압력. 풍선처럼 부풀린다. 자작에는 없다.
@export_range(0.0, 40.0, 0.5) var pressure := 0.0

@export_group("자극")
@export_range(0.1, 3.0, 0.05) var stimulus_speed := 1.0
@export_range(0.0, 2.0, 0.05) var stimulus_amount := 1.0

@export_group("보기")
@export var show_custom := true
@export var show_builtin := true
@export var show_colliders := false

var _cloth := JiggleVerletCloth.new()
var _mesh := ArrayMesh.new()
var _custom_instance: MeshInstance3D
var _soft_body: SoftBody3D
var _ball: StaticBody3D
var _custom_ball_mesh: MeshInstance3D
var _ball_collider := JiggleVerletBody.Collider.new(Vector3.ZERO, Vector3.ZERO, BALL_RADIUS)
var _colliders: Array[JiggleVerletBody.Collider] = []

var _custom_material := ShaderMaterial.new()
var _builtin_material := ShaderMaterial.new()
var _pinned := PackedInt32Array()
var _rest_points := PackedVector3Array()
var _structure := Vector2.ZERO
var _sim_usec := 0.0
var _physics_msec := 0.0
var _frame_msec := 0.0


func _build() -> void:
	stimulus.kind = Stimulus.Kind.SIDE_STEP
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

	_setup_material(_custom_material, CUSTOM_COLOR)
	_setup_material(_builtin_material, BUILTIN_COLOR)

	_custom_instance = MeshInstance3D.new()
	_custom_instance.name = "CustomCloth"
	_custom_instance.mesh = _mesh
	_custom_instance.material_override = _custom_material
	_custom_instance.custom_aabb = AABB(Vector3(-3.0, -1.0, -3.0), Vector3(6.0, 5.0, 6.0))
	add_child(_custom_instance)

	# 공은 [b]양쪽에 하나씩[/b] 둔다. 두 천이 좌우로 떨어져 있어 공 하나로는 둘 다 못 건드린다.
	# 자작 쪽은 JiggleVerletBody.Collider(그냥 데이터), 내장 쪽은 StaticBody3D(물리 노드)여야 한다.
	# 같은 일을 하는데 요구하는 형태가 다르다는 것 자체가 비교 포인트다.
	var ball_material := StandardMaterial3D.new()
	ball_material.albedo_color = Color(0.85, 0.80, 0.35)
	ball_material.roughness = 0.4

	_ball = StaticBody3D.new()
	_ball.name = "BuiltinBall"
	var shape := CollisionShape3D.new()
	var sphere_shape := SphereShape3D.new()
	sphere_shape.radius = BALL_RADIUS
	shape.shape = sphere_shape
	_ball.add_child(shape)
	_ball.add_child(_make_ball_mesh(ball_material))
	add_child(_ball)

	_custom_ball_mesh = _make_ball_mesh(ball_material)
	_custom_ball_mesh.name = "CustomBall"
	add_child(_custom_ball_mesh)

	_colliders.append(_ball_collider)
	_rebuild()


func _make_ball_mesh(material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = BALL_RADIUS
	sphere_mesh.height = BALL_RADIUS * 2.0
	instance.mesh = sphere_mesh
	instance.material_override = material
	return instance


func _setup_material(material: ShaderMaterial, color: Color) -> void:
	var shader := Shader.new()
	shader.code = CLOTH_SHADER
	material.shader = shader
	material.set_shader_parameter("cloth_color", color)


func _rebuild() -> void:
	# --- 자작 ---
	var points := PackedVector3Array()
	_pinned = PackedInt32Array()
	for row in rows + 1:
		for column in columns + 1:
			points.append(_grid_point(row, column, -SLOT_X))
			if row == 0:
				_pinned.append(points.size() - 1)
	_rest_points = points.duplicate()
	_cloth.build(points, columns, rows, false)
	for index in _pinned:
		_cloth.pin(index)
	_cloth.colliders = _colliders

	# --- 내장 ---
	# 같은 격자를 오른쪽에 한 장 더 만들고 SoftBody3D 에 넘긴다.
	if _soft_body != null:
		remove_child(_soft_body)
		_soft_body.queue_free()
	var builtin_points := PackedVector3Array()
	for row in rows + 1:
		for column in columns + 1:
			builtin_points.append(_grid_point(row, column, SLOT_X))
	var arrays := _cloth.mesh_arrays()
	arrays[Mesh.ARRAY_VERTEX] = builtin_points
	var builtin_mesh := ArrayMesh.new()
	builtin_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	_soft_body = SoftBody3D.new()
	_soft_body.name = "BuiltinCloth"
	_soft_body.mesh = builtin_mesh
	_soft_body.material_override = _builtin_material
	add_child(_soft_body)
	# 고정점 지정은 [b]메쉬 정점 인덱스[/b]로 한다. 자작의 pin()과 개념은 같다.
	for index in _pinned:
		_soft_body.set_point_pinned(index, true, NodePath(), -1)

	_structure = Vector2(columns, rows)
	_apply_params()
	_update_mesh()


func _grid_point(row: int, column: int, offset_x: float) -> Vector3:
	return Vector3(
		offset_x + (float(column) / float(columns) - 0.5) * CLOTH_WIDTH,
		CLOTH_TOP - float(row) / float(rows) * CLOTH_HEIGHT,
		0.0
	)


func _frame_update(_delta: float) -> void:
	# 공이 앞뒤로 오가며 두 천을 동시에 통과한다.
	var sweep := sin(stimulus.cycle * PI) * 0.42 * stimulus_amount
	var height := CLOTH_TOP - CLOTH_HEIGHT * 0.45
	var custom_position := Vector3(-SLOT_X, height, sweep)
	var builtin_position := Vector3(SLOT_X, height, sweep)
	_ball.position = builtin_position
	_custom_ball_mesh.position = custom_position
	_ball_collider.point_a = custom_position
	_ball_collider.point_b = custom_position

	_cloth.apply_wind(Vector3(0.2, 0.1, 1.0).normalized(), wind)
	_custom_instance.visible = show_custom
	_custom_ball_mesh.visible = show_custom
	_soft_body.visible = show_builtin
	_ball.visible = show_builtin
	_physics_msec = lerpf(
		_physics_msec, Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0, 0.08
	)
	_frame_msec = lerpf(
		_frame_msec, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, 0.08
	)


func _simulate(delta: float) -> void:
	if not show_custom:
		return
	var start := Time.get_ticks_usec()
	_cloth.step(delta)
	_sim_usec = lerpf(_sim_usec, float(Time.get_ticks_usec() - start), 0.08)


func _post_simulate(_delta: float) -> void:
	_update_mesh()


func _update_mesh() -> void:
	_cloth.update_normals()
	_mesh.clear_surfaces()
	_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _cloth.mesh_arrays())


func reset_demo() -> void:
	stimulus.reset()
	if _rest_points.is_empty():
		return
	_cloth.reset_to(_rest_points)
	_update_mesh()


func on_params_changed() -> void:
	stimulus.speed = stimulus_speed
	stimulus.amount = stimulus_amount
	var structure := Vector2(columns, rows)
	if not structure.is_equal_approx(_structure):
		_rebuild()
		return
	_apply_params()


func _apply_params() -> void:
	_cloth.iterations = iterations
	_cloth.structural_stiffness = stiffness
	_cloth.shear_enabled = shear_enabled
	_cloth.bend_enabled = bend_enabled
	_cloth.drag = damping

	# 내장은 중력을 개별로 못 준다. 프로젝트 물리 중력을 그대로 쓴다.
	_soft_body.simulation_precision = iterations
	_soft_body.linear_stiffness = stiffness
	_soft_body.damping_coefficient = damping
	_soft_body.total_mass = total_mass
	_soft_body.pressure_coefficient = pressure


func _draw_debug() -> void:
	if not show_colliders:
		return
	debug.sphere(_ball_collider.point_a, BALL_RADIUS, Color(0.9, 0.85, 0.4, 0.35), 20)
	debug.sphere(_ball.position, BALL_RADIUS, Color(0.9, 0.85, 0.4, 0.35), 20)


func sample_plot() -> Dictionary:
	var bottom_row := rows * (columns + 1)
	var middle := bottom_row + columns / 2
	if _cloth.positions.size() <= middle:
		return {}
	var rest := _rest_points[middle]
	var custom_offset := _cloth.positions[middle].distance_to(rest)
	var builtin_offset := 0.0
	if _soft_body != null:
		var mirrored := rest + Vector3(SLOT_X * 2.0, 0.0, 0.0)
		builtin_offset = _soft_body.get_point_transform(middle).distance_to(mirrored)
	return {"custom": custom_offset, "builtin": builtin_offset}


func get_plot_series() -> Array[Dictionary]:
	return [
		{"id": "custom", "color": Color(1.0, 0.62, 0.30)},
		{"id": "builtin", "color": Color(0.45, 0.75, 1.0)},
	]


func get_plot_info() -> String:
	return "밑단 중앙의 rest 대비 변위 m   |   자작 시뮬 %.2fms   |   물리 프레임 %.2fms   |   전체 프레임 %.2fms" % [
		_sim_usec / 1000.0, _physics_msec, _frame_msec
	]


func get_demo_title() -> String:
	return "06 · 내장 SoftBody 비교"


func get_demo_description() -> String:
	return """[b]같은 격자, 같은 공, 다른 구현.[/b] [color=#ff8c5a]왼쪽(주황) = 데모 04의 자작 Verlet 천[/color] · [color=#5aa8ff]오른쪽(파랑) = 내장 SoftBody3D(Jolt)[/color].
[b]대응표[/b]  자작 [code]iterations[/code] ↔ 내장 [code]simulation_precision[/code] · 구조 제약 강도 ↔ [code]linear_stiffness[/code] · 공기저항 ↔ [code]damping_coefficient[/code].
[b]자작에만[/b] 전단·굽힘 제약을 따로 끄고 켜기, 바람 같은 임의 외력, 정점을 직접 읽고 쓰기. [b]내장에만[/b] 질량, 내부 압력, 물리 월드의 다른 강체와의 상호작용.
[color=#8ab4ff]해볼 것[/color]  ① 공이 지나갈 때 두 천이 어떻게 다르게 밀리는지 본다. 내장은 물리 서버에서 [b]물리 틱[/b]에, 자작은 [b]렌더 프레임[/b]에 돈다.
② [b]압력[/b]을 올린다 → 내장 쪽만 풍선처럼 부푼다. 자작 Verlet에는 부피 개념이 없다.
③ [b]바람[/b]을 올린다 → 자작 쪽만 반응한다. [code]SoftBody3D[/code] 에는 외력을 넣는 API가 없다.
④ 비용: 자작은 [code]_process[/code] 안에서 직접 계측되고, 내장은 [b]물리 서버 시간[/b]에 들어간다. 두 숫자는 서로 다른 예산에서 나온다.
[color=#ff8080]현실적인 차이[/color]  내장은 고정점을 임의의 노드에 붙이려면 [PhysicsBody3D] 가 필요하고, 중력도 개별 설정이 안 된다. 캐릭터에 붙는 옷은 그래서 대부분 자작 쪽이 편하다."""


func get_param_labels() -> Dictionary:
	return {
		&"show_debug": "디버그 표시",
		&"columns": "가로 칸수 ⟲",
		&"rows": "세로 칸수 ⟲",
		&"iterations": "반복 (precision)",
		&"stiffness": "강성 (linear_stiffness)",
		&"damping": "감쇠 (damping)",
		&"shear_enabled": "전단 제약",
		&"bend_enabled": "굽힘 제약",
		&"wind": "바람",
		&"total_mass": "총 질량",
		&"pressure": "내부 압력",
		&"stimulus_speed": "자극 속도",
		&"stimulus_amount": "공 이동 폭",
		&"show_custom": "자작 보기",
		&"show_builtin": "내장 보기",
		&"show_colliders": "충돌체 표시",
	}


func get_presets() -> Dictionary:
	return {
		"기본": {
			&"iterations": 6,
			&"stiffness": 0.9,
			&"damping": 0.02,
			&"wind": 0.0,
			&"pressure": 0.0,
			&"total_mass": 2.0,
		},
		"뻣뻣": {&"iterations": 12, &"stiffness": 1.0, &"damping": 0.05},
		"흐물": {&"iterations": 2, &"stiffness": 0.3, &"damping": 0.01},
		"압력(내장만)": {&"pressure": 22.0, &"stiffness": 0.7},
		"바람(자작만)": {&"wind": 22.0, &"stiffness": 0.8},
	}


func get_camera_focus() -> Vector3:
	return Vector3(0.0, 0.88, 0.0)


func get_camera_distance() -> float:
	return 2.6


func smoke_check() -> String:
	if _cloth.positions.is_empty():
		return "자작 천이 만들어지지 않았다"
	if _soft_body == null or _soft_body.mesh == null:
		return "내장 SoftBody3D 가 만들어지지 않았다"
	if _cloth.average_stretch() > 0.5:
		return "자작 천이 평균 %.2fm 늘어났다" % _cloth.average_stretch()
	return ""
