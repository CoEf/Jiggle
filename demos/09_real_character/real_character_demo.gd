class_name RealCharacterDemo
extends JiggleDemo

## 데모 09 — 실제 캐릭터에 모디파이어 붙이기
##
## 데모 01~08은 전부 [b]코드로 만든 리그[/b]를 썼다. 본 축이 단위행렬이고, 이름도 내가 정했고,
## rest 자세가 충돌체에 파묻힐 일도 없었다. 그 조건에서 잘 도는 것은 당연하다.
##
## 이 데모는 밖에서 가져온 [b]Rigify 계열 캐릭터(본 183개)[/b]에 앞 데모의 모디파이어를 그대로 붙인다.
## 코드로 새로 만든 것은 하나도 없고, [JiggleChainModifier3D] · [JiggleBoneModifier3D] ·
## [JiggleCollider3D] 를 리그에 맞게 설정해 붙이기만 한다.
##
## [b]실제 리그에서 처음 만나는 차이[/b]
## [codeblock]
## 본 축      자작 리그는 단위행렬, 이 리그는 본 로컬 +Y  → tip_axis 를 바꿔야 한다
## 이름       breast.L / Hair_Fringe.001 / Dress_S.L.001  → 규칙으로 찾아야 한다
## 개수       흔들 사슬이 30가닥이 넘는다                 → 그룹별로 켜고 끌 수 있어야 한다
## 충돌       머리·골반·허벅지를 본에 붙여야 따라다닌다   → BoneAttachment3D + JiggleCollider3D
## 이름 오류  앞리본 왼쪽 뿌리가 "Back" 이다              → CharacterRig.MISNAMED_BONES
## [/codeblock]
##
## [b]기본값은 손으로 맞춘 것이다.[/b] 여기 적힌 재질값 · 충돌체 치수 · 가슴 설정은
## [code]assets/adachi_rigged4/adachi_rigged4_jiggle.tscn[/code] 을 에디터에서
## 눈으로 맞춘 결과와 같은 값이다. 계산으로 나온 값이 아니라 [b]이 캐릭터에 맞춘 값[/b]이다.

const GROUND_COLOR := Color(0.10, 0.11, 0.13)
const COLOR_CONTACT := Color(1.0, 0.25, 0.35)

## 리본 4종의 재질값. 슬라이더로 빼지 않고 표로 박아 둔 값이다.
##
## 리본은 머리카락·치마와 달리 [b]가닥마다 소재가 다르다[/b] — 앞리본 옆은 뻣뻣하고,
## 뒤리본 꼬리는 길고 흐물거린다. 슬라이더 한 벌로 묶으면 그 차이가 첫 프레임에 사라진다.
## 표에 없는 값(반복 횟수 · 거리 제약 · 공기 저항 · 파티클 두께)은 넷 다 리소스 기본값이다.
##
## 키는 [b]끝 본 이름[/b]의 앞부분이다. 뿌리 이름으로 나눌 수 없다 —
## 왼쪽 앞리본만 뿌리 이름이 "Back" 이기 때문이다([member CharacterRig.MISNAMED_BONES]).
const RIBBON_MATERIALS := {
	"Front_Ribbon_Side": {"shape": 0.40, "elasticity": 0.07, "gravity": 3.0, "angle": 0.0},
	"Front_Ribbon_Tail": {"shape": 0.25, "elasticity": 0.10, "gravity": 3.0, "angle": 0.0},
	"Back_Ribbon_Side": {"shape": 0.25, "elasticity": 0.05, "gravity": 4.0, "angle": 0.0},
	"Back_Ribbon_Tail": {"shape": 0.15, "elasticity": 0.10, "gravity": 4.0, "angle": 15.0},
}

