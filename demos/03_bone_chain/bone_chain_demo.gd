class_name BoneChainDemo
extends JiggleDemo

## 데모 03 — 본 체인 Verlet (머리카락 · 꼬리)
##
## 데모 02가 스프링 [b]하나[/b]로 본 [b]하나[/b]를 흔들었다면,
## 여기서는 [JiggleVerletChain]으로 본 [b]사슬[/b]을 흔든다.
##
## 화면에 세 가지가 겹쳐 보인다.
## [codeblock]
## 초록 선   흔들림이 없을 때의 rest 사슬
## 노랑 십자 Verlet 파티클 (제약이 덜 풀리면 여기가 늘어난다)
## 흰 선     실제로 본이 만들어 낸 사슬 (길이는 항상 정확하다)
## [/codeblock]
## [b]노랑 십자와 흰 선이 어긋나는 정도가 곧 "제약이 얼마나 덜 풀렸는가"다.[/b]
## 반복 횟수를 1로 내리면 눈에 띄게 벌어진다.

const GROUND_COLOR := Color(0.10, 0.11, 0.13)
## 지금 충돌 중인 입자 표시색.
const COLOR_CONTACT := Color(1.0, 0.25, 0.35)

@export_group("사슬 구조")
## 머리카락 다발 개수. 바꾸면 리그를 다시 만든다.
@export_range(1, 12, 1) var strand_count := 8
## 다발 하나당 본 개수. 길수록 흔들림은 풍부해지지만 불안정해진다.
@export_range(2, 12, 1) var segment_count := 6
@export_range(0.02, 0.12, 0.005) var segment_length := 0.055

@export_group("시뮬레이션")
## 제약 반복 횟수. [b]사슬의 뻣뻣함을 정하는 가장 중요한 값[/b].
@export_range(1, 16, 1) var iterations := 6
## 거리 제약을 한 번에 얼마나 강하게 적용할지. 낮추면 고무줄처럼 늘어난다.
@export_range(0.05, 1.0, 0.01) var constraint_stiffness := 1.0
## 공기 저항. Verlet에서는 이게 곧 감쇠다.
@export_range(0.0, 0.25, 0.005) var drag := 0.03
@export_range(0.0, 20.0, 0.5) var gravity := 9.0
## rest 자세로 되돌아가려는 스프링의 진동수. 0이면 중력에 완전히 내맡긴다.
@export_range(0.0, 4.0, 0.05) var restore_frequency := 0.9

@export_group("제한 · 충돌")
## 이웃 마디끼리 꺾일 수 있는 최대 각도. 0이면 제한 없음(자기 위로 접힌다).
@export_range(0.0, 90.0, 1.0) var angle_limit_degrees := 35.0
@export var collision_enabled := true
## 충돌한 입자의 속도를 어떻게 처리할지. Verlet 충돌 사고의 3단계를 그대로 재현한다.
@export_enum("① 위치만 밀기 (폭주):0", "② 속도 보존 (표면에서 튐):1", "③ 접촉 안정화 (권장):2")
var collision_response: int = 2
## 표면을 스칠 때 접선 속도를 얼마나 깎을지. 0이면 얼음처럼 미끄러진다. ③에서만 동작.
@export_range(0.0, 1.0, 0.02) var collision_friction := 0.2

@export_group("자극")
@export_range(0.1, 3.0, 0.05) var stimulus_speed := 1.0
@export_range(0.0, 2.5, 0.05) var stimulus_amount := 1.0

@export_group("보기")
## 머리카락을 본 인덱스별 색으로 칠한다. 관절의 가중치 전이 구간이 보인다.
@export var show_bone_colors := false
## Verlet 파티클과 rest 사슬을 함께 그린다.
@export var show_particles := true
@export var show_colliders := true

var _rig: HairRig
var _modifiers: Array[JiggleChainModifier3D] = []
var _structure := Vector3.ZERO
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

	_rebuild_rig()


## 구조 파라미터가 바뀌면 스켈레톤과 메쉬를 통째로 다시 만든다.
func _rebuild_rig() -> void:
	if _rig != null:
		remove_child(_rig)
		_rig.queue_free()
	_modifiers.clear()

	_rig = HairRig.new()
	_rig.name = "HairRig"
	add_child(_rig)
	_rig.build(strand_count, segment_count, segment_length)

	# 다발 하나에 모디파이어 하나. 모디파이어는 Skeleton3D 의 직속 자식이어야 한다.
	for strand in _rig.strands:
		var modifier := JiggleChainModifier3D.new()
		modifier.name = "Chain_%s" % strand["root"]
		modifier.root_bone_name = String(strand["root"])
		modifier.end_bone_name = String(strand["end"])
		modifier.tip_axis = strand["tip_axis"]
		modifier.tip_length = strand["tip_length"]
		_rig.skeleton.add_child(modifier)
		_modifiers.append(modifier)

	_structure = Vector3(strand_count, segment_count, segment_length)
	_apply_simulation_params()