@export_group("가슴")
@export var breast_enabled := true
## 본 원점에서 흔들리는 덩어리 중심까지의 거리. 스프링 팔 길이다.
## 리그에서 잰 자식 본(breast.L.001)까지의 거리가 아니라 [b]씬에서 손으로 맞춘 값[/b]이다.
@export_range(0.02, 0.4, 0.005) var breast_tip_length := 0.18
## 1초에 몇 번 출렁이는가.
@export_range(0.5, 6.0, 0.05) var breast_frequency := 2.4
## 1.0이면 지나쳤다가 돌아오는 출렁임 없이 목표를 따라가기만 한다.
@export_range(0.02, 1.0, 0.01) var breast_damping := 1.0
## 아래로 당기는 연출용 가속도. 실제 중력(9.8)을 넣으면 과하게 늘어진다.
@export_range(0.0, 9.8, 0.1) var breast_gravity := 3.0
@export_range(0.0, 180.0, 1.0) var breast_max_angle := 100.0
## 상하 강성 배율. 1보다 작으면 위아래로 더 잘 흔들린다.
@export_range(0.2, 2.0, 0.05) var breast_vertical_ratio := 0.2
## 좌우/앞뒤 강성 배율. 1보다 작으면 좌우로 더 잘 흔들린다.
@export_range(0.2, 2.0, 0.05) var breast_horizontal_ratio := 1.0
## 흔들린 만큼 본 축으로 늘리는 연출. 실제 메쉬에서는 조금만 줘도 티가 난다.
@export_range(0.0, 0.6, 0.01) var breast_squash := 0.0

@export_group("머리카락")
@export var hair_enabled := true
@export_range(1, 16, 1) var hair_iterations := 6
## 거리 제약을 한 번에 얼마나 강하게 적용할지. 낮추면 가닥이 고무줄처럼 늘어난다.
## 이 머리채는 낮게 두어 모양 유지 쪽에 일을 맡긴다.
@export_range(0.0, 1.0, 0.01) var hair_constraint_stiffness := 0.10
## rest 모양을 유지하려는 강성. 0이면 축 늘어진 밧줄이 된다.
@export_range(0.0, 1.0, 0.01) var hair_shape_stiffness := 0.45
## 모양을 되돌리는 힘의 탄성. 1이면 착지 순간 스프링처럼 튄다.
@export_range(0.0, 1.0, 0.01) var hair_shape_elasticity := 0.0
@export_range(0.0, 4.0, 0.01) var hair_restore_frequency := 0.59
@export_range(0.0, 0.5, 0.005) var hair_drag := 0.50
@export_range(0.0, 90.0, 1.0) var hair_angle_limit := 45.0
@export_range(0.0, 20.0, 0.5) var hair_gravity := 9.0
## 파티클 자체의 두께. 충돌 시 이만큼 여유를 둔다.
@export_range(0.0, 0.06, 0.002) var hair_particle_radius := 0.012

@export_group("리본")
## 리본 4종은 [member RIBBON_MATERIALS] 의 값을 그대로 쓴다.
@export var ribbon_enabled := true
## 리본 4종의 모양 유지를 한꺼번에 올리고 내리는 [b]배율[/b]. 1이면 표 값 그대로다.
##
## 값이 아니라 배율인 이유는 종류별 차이(앞옆 0.40 · 뒤꼬리 0.15 …)를 지우지 않기 위해서다.
## 슬라이더 하나로 값을 직접 쓰면 4종이 첫 프레임에 같은 리본이 된다.
@export_range(0.0, 2.0, 0.05) var ribbon_shape_scale := 1.0

@export_group("치마")
@export var skirt_enabled := true
## 치마는 가닥이 12개라 반복 횟수가 비용에 그대로 곱해진다.
@export_range(1, 16, 1) var skirt_iterations := 8
@export_range(0.0, 1.0, 0.01) var skirt_constraint_stiffness := 1.0
## 치마는 천이라 두께가 있다. 이 값이 0이면 밧줄 12가닥처럼 축 늘어진다.
@export_range(0.0, 1.0, 0.01) var skirt_shape_stiffness := 0.50
## 모양을 되돌리는 힘의 탄성. 1이면 착지 순간 스프링처럼 튄다.
@export_range(0.0, 1.0, 0.01) var skirt_shape_elasticity := 0.0
@export_range(0.0, 4.0, 0.01) var skirt_restore_frequency := 0.7
@export_range(0.0, 0.5, 0.005) var skirt_drag := 0.30
## 0으로 두면 치맛자락이 자기 위로 접혀 메쉬가 뒤집힌다.
@export_range(0.0, 90.0, 1.0) var skirt_angle_limit := 30.0
@export_range(0.0, 20.0, 0.5) var skirt_gravity := 9.0
## 치마가 다리에 딱 붙는 게 싫으면 올린다. 머리카락보다 두껍다.
@export_range(0.0, 0.06, 0.002) var skirt_particle_radius := 0.02

@export_group("충돌")
@export var collision_enabled := true
## 머리·골반·허벅지 충돌체 반지름을 한꺼번에 조절한다.
@export_range(0.4, 2.0, 0.02) var collider_scale := 1.0
@export_range(0.0, 1.0, 0.02) var collision_friction := 0.2

@export_group("자극")
@export_range(0.1, 3.0, 0.05) var stimulus_speed := 1.0
@export_range(0.0, 2.5, 0.05) var stimulus_amount := 1.0

@export_group("보기")
@export var show_model := true
@export var show_colliders := true
## 사슬 30가닥을 전부 그리면 화면이 가득 차므로 기본은 끔.
@export var show_chains := false

var rig: CharacterRig = null
var breast_modifiers: Array[JiggleBoneModifier3D] = []
var hair_modifiers: Array[JiggleChainModifier3D] = []
var skirt_modifiers: Array[JiggleChainModifier3D] = []
var ribbon_modifiers: Array[JiggleChainModifier3D] = []

## 재질값은 사슬마다가 아니라 [b]소재마다[/b] 하나씩 둔다.
##
## 이 캐릭터의 사슬 모디파이어는 37개인데 재질은 여섯 가지뿐이다 —
## 머리카락 17가닥 · 치마 12가닥 · 리본 8가닥(4종).
## 예전에는 슬라이더 하나가 움직일 때마다 [b]37개 노드에 값 11개씩을 밀어 넣었다.[/b]
## [JiggleChainSettings] 를 쓰면 리소스 여섯 개만 고치면 되고,
## 나머지는 [code]changed[/code] 신호로 알아서 따라온다.
##
## [b]가닥마다 달라야 하는 것은 리소스에 안 들어간다[/b] — 본 이름 · tip 축 · 충돌체 목록.
## 그건 "이 가닥이 무엇인가"이지 "무슨 재질인가"가 아니다.
var hair_settings := JiggleChainSettings.new()
var skirt_settings := JiggleChainSettings.new()
## 리본 재질 4종. 키는 [member RIBBON_MATERIALS] 와 같다.
var ribbon_settings: Dictionary[String, JiggleChainSettings] = {}

# 그래프 기준으로 삼을 대표 사슬(가장 긴 것).
var _hair_probe: JiggleChainModifier3D = null
var _skirt_probe: JiggleChainModifier3D = null
var _ground_y := 0.0
var _height := 1.7
var _focus := Vector3(0.0, 1.0, 0.0)
var _total_usec := 0.0
# 그룹을 껐다 켤 때만 시뮬레이션을 리셋하려고 직전 상태를 들고 있는다.
var _was_enabled := {}


func _build() -> void:
	stimulus.kind = Stimulus.Kind.WALK

	rig = CharacterRig.new()
	rig.name = "CharacterRig"
	add_child(rig)
	if not rig.build():
		return

	# 카메라는 캐릭터 크기에서 자동으로 잡는다. 모델을 바꿔도 다시 맞출 필요가 없다.
	var head := rig.bone_world("Head")
	var foot := rig.bone_world("foot.L")
	var hip := rig.bone_world("spine")
	_ground_y = foot.y
	# Head 본은 목 밑이라 머리카락 높이가 빠진다. 그만큼 얹어 실제 실루엣에 맞춘다.
	_height = maxf(head.y - foot.y, 0.5) * 1.25
	_focus = Vector3(hip.x, (head.y + foot.y) * 0.5 + _height * 0.10, hip.z)
	_add_ground()

	# 충돌체 넷을 [b]모든 가닥에[/b] 물린다. 그룹별로 골라 물리면 "머리카락은 허벅지를 그냥
	# 통과한다" 같은 구멍이 조용히 남는다 — 앉거나 숙이는 자세에서 바로 드러난다.
	var body := rig.all_colliders()
	for breast: Dictionary in rig.breasts:
		breast_modifiers.append(_add_breast(breast))
	for chain: Dictionary in rig.hair_chains:
		hair_modifiers.append(_add_chain(chain, "Hair", body, hair_settings))
	for chain: Dictionary in rig.skirt_chains:
		skirt_modifiers.append(_add_chain(chain, "Skirt", body, skirt_settings))
	# 리본만 재질이 가닥마다 갈린다. 나머지 둘은 그룹 전체가 리소스 하나를 공유한다.
	for chain: Dictionary in rig.ribbon_chains:
		ribbon_modifiers.append(_add_chain(chain, "Ribbon", body, _ribbon_material(chain)))

	_hair_probe = _longest(hair_modifiers, rig.hair_chains)
	_skirt_probe = _longest(skirt_modifiers, rig.skirt_chains)