func _frame_update(_delta: float) -> void:
	if _rig == null:
		return
	# 자극은 머리 전체를 움직인다. 머리카락은 관성 때문에 뒤처지면서 흔들린다.
	_rig.transform = Transform3D(Basis.from_euler(stimulus.euler), stimulus.offset)
	# 충돌체도 같이 움직여야 머리카락이 머리를 통과하지 않는다.
	_rig.refresh_colliders()


func reset_demo() -> void:
	stimulus.reset()
	if _rig == null:
		return
	_rig.transform = Transform3D.IDENTITY
	_rig.refresh_colliders()
	_rig.reset_pose()
	for modifier in _modifiers:
		modifier.reset_simulation()


func on_params_changed() -> void:
	stimulus.speed = stimulus_speed
	stimulus.amount = stimulus_amount
	var structure := Vector3(strand_count, segment_count, segment_length)
	if not structure.is_equal_approx(_structure):
		_rebuild_rig()
		return
	_apply_simulation_params()


func _apply_simulation_params() -> void:
	if _rig == null:
		return
	_rig.set_bone_color_view(show_bone_colors)
	# 복원력도 결국 데모 01의 스프링이다. 진동수를 강성으로 환산해 넘긴다.
	var restore := 0.0
	if restore_frequency > 0.0:
		restore = JiggleSpring.params_from_frequency(restore_frequency, 1.0).x
	for modifier in _modifiers:
		var chain := modifier.chain
		chain.iterations = iterations
		chain.constraint_stiffness = constraint_stiffness
		chain.drag = drag
		chain.gravity = Vector3.DOWN * gravity
		chain.restore_stiffness = restore
		chain.angle_limit = deg_to_rad(angle_limit_degrees)
		chain.collision_response = collision_response as JiggleVerletBody.CollisionResponse
		chain.collision_friction = collision_friction
		chain.colliders = _rig.colliders if collision_enabled else _no_colliders


func _draw_debug() -> void:
	_draw_grid()
	if show_colliders:
		for collider in _rig.colliders:
			debug.capsule(
				collider.point_a, collider.point_b, collider.radius, Color(0.35, 0.75, 1.0, 0.22)
			)
	for modifier in _modifiers:
		# 실제로 본이 만들어 낸 사슬. 길이는 항상 rest 그대로다.
		debug.polyline(modifier.reconstructed, Color(1.0, 1.0, 1.0, 0.5))
		if not show_particles:
			continue
		debug.polyline(modifier.rest_points, JiggleDebugDraw.COLOR_TARGET)
		var chain := modifier.chain
		for i in chain.positions.size():
			var normal: Vector3 = chain.contact_normals[i]
			if normal.length_squared() < 0.000001:
				debug.cross_mark(chain.positions[i], 0.011, JiggleDebugDraw.COLOR_ACTUAL)
				continue
			# 지금 충돌 중인 입자. 어느 가닥이 표면에 끌리고 있는지 한눈에 보인다.
			debug.sphere(chain.positions[i], 0.016, COLOR_CONTACT, 10)
			debug.arrow(chain.positions[i], normal.normalized() * 0.05, COLOR_CONTACT)


func sample_plot() -> Dictionary:
	if _modifiers.is_empty():
		return {}
	var chain := _modifiers[_modifiers.size() / 2].chain
	var tip := chain.positions.size() - 1
	if tip < 0 or chain.rest_positions.size() <= tip:
		return {}
	return {
		"tip": chain.positions[tip].x - chain.rest_positions[tip].x,
		# 길이 오차를 cm 로. 반복 횟수를 내리면 이 선이 확 뜬다.
		"stretch": chain.length_error() * 100.0,
	}


func get_plot_series() -> Array[Dictionary]:
	return [
		{"id": "tip", "color": Color(1.0, 0.70, 0.35)},
		{"id": "stretch", "color": Color(0.45, 0.95, 0.60)},
	]


func get_plot_info() -> String:
	if _modifiers.is_empty():
		return ""
	var chain := _modifiers[_modifiers.size() / 2].chain
	return "끝점 좌우 변위(주황) · 길이 오차 cm(초록)   |   반복 %d회 → 오차 %.2f mm" % [
		iterations, chain.length_error() * 1000.0
	]


func get_demo_title() -> String:
	return "03 · 본 체인 Verlet (머리카락)"