## 리본 가닥 하나가 쓸 재질. 없으면 만들어 둔다 — 4종이 다 쓰이는 리그만 있는 것은 아니다.
func _ribbon_material(chain: Dictionary) -> JiggleChainSettings:
	var key := _ribbon_material_key(String(chain["end"]))
	if not ribbon_settings.has(key):
		var settings := JiggleChainSettings.new()
		var values: Dictionary = RIBBON_MATERIALS[key]
		settings.shape_stiffness = values["shape"]
		settings.shape_elasticity = values["elasticity"]
		settings.gravity = Vector3.DOWN * float(values["gravity"])
		settings.angle_limit_degrees = values["angle"]
		ribbon_settings[key] = settings
	return ribbon_settings[key]


func _ribbon_material_key(end_bone_name: String) -> String:
	for key: String in RIBBON_MATERIALS:
		if end_bone_name.begins_with(key):
			return key
	# 규칙에 안 맞는 리본이 나오면 첫 재질을 쓴다. 조용히 안 흔들리는 것보다 낫다.
	return RIBBON_MATERIALS.keys()[0]


## 가슴 = 본 하나. [b]tip_axis 가 Y[/b] 인 것이 자작 리그와의 유일한 차이다.
##
## 스프링 팔 길이는 리그에서 잰 값([code]info["tip_length"][/code]) 대신
## [member breast_tip_length] 를 쓴다. 이 리그는 breast.L 바로 밑에 breast.L.001 이 붙어 있어
## 잰 값이 [b]덩어리 중심이 아니라 다음 본까지의 거리[/b]다 — 팔이 너무 짧아 흔들림이 안 보인다.
func _add_breast(info: Dictionary) -> JiggleBoneModifier3D:
	var modifier := JiggleBoneModifier3D.new()
	modifier.name = "Jiggle_%s" % String(info["bone"]).replace(".", "_")
	modifier.bone_name = info["bone"]
	modifier.tip_axis = JiggleBoneModifier3D.TipAxis.Y
	modifier.tip_length = breast_tip_length
	rig.skeleton.add_child(modifier)
	return modifier


## 사슬 하나. 충돌체는 [b]NodePath 로[/b] 물린다 — 실제 캐릭터에서 쓰이는 방식 그대로다.
##
## 여기서 정하는 것은 전부 [b]이 가닥에만 해당하는 것[/b]이다(이름 · 축 · 길이 · 충돌체).
## 재질값은 하나도 안 건드린다 — 그건 [param settings] 가 들고 있다.
func _add_chain(
	info: Dictionary,
	group: String,
	colliders: Array[JiggleCollider3D],
	settings: JiggleChainSettings
) -> JiggleChainModifier3D:
	var modifier := JiggleChainModifier3D.new()
	modifier.name = "%s_%s" % [group, String(info["root"]).replace(".", "_")]
	modifier.root_bone_name = info["root"]
	modifier.end_bone_name = info["end"]
	# 마지막 본의 끝 방향. 중간 본은 자식 위치에서 자동으로 구하므로 여기만 주면 된다.
	modifier.tip_axis = CharacterRig.BONE_AXIS
	modifier.tip_length = info["tip_length"]
	modifier.settings = settings
	rig.skeleton.add_child(modifier)

	var paths: Array[NodePath] = []
	for collider in colliders:
		if collider != null:
			paths.append(modifier.get_path_to(collider))
	modifier.collider_paths = paths
	return modifier


func _add_ground() -> void:
	var ground := MeshInstance3D.new()
	ground.name = "Ground"
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.0, 6.0)
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = GROUND_COLOR
	material.roughness = 0.95
	ground.material_override = material
	ground.position = Vector3(0.0, _ground_y, 0.0)
	add_child(ground)


func _frame_update(_delta: float) -> void:
	if rig == null:
		return
	# 자극이 캐릭터 전체를 움직인다. 흔들리는 부위는 관성 때문에 뒤처진다.
	rig.transform = Transform3D(Basis.from_euler(stimulus.euler), stimulus.offset)

	var total := 0
	for modifier in all_chains():
		total += modifier.last_usec
	_total_usec = lerpf(_total_usec, float(total), 0.08)


func reset_demo() -> void:
	stimulus.reset()
	if rig == null:
		return
	rig.transform = Transform3D.IDENTITY
	for modifier in breast_modifiers:
		modifier.reset_simulation()
	for modifier in all_chains():
		modifier.reset_simulation()


func on_params_changed() -> void:
	stimulus.speed = stimulus_speed
	stimulus.amount = stimulus_amount
	if rig == null:
		return

	rig.set_collider_scale(collider_scale)
	rig.set_model_visible(show_model)

	for modifier in breast_modifiers:
		modifier.active = breast_enabled
		modifier.tip_length = breast_tip_length
		modifier.frequency = breast_frequency
		modifier.damping_ratio = breast_damping
		modifier.gravity = breast_gravity
		modifier.max_angle_degrees = breast_max_angle
		modifier.vertical_ratio = breast_vertical_ratio
		modifier.horizontal_ratio = breast_horizontal_ratio
		modifier.squash = breast_squash

	# 재질값은 [b]리소스[/b]에만 쓴다. 37개 모디파이어는 changed 신호로 따라온다.
	# 슬라이더 하나가 움직일 때 예전에는 37 × 11 번 대입이 일어났다.
	hair_settings.iterations = hair_iterations
	hair_settings.constraint_stiffness = hair_constraint_stiffness
	hair_settings.shape_stiffness = hair_shape_stiffness
	hair_settings.shape_elasticity = hair_shape_elasticity
	hair_settings.restore_frequency = hair_restore_frequency
	hair_settings.drag = hair_drag
	hair_settings.angle_limit_degrees = hair_angle_limit
	hair_settings.gravity = Vector3.DOWN * hair_gravity
	hair_settings.particle_radius = hair_particle_radius
	hair_settings.collision_friction = collision_friction

	skirt_settings.iterations = skirt_iterations
	skirt_settings.constraint_stiffness = skirt_constraint_stiffness
	skirt_settings.shape_stiffness = skirt_shape_stiffness
	skirt_settings.shape_elasticity = skirt_shape_elasticity
	skirt_settings.restore_frequency = skirt_restore_frequency
	skirt_settings.drag = skirt_drag
	skirt_settings.angle_limit_degrees = skirt_angle_limit
	skirt_settings.gravity = Vector3.DOWN * skirt_gravity
	skirt_settings.particle_radius = skirt_particle_radius
	skirt_settings.collision_friction = collision_friction

	# 리본 4종은 표 값을 배율로만 건드린다. 마찰은 같이 움직인다 —
	# 그건 소재가 아니라 [b]무대 쪽 값[/b]이라 셋을 따로 놀게 할 이유가 없다.
	for key: String in ribbon_settings:
		var settings: JiggleChainSettings = ribbon_settings[key]
		settings.shape_stiffness = float(RIBBON_MATERIALS[key]["shape"]) * ribbon_shape_scale
		settings.collision_friction = collision_friction

	_apply_chain_group(hair_modifiers, hair_enabled)
	_apply_chain_group(ribbon_modifiers, ribbon_enabled)
	_apply_chain_group(skirt_modifiers, skirt_enabled)


## 그룹 하나를 켜고 끈다.
##
## 재질값이 리소스로 빠진 뒤로 [b]여기 남은 것은 가닥마다 달라야 하는 것뿐[/b]이다.
## 그룹을 껐다 켜는 것은 가닥별 시뮬레이션 상태를 건드리는 일이라 리소스가 대신할 수 없다.
func _apply_chain_group(modifiers: Array[JiggleChainModifier3D], enabled: bool) -> void:
	for modifier in modifiers:
		# 껐다 켜면 파티클이 옛 자리에 남아 있다. 그대로 두면 켜는 순간 튄다.
		if _was_enabled.get(modifier, enabled) != enabled and enabled:
			modifier.reset_simulation()
		_was_enabled[modifier] = enabled

		modifier.active = enabled
		modifier.collision_enabled = collision_enabled