func get_demo_description() -> String:
	return """[b]사슬은 스프링이 아니라 Verlet으로 푼다.[/b] 스프링을 여러 개 이으면 강성이 서로 간섭해 잘 터지지만, Verlet은 위치를 직접 고쳐 제약을 만족시키므로 몇 개를 잇든 안정적이다.
초록 = rest 사슬 · 노랑 십자 = Verlet 파티클 · 흰 선 = 본이 만든 실제 사슬 · [color=#ff4059]빨간 구 = 지금 충돌 중인 입자[/color].
[color=#8ab4ff]해볼 것[/color]  ① [b]반복 횟수[/b]를 1로 내린다 → 초록 그래프(길이 오차)가 치솟고 머리카락이 고무줄처럼 늘어난다. 12로 올리면 즉시 뻣뻣해진다. [b]반복 횟수 = 뻣뻣함[/b].
② [b]본 개수[/b]를 12로 올린다 → 끝이 어깨에 닿기 시작하고, 빨간 구가 뜬 가닥만 다르게 움직인다. [b]rest 자세가 충돌체에 파묻힌 가닥은 파라미터로 못 고친다[/b] — 리그 형상을 고쳐야 한다.
③ [b]충돌 응답 방식[/b]을 ①로 바꾼다 → 밀어내기가 속도를 만들어 사슬이 폭주한다(안전장치가 rest로 되돌린다). ②는 폭주는 없지만 표면에서 튄다.
④ [b]각도 제한[/b]을 0으로 두고 자극을 세게 준다 → 머리카락이 자기 위로 접히며 튜브가 뒤집힌다.
⑤ [b]복원 진동수[/b]를 0으로 → 한 번 흐트러진 머리가 영영 제자리로 안 돌아온다. 이게 데모 01의 스프링을 파티클에 얹는 이유."""


func get_param_labels() -> Dictionary:
	return {
		&"show_debug": "디버그 표시",
		&"strand_count": "다발 개수 ⟲",
		&"segment_count": "본 개수 ⟲",
		&"segment_length": "마디 길이 ⟲",
		&"iterations": "제약 반복 횟수",
		&"constraint_stiffness": "거리 제약 강도",
		&"drag": "공기 저항",
		&"gravity": "중력",
		&"restore_frequency": "복원 진동수 (Hz)",
		&"angle_limit_degrees": "각도 제한 (0=무제한)",
		&"collision_enabled": "충돌",
		&"collision_response": "충돌 응답 방식",
		&"collision_friction": "충돌 마찰",
		&"stimulus_speed": "자극 속도",
		&"stimulus_amount": "자극 세기",
		&"show_bone_colors": "본 색 보기",
		&"show_particles": "파티클 · rest 표시",
		&"show_colliders": "충돌체 표시",
	}


func get_presets() -> Dictionary:
	return {
		"기본": {
			&"segment_count": 6,
			&"segment_length": 0.055,
			&"iterations": 6,
			&"constraint_stiffness": 1.0,
			&"drag": 0.03,
			&"gravity": 9.0,
			&"restore_frequency": 0.9,
			&"angle_limit_degrees": 35.0,
			&"collision_enabled": true,
		},
		"긴 생머리": {
			&"segment_count": 10,
			&"segment_length": 0.062,
			&"iterations": 10,
			&"drag": 0.02,
			&"restore_frequency": 0.5,
			&"angle_limit_degrees": 26.0,
		},
		"짧은 단발": {
			&"segment_count": 4,
			&"segment_length": 0.042,
			&"iterations": 8,
			&"drag": 0.06,
			&"restore_frequency": 1.8,
			&"angle_limit_degrees": 45.0,
		},
		"뻣뻣한 끈": {
			&"iterations": 14,
			&"constraint_stiffness": 1.0,
			&"drag": 0.10,
			&"restore_frequency": 2.6,
			&"angle_limit_degrees": 12.0,
		},
		"고무줄": {
			&"iterations": 1,
			&"constraint_stiffness": 0.4,
			&"drag": 0.06,
			&"restore_frequency": 0.4,
		},
	}


func get_camera_focus() -> Vector3:
	return Vector3(0.0, 1.24, 0.0)


func get_camera_distance() -> float:
	return 1.7


func smoke_check() -> String:
	for modifier in _modifiers:
		if modifier.chain.positions.is_empty():
			return "%s: 사슬이 만들어지지 않았다 (본 이름 확인)" % modifier.name
		if modifier.reconstructed.is_empty():
			return "%s: 모디파이어 콜백이 돌지 않았다" % modifier.name
		if modifier.chain.length_error() > 1.0:
			return "%s: 사슬이 %.2fm 늘어났다" % [modifier.name, modifier.chain.length_error()]
	return ""


func _draw_grid() -> void:
	var color := Color(1.0, 1.0, 1.0, 0.05)
	for i in range(-8, 9):
		var t := float(i) * 0.25
		debug.line(Vector3(t, 0.001, -2.0), Vector3(t, 0.001, 2.0), color)
		debug.line(Vector3(-2.0, 0.001, t), Vector3(2.0, 0.001, t), color)