func _draw_debug() -> void:
	if rig == null:
		return
	if show_colliders:
		for node in rig.all_colliders():
			var collider := node.to_collider()
			debug.capsule(
				collider.point_a, collider.point_b, collider.radius, Color(0.35, 0.75, 1.0, 0.22)
			)
	if not show_chains:
		return
	for modifier in all_chains():
		if not modifier.active:
			continue
		debug.polyline(modifier.reconstructed, Color(1.0, 1.0, 1.0, 0.5))
		var chain := modifier.chain
		for i in chain.positions.size():
			var normal: Vector3 = chain.contact_normals[i]
			if normal.length_squared() < 0.000001:
				debug.cross_mark(chain.positions[i], 0.008, JiggleDebugDraw.COLOR_ACTUAL)
				continue
			debug.sphere(chain.positions[i], 0.012, COLOR_CONTACT, 8)


# --- 그래프 · 정보 -------------------------------------------------------------


func sample_plot() -> Dictionary:
	var sample := {}
	if not breast_modifiers.is_empty():
		sample["breast"] = rad_to_deg(breast_modifiers[0].swing_angle)
	sample["hair"] = _tip_drift(_hair_probe) * 100.0
	sample["skirt"] = _tip_drift(_skirt_probe) * 100.0
	return sample


## 사슬 끝점이 rest 자리에서 얼마나 벗어나 있는지(m).
func _tip_drift(modifier: JiggleChainModifier3D) -> float:
	if modifier == null or not modifier.active:
		return 0.0
	var chain := modifier.chain
	var tip := chain.positions.size() - 1
	if tip < 0 or chain.rest_positions.size() <= tip:
		return 0.0
	return chain.positions[tip].distance_to(chain.rest_positions[tip])


func get_plot_series() -> Array[Dictionary]:
	return [
		{"id": "breast", "color": Color(1.0, 0.55, 0.72)},
		{"id": "hair", "color": Color(0.55, 0.78, 1.0)},
		{"id": "skirt", "color": Color(0.55, 0.95, 0.62)},
	]


func get_plot_info() -> String:
	if rig != null and rig.model_missing:
		return "%s 가 없다 — 모델을 넣으면 이 데모가 동작한다" % CharacterRig.MODEL
	if rig == null or rig.skeleton == null:
		return "모델을 불러오지 못했다"
	var active := 0
	for modifier in all_chains():
		if modifier.active:
			active += 1
	return "가슴 휨°(분홍) · 머리카락 변위cm(파랑) · 치마 변위cm(초록)   |   사슬 %d/%d 가동 · %.2f ms" % [
		active, all_chains().size(), _total_usec * 0.001
	]


func smoke_check() -> String:
	# 모델 파일이 없는 것은 코드 문제가 아니다. 검사를 통째로 실패시키지 않는다.
	if rig != null and rig.model_missing:
		return ""
	if rig == null or rig.skeleton == null:
		return "캐릭터 리그를 만들지 못했다"
	if breast_modifiers.is_empty():
		return "가슴 본을 못 찾았다"
	if hair_modifiers.is_empty() or skirt_modifiers.is_empty():
		return "머리카락 %d 가닥 · 치마 %d 가닥 — 사슬을 못 찾았다" % [
			hair_modifiers.size(), skirt_modifiers.size()
		]
	for modifier in all_chains():
		for position in modifier.chain.positions:
			if not (is_finite(position.x) and is_finite(position.y) and is_finite(position.z)):
				return "%s 의 파티클이 NaN/무한대" % modifier.name
	return ""


func all_chains() -> Array[JiggleChainModifier3D]:
	var all: Array[JiggleChainModifier3D] = []
	all.append_array(hair_modifiers)
	all.append_array(skirt_modifiers)
	all.append_array(ribbon_modifiers)
	return all


func _longest(
	modifiers: Array[JiggleChainModifier3D], infos: Array[Dictionary]
) -> JiggleChainModifier3D:
	var best: JiggleChainModifier3D = null
	var best_length := -1.0
	for i in mini(modifiers.size(), infos.size()):
		var length: float = infos[i]["length"]
		if length > best_length:
			best_length = length
			best = modifiers[i]
	return best


func get_camera_focus() -> Vector3:
	return _focus


func get_camera_distance() -> float:
	return _height * 1.9


func get_demo_title() -> String:
	return "09 · 실제 캐릭터 (모디파이어 적용)"


func get_demo_description() -> String:
	return """[b]밖에서 가져온 Rigify 캐릭터(본 183개)에 앞 데모의 모디파이어를 그대로 붙인 것이다.[/b] 새로 만든 시뮬레이션 코드는 한 줄도 없다 — 리그에 맞게 [i]설정[/i]만 했다.
가슴 2 · 머리카락 17 · 치마 12 · 리본 8가닥을 [code]JiggleBoneModifier3D[/code] 와 [code]JiggleChainModifier3D[/code] 가 흔들고, 머리·골반·허벅지 충돌체는 [code]BoneAttachment3D[/code] 아래 [code]JiggleCollider3D[/code] 로 붙어 본을 따라다닌다. 재질은 [b]소재별로 여섯 개[/b] — 머리카락 · 치마 · 리본 4종이다.
[color=#8ab4ff]해볼 것[/color]  ① [b]치마 모양 유지[/b]를 0으로 내린다(프리셋 "모양 유지 끔") → 치맛자락이 [b]축 늘어진 밧줄 12가닥[/b]이 된다. 거리 제약은 길이만, 각도 제한은 한계각만 지킬 뿐 [b]그 사이의 모양은 아무도 안 지킨다[/b]. 두께가 있는 천·리본에는 이 값이 필요하다.
② [b]충돌[/b]을 끈다 → 치맛자락이 허벅지를 통과한다. 단, 모양 유지가 켜져 있으면 치마가 다리 근처까지 가지도 않아 차이가 안 보인다(그래서 위 프리셋은 둘 다 끈다).
③ [b]치마 각도 제한[/b]을 0으로 내리고 급정거 자극을 준다 → 치맛자락이 자기 위로 접히며 메쉬가 뒤집힌다.
④ [b]치마 반복 횟수[/b]를 1로 내린다 → 가닥이 고무줄처럼 늘어난다. 12로 올리면 즉시 뻣뻣해지고 ms 표시가 같이 오른다. [b]반복 횟수 = 뻣뻣함 = 비용[/b]. (모양 유지는 반복 횟수로 나눠 두어 이 값에 안 휘둘린다.)
⑤ [b]모델 보기[/b]를 끄고 [b]사슬 표시[/b]를 켠다 → 본이 실제로 어떻게 움직이는지 그대로 보인다.
⑥ [b]가슴 좌우 강성 배율[/b]을 0.3으로 → 좌우로만 크게 흔들린다. 1.5로 올리면 위아래로만 움직인다.
[color=#ffb060]리그에서 실제로 달랐던 것[/color]  이 리그는 본이 [b]로컬 +Y[/b] 를 향한다(자작 리그는 단위행렬이라 +Z였다). [code]tip_axis[/code] 를 안 고치면 가슴이 엉뚱한 방향으로 눕는다. 축은 추측하지 말고 [code]tools/inspectrig.gd[/code] 로 찍어 볼 것.
그리고 리그에는 [b]이름이 틀린 본[/b]이 있다 — 앞리본 왼쪽 뿌리만 [code]Back[/code] 이다. 이름 규칙으로는 안 잡혀 그 한 가닥이 조용히 빠진다. 예외 표([code]CharacterRig.MISNAMED_BONES[/code])로 잡아 준다."""


func get_param_labels() -> Dictionary:
	return {
		&"show_debug": "디버그 표시",
		&"breast_enabled": "가슴 흔들림",
		&"breast_tip_length": "가슴 팔 길이 (m)",
		&"breast_frequency": "가슴 진동수 (Hz)",
		&"breast_damping": "가슴 감쇠비",
		&"breast_gravity": "가슴 중력(연출)",
		&"breast_max_angle": "가슴 최대 각도",
		&"breast_vertical_ratio": "가슴 상하 강성 배율",
		&"breast_horizontal_ratio": "가슴 좌우 강성 배율",
		&"breast_squash": "가슴 스쿼시",
		&"hair_enabled": "머리카락",
		&"ribbon_enabled": "리본",
		&"ribbon_shape_scale": "리본 모양 유지 배율",
		&"hair_iterations": "머리 반복 횟수",
		&"hair_constraint_stiffness": "머리 거리 제약 강도",
		&"hair_shape_stiffness": "머리 모양 유지",
		&"hair_shape_elasticity": "머리 모양 탄성",
		&"hair_restore_frequency": "머리 복원 진동수 (Hz)",
		&"hair_drag": "머리 공기 저항",
		&"hair_angle_limit": "머리 각도 제한",
		&"hair_gravity": "머리 중력",
		&"hair_particle_radius": "머리 파티클 두께",
		&"skirt_enabled": "치마",
		&"skirt_iterations": "치마 반복 횟수",
		&"skirt_constraint_stiffness": "치마 거리 제약 강도",
		&"skirt_shape_stiffness": "치마 모양 유지",
		&"skirt_shape_elasticity": "치마 모양 탄성",
		&"skirt_restore_frequency": "치마 복원 진동수 (Hz)",
		&"skirt_drag": "치마 공기 저항",
		&"skirt_angle_limit": "치마 각도 제한",
		&"skirt_gravity": "치마 중력",
		&"skirt_particle_radius": "치마 파티클 두께",
		&"collision_enabled": "충돌",
		&"collider_scale": "충돌체 크기 배율",
		&"collision_friction": "충돌 마찰",
		&"stimulus_speed": "자극 속도",
		&"stimulus_amount": "자극 세기",
		&"show_model": "모델 보기",
		&"show_colliders": "충돌체 표시",
		&"show_chains": "사슬 표시",
	}


func get_presets() -> Dictionary:
	return {
		# adachi_rigged4_jiggle.tscn 을 에디터에서 눈으로 맞춘 값이다.
		"기본": {
			&"breast_tip_length": 0.18,
			&"breast_frequency": 2.4,
			&"breast_damping": 1.0,
			&"breast_gravity": 3.0,
			&"breast_max_angle": 100.0,
			&"breast_vertical_ratio": 0.2,
			&"breast_horizontal_ratio": 1.0,
			&"breast_squash": 0.0,
			&"hair_iterations": 6,
			&"hair_constraint_stiffness": 0.10,
			&"hair_shape_stiffness": 0.45,
			&"hair_drag": 0.50,
			&"hair_restore_frequency": 0.59,
			&"hair_angle_limit": 45.0,
			&"hair_particle_radius": 0.012,
			&"skirt_iterations": 8,
			&"skirt_constraint_stiffness": 1.0,
			&"skirt_shape_stiffness": 0.50,
			&"skirt_drag": 0.30,
			&"skirt_restore_frequency": 0.7,
			&"skirt_angle_limit": 30.0,
			&"skirt_particle_radius": 0.02,
			&"ribbon_shape_scale": 1.0,
			&"collision_enabled": true,
			&"collider_scale": 1.0,
		},
		# 실측으로 고른 값이다 (tools/material_sweep.gd).
		# 기본 대비 진폭 0.213→0.145 · 왕복 7→4 · 정착 0.27→0.12s.
		"뻣뻣한 천 (덜 탄력적)": {
			&"skirt_drag": 0.15,
			&"skirt_shape_stiffness": 0.60,
			&"skirt_angle_limit": 22.0,
			&"hair_drag": 0.08,
			&"hair_shape_stiffness": 0.30,
			&"hair_angle_limit": 25.0,
			&"breast_damping": 0.45,
		},
		"차분하게": {
			&"breast_frequency": 3.2,
			&"breast_damping": 0.45,
			&"breast_squash": 0.05,
			&"hair_restore_frequency": 1.8,
			&"hair_drag": 0.08,
			&"skirt_restore_frequency": 1.6,
			&"skirt_drag": 0.10,
		},
		"과장되게": {
			&"breast_frequency": 1.8,
			&"breast_damping": 0.10,
			&"breast_gravity": 5.0,
			&"breast_squash": 0.35,
			&"hair_restore_frequency": 0.4,
			&"hair_drag": 0.015,
			&"skirt_restore_frequency": 0.3,
			&"skirt_drag": 0.02,
			&"stimulus_amount": 1.6,
		},
		"모양 유지 끔 (밧줄)": {
			&"hair_shape_stiffness": 0.0,
			&"skirt_shape_stiffness": 0.0,
			&"ribbon_shape_scale": 0.0,
		},
		"충돌 끔 (통과 확인)": {
			&"collision_enabled": false,
			&"hair_shape_stiffness": 0.0,
			&"skirt_shape_stiffness": 0.0,
			&"ribbon_shape_scale": 0.0,
			&"show_chains": true,
		},
		"가벼운 설정 (비용)": {
			&"hair_iterations": 3,
			&"skirt_iterations": 3,
			&"ribbon_enabled": false,
		},
	}
