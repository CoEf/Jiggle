extends SceneTree

## 실제 캐릭터(.glb)에서 모디파이어가 정말로 동작하는지 [b]재는[/b] 검사.
##
## [codeblock]
## godot --headless --path <프로젝트> --script tools/character_test.gd
## [/codeblock]
##
## [code]smoke_test.gd[/code] 는 "안 터졌는가"만 본다. 그런데 흔들림이 아예 [b]0[/b] 이어도
## 터지지는 않는다. 실제로 이 프로젝트에서 내장 [SpringBoneSimulator3D] 의 gravity 단위를
## 잘못 넣어 흔들림이 통째로 사라졌을 때도, 검사는 전부 통과했다.
##
## 그래서 여기서는 [b]조건 하나만 바꿔 실측하고 표로 비교한다.[/b]
## [codeblock]
## ① 정지 vs 걷기          자극이 없으면 안 움직이고, 있으면 움직여야 한다
## ② 그룹별 최대 변위      가슴 · 머리카락 · 치마 · 리본이 각각 살아 있는가
## ③ 충돌 켬 vs 끔         치마가 허벅지를 통과하는가
## ④ tip_axis Y vs Z       리그 축을 틀리면 결과가 달라지는가 (틀려도 안 터진다!)
## ⑤ 비용                  사슬 30가닥이 몇 ms 인가
## [/codeblock]

const DEMO := "res://demos/09_real_character/real_character_demo.gd"
const SETTLE_FRAMES := 30
const MEASURE_FRAMES := 150
## 순간이동 케이스에서 몸을 통째로 옮기는 시점(측정 구간 안). 뒤쪽 프레임이 남아야
## "그래서 어떻게 됐는가"를 잴 수 있으므로 구간 초반에 둔다.
const TELEPORT_FRAME := SETTLE_FRAMES + 40

## [b]기준선을 고정한다.[/b] 데모 기본값을 그대로 쓰면, 데모를 취향대로 튜닝하는 순간
## 이 검사의 비교 조건까지 같이 움직여 엉뚱하게 실패한다(실제로 두 건 겪었다).
##
## 이 검사가 확인하는 것은 [b]모디파이어가 실제 리그에서 동작하는가[/b]이지
## [b]데모 기본값이 예쁜가[/b]가 아니다. 후자는 tools/material_sweep.gd 의 일이다.
##
## 값은 "각 비교가 실제로 일을 하는" 조건으로 골랐다 —
## 예를 들어 치마 drag 를 낮게 둬야 치맛자락이 다리까지 와서 충돌 비교가 성립한다.
##
## [b]재질값은 하나도 빠짐없이 여기서 고정한다.[/b] 데모 기본값에 기대어 비워 둔 값이 있으면
## 그 값만 조용히 따라 움직인다 — 데모 기본 복원 진동수를 0.9 에서 0.59 로 내렸을 때
## 여기 없던 [code]hair_restore_frequency[/code] 가 같이 내려가 "정지 상태인데 안 멈춘다"로
## 터졌다(세 번째다).
const BASELINE := {
	&"hair_iterations": 6,
	&"hair_constraint_stiffness": 1.0,
	# 탄성 0에서는 모양 유지를 0.8 이상 줘야 제 몫을 한다.
	# 0.2~0.4 는 오히려 안 준 것보다 처짐이 클 수 있다(실측).
	&"hair_shape_stiffness": 0.85,
	&"hair_shape_elasticity": 0.0,
	&"hair_drag": 0.03,
	&"hair_restore_frequency": 0.9,
	&"hair_angle_limit": 35.0,
	&"hair_gravity": 9.0,
	&"hair_particle_radius": 0.012,
	&"skirt_iterations": 8,
	&"skirt_constraint_stiffness": 1.0,
	&"skirt_shape_stiffness": 0.85,
	&"skirt_shape_elasticity": 0.0,
	&"skirt_drag": 0.05,
	&"skirt_restore_frequency": 0.7,
	&"skirt_angle_limit": 30.0,
	&"skirt_gravity": 9.0,
	&"skirt_particle_radius": 0.012,
	&"collider_scale": 1.0,
	&"collision_friction": 0.2,
}


## [b]프레임 간격을 고정한다.[/b] 헤드리스는 기본이 무제한이라 프레임마다 delta 가 다르고,
## 그러면 같은 프레임 수를 돌려도 [b]흘러간 시뮬레이션 시간이 매번 달라진다.[/b]
##
## 이걸 안 걸어 두면 "치맛자락이 그 150프레임 안에 허벅지까지 왔는가"가 운에 좌우되어
## 충돌 검사가 [b]4번 중 2번 실패[/b]했다(실측: 파고듦이 0.0000 / 0.0013 / 0.0151 로 튐).
## 회귀 검사가 흔들리면 없는 버그를 쫓게 되므로, 재현성이 정확도보다 먼저다.
const FIXED_FPS := 60


func _initialize() -> void:
	Engine.max_fps = FIXED_FPS
	print("=== 실제 캐릭터 검사 === (%d fps 고정)" % FIXED_FPS)
	var runner := Runner.new()
	root.add_child(runner)


class Runner:
	extends Node

	var _demo: RealCharacterDemo = null
	var _case := -1
	var _frames := 0
	var _peak := {}
	var _worst_penetration := 0.0
	var _rest_embed := 0.0
	var _axis_error := 0.0
	var _late_motion := 0.0
	var _safety_resets := 0
	var _previous_tips := PackedVector3Array()
	var _usec_sum := 0.0
	var _usec_count := 0
	var _results: Array[Dictionary] = []
	var _failures: PackedStringArray = PackedStringArray()

	# 조건 하나씩만 바꾼다. 그게 이 프로젝트가 결론을 내는 유일한 방식이다.
	var _cases: Array[Dictionary] = [
		{"name": "정지", "stimulus": Stimulus.Kind.IDLE},
		{"name": "걷기", "stimulus": Stimulus.Kind.WALK},
		{"name": "급정거", "stimulus": Stimulus.Kind.SHOCK},
		{"name": "걷기 · 축 틀림(Z)", "stimulus": Stimulus.Kind.WALK, "wrong_axis": true},
		# 정지 상태의 처짐은 버그가 아니라 평형점 이동이다. 복원 강성을 올리면 줄어야 한다.
		# sag ≈ g / k,  k = (2π·f)²  이므로 f 를 2배로 하면 처짐은 1/4 이 되어야 한다.
		{"name": "정지 · 복원 2배", "stimulus": Stimulus.Kind.IDLE, "restore_scale": 2.0},
		# 모양 유지를 빼면 축 늘어진 밧줄이 된다. 처짐이 확 늘어야 정상이다.
		{"name": "정지 · 모양 끔", "stimulus": Stimulus.Kind.IDLE, "shape": 0.0},
		# 탄성을 0으로 내리면 되돌리는 힘이 속도를 못 만든다. 그만큼 덜 되돌아오므로
		# [b]처짐이 늘어날 수 있다.[/b] 얼마나 손해인지 재 둔다.
		{"name": "정지 · 모양 탄성 1", "stimulus": Stimulus.Kind.IDLE, "elasticity": 1.0},
		# 탄성으로 벌던 처짐 저항을 [b]모양 유지를 올려서[/b] 되찾을 수 있는지 본다.
		{"name": "정지 · 모양 0.7", "stimulus": Stimulus.Kind.IDLE, "shape": 0.7},
		{"name": "정지 · 모양 0.9", "stimulus": Stimulus.Kind.IDLE, "shape": 0.9},
		# --- 충돌 비교 쌍 ---
		# 모양 유지를 켜 두면 치마가 rest 모양을 지켜 다리 근처까지 가지도 않는다.
		# 그래서 충돌을 껐다 켜도 아무 차이가 안 난다. 충돌이 [b]일하는 조건[/b]을
		# 만들어 놓고(모양 유지 끔 = 치마가 다리로 무너짐) 충돌만 바꿔야 비교가 성립한다.
		# 충돌체를 키워 [b]확실히 치맛자락 경로 안에[/b] 두고 충돌만 껐다 켠다.
		# 기본 크기에서는 모양 유지를 꺼도 치마가 다리에 거의 안 닿아서
		# "충돌이 막고 있었다"를 증명할 수 없다(⑮).
		{
			"name": "걷기 · 모양 끔 · 충돌체 2배",
			"stimulus": Stimulus.Kind.WALK,
			"shape": 0.0,
			"collider_scale": 2.0,
		},
		{
			"name": "걷기 · 모양+충돌 끔 · 충돌체 2배",
			"stimulus": Stimulus.Kind.WALK,
			"shape": 0.0,
			"collision": false,
			"collider_scale": 2.0,
		},
		# --- 순간이동 3종 ---
		# 파티클이 월드 공간에 있어서 관성이 공짜로 생기는데, 대가로 몸이 순간이동하면
		# 사슬만 제자리에 남는다. 아무 손잡이도 안 주면 rest 에서 5m 벗어나
		# safety_radius 가 통째로 되돌린다 — [b]터지지는 않지만 그건 고친 게 아니다.[/b]
		{"name": "순간이동", "stimulus": Stimulus.Kind.IDLE, "teleport": 5.0},
		{
			"name": "순간이동 · 문턱 1m",
			"stimulus": Stimulus.Kind.IDLE,
			"teleport": 5.0,
			"teleport_threshold": 1.0,
		},
		# 문턱과 달리 motion_inherit 은 늘 조금씩 따라간다. 순간이동에는 부분적으로만 듣는다 —
		# 두 손잡이가 서로 다른 일을 한다는 것을 보이려고 같이 잰다.
		{
			"name": "순간이동 · 관성 계승 0.5",
			"stimulus": Stimulus.Kind.IDLE,
			"teleport": 5.0,
			"motion_inherit": 0.5,
		},
	]

	func _ready() -> void:
		_next_case()

	func _process(_delta: float) -> void:
		if _demo == null:
			return
		_frames += 1
		# 몸을 통째로 한 프레임에 옮긴다. 데모 자신은 rig.transform 만 건드리므로
		# 데모 노드를 옮기면 자극과 안 섞인 순수한 순간이동이 된다.
		var case: Dictionary = _cases[_case]
		if _frames == TELEPORT_FRAME and case.has("teleport"):
			_demo.position += Vector3.RIGHT * float(case["teleport"])
		if _frames <= SETTLE_FRAMES:
			return
		_accumulate()
		if _frames >= SETTLE_FRAMES + MEASURE_FRAMES:
			_finish_case()
			_next_case()

	# --- 측정 -----------------------------------------------------------------

	func _accumulate() -> void:
		_track("가슴", rad_to_deg(_max_breast_swing()))
		_track("머리카락", _max_drift(_demo.hair_modifiers))
		_track("치마", _max_drift(_demo.skirt_modifiers))
		_track("리본", _max_drift(_demo.ribbon_modifiers))

		var total := 0
		for modifier in _demo.all_chains():
			total += modifier.last_usec
		_usec_sum += float(total)
		_usec_count += 1

		_worst_penetration = maxf(_worst_penetration, _max_penetration())
		_rest_embed = maxf(_rest_embed, _measure_rest_embed())
		_axis_error = maxf(_axis_error, _measure_axis_error())
		_measure_motion()
		_safety_resets = _count_safety_resets()

	## 안전장치가 사슬을 rest 로 되돌린 횟수(전 사슬 합).
	##
	## [b]0이 아니면 시뮬레이션이 조용히 터지고 있다는 뜻이다.[/b] 변위로는 안 잡힌다 —
	## 재는 시점에는 이미 rest 로 복구된 뒤라 오히려 [b]더 얌전한 숫자[/b]가 나온다.
	## 순간이동 문제를 이 열 없이는 볼 수가 없어서 따로 뺐다.
	func _count_safety_resets() -> int:
		var total := 0
		for modifier in _demo.all_chains():
			total += modifier.chain.safety_resets
		return total

	## 프레임 사이에 끝점이 얼마나 움직였는지. 마지막 구간에서만 본다.
	##
	## [b]정지 상태에서 재야 할 것은 "rest 에서 얼마나 벗어났는가"가 아니라 "멈췄는가"다.[/b]
	## 중력이 있으면 평형점은 당연히 rest 에서 g/k 만큼 옮겨간다 — 그건 버그가 아니라 설계다.
	func _measure_motion() -> void:
		var tips := PackedVector3Array()
		for modifier in _demo.all_chains():
			var chain := modifier.chain
			var tip := chain.positions.size() - 1
			tips.append(chain.positions[tip] if tip >= 0 else Vector3.ZERO)
		if _previous_tips.size() == tips.size() and _frames > SETTLE_FRAMES + MEASURE_FRAMES / 2:
			for i in tips.size():
				_late_motion = maxf(_late_motion, tips[i].distance_to(_previous_tips[i]))
		_previous_tips = tips

	## [b]rest 자세가 충돌체에 파묻힌 정도.[/b] 0보다 크면 파라미터로는 절대 못 고친다 —
	## 충돌체를 줄이거나 리그를 고쳐야 한다. 이 프로젝트에서 가장 오래 헤맸던 종류의 문제다.
	func _measure_rest_embed() -> float:
		var worst := 0.0
		for modifier in _demo.all_chains():
			var chain := modifier.chain
			for collider in chain.colliders:
				for i in range(1, chain.rest_positions.size()):
					var point := chain.rest_positions[i]
					worst = maxf(
						worst, collider.radius - point.distance_to(collider.closest_point(point))
					)
		return worst

	## [b]tip_axis 가 리그와 맞는지 직접 검증한다.[/b]
	##
	## 모디파이어가 믿는 tip 방향(target_position - bone_origin)과
	## 실제 자식 본이 있는 방향 사이의 각도. 축이 맞으면 0°에 가깝다.
	## 축이 틀려도 [b]에러는 하나도 안 난다[/b] — 그래서 이렇게 재야만 알 수 있다.
	##
	## [b]순간이동한 프레임에는 재지 않는다.[/b] [code]bone_origin[/code] 은 모디파이어가
	## 지난번 돈 시점의 값이고 [code]bone_world()[/code] 는 지금 값이라, 몸이 5m 튄 프레임에는
	## 둘이 [b]다른 좌표계의 값[/b]이 된다. 그러면 축이 멀쩡해도 89.7° 가 찍힌다.
	## 실제로 한 번 찍혔고, 표만 보면 축이 틀어진 것처럼 읽힌다 — 3-⑩ 과 같은 종류의 함정이다.
	## [b]서로 다른 시점의 값을 비교하면 그건 "틀렸다"가 아니라 "잴 수 없다"이다.[/b]
	func _measure_axis_error() -> float:
		if _frames >= TELEPORT_FRAME and _frames <= TELEPORT_FRAME + 1:
			return 0.0
		var worst := 0.0
		for modifier in _demo.breast_modifiers:
			var believed := modifier.target_position - modifier.bone_origin
			var actual := _demo.rig.bone_world("%s.001" % modifier.bone_name) - modifier.bone_origin
			if believed.length_squared() < 0.000001 or actual.length_squared() < 0.000001:
				continue
			worst = maxf(worst, rad_to_deg(believed.angle_to(actual)))
		return worst

	func _track(key: String, value: float) -> void:
		if value > float(_peak.get(key, 0.0)):
			_peak[key] = value

	func _max_breast_swing() -> float:
		var best := 0.0
		for modifier in _demo.breast_modifiers:
			best = maxf(best, modifier.swing_angle)
		return best

	## 사슬 끝점이 rest 자리에서 가장 많이 벗어난 거리(m).
	func _max_drift(modifiers: Array[JiggleChainModifier3D]) -> float:
		var best := 0.0
		for modifier in modifiers:
			var chain := modifier.chain
			var tip := chain.positions.size() - 1
			if tip < 1 or chain.rest_positions.size() <= tip:
				continue
			best = maxf(best, chain.positions[tip].distance_to(chain.rest_positions[tip]))
		return best

	## 치마 파티클이 허벅지·골반 캡슐 안으로 얼마나 파고들었는지(m).
	## 충돌이 켜져 있으면 0에 가까워야 하고, 끄면 눈에 띄게 커져야 한다.
	func _max_penetration() -> float:
		var worst := 0.0
		for modifier in _demo.skirt_modifiers:
			var chain := modifier.chain
			for node in _demo.rig.all_colliders():
				var collider := node.to_collider()
				# 뿌리(0번)는 스켈레톤이 위치를 정하는 고정점이라 충돌 대상이 아니다.
				for i in range(1, chain.positions.size()):
					var distance := chain.positions[i].distance_to(
						collider.closest_point(chain.positions[i])
					)
					worst = maxf(worst, collider.radius - distance)
		return worst

	# --- 케이스 진행 -----------------------------------------------------------

	func _next_case() -> void:
		if _demo != null:
			_demo.queue_free()
			_demo = null
		_case += 1
		if _case >= _cases.size():
			_report()
			return

		var case: Dictionary = _cases[_case]
		var script: GDScript = load(DEMO)
		_demo = script.new() as RealCharacterDemo
		add_child(_demo)
		if _demo.rig == null or _demo.rig.skeleton == null:
			_failures.append("모델을 못 불러왔다")
			_report()
			return
		if _case == 0:
			_check_group_discovery(_demo.rig)

		for key: StringName in BASELINE:
			_demo.set(key, BASELINE[key])
		if case.has("collision"):
			_demo.collision_enabled = case["collision"]
		if case.has("restore_scale"):
			var scale: float = case["restore_scale"]
			_demo.hair_restore_frequency *= scale
			_demo.skirt_restore_frequency *= scale
		if case.has("shape"):
			_demo.hair_shape_stiffness = case["shape"]
			_demo.skirt_shape_stiffness = case["shape"]
		if case.has("elasticity"):
			_demo.hair_shape_elasticity = case["elasticity"]
			_demo.skirt_shape_elasticity = case["elasticity"]
		if case.has("collider_scale"):
			_demo.collider_scale = case["collider_scale"]
		# 기준 좌표계 손잡이 둘. 재질값이라 리소스에 있다 — 노드에 써 봐야 무시된다.
		if case.has("teleport_threshold"):
			for settings: JiggleChainSettings in [_demo.hair_settings, _demo.skirt_settings]:
				settings.teleport_threshold = case["teleport_threshold"]
		if case.has("motion_inherit"):
			for settings: JiggleChainSettings in [_demo.hair_settings, _demo.skirt_settings]:
				settings.motion_inherit = case["motion_inherit"]
		if case.get("wrong_axis", false):
			# 일부러 축을 틀린다. [b]틀려도 에러 하나 안 난다[/b]는 것이 이 검사의 요점이다.
			for modifier in _demo.breast_modifiers:
				modifier.tip_axis = JiggleBoneModifier3D.TipAxis.Z
			for modifier in _demo.all_chains():
				modifier.tip_axis = Vector3.BACK
			for modifier in _demo.all_chains():
				modifier.reset_simulation()
		_demo.on_params_changed()
		_mirror_hair_onto_ribbons()
		_demo.set_stimulus_kind(case["stimulus"])

		_frames = 0
		_peak = {}
		_worst_penetration = 0.0
		_rest_embed = 0.0
		_axis_error = 0.0
		_late_motion = 0.0
		_safety_resets = 0
		_previous_tips = PackedVector3Array()
		_usec_sum = 0.0
		_usec_count = 0

	func _finish_case() -> void:
		var case: Dictionary = _cases[_case]
		_results.append({
			"name": case["name"],
			"가슴": float(_peak.get("가슴", 0.0)),
			"머리카락": float(_peak.get("머리카락", 0.0)),
			"치마": float(_peak.get("치마", 0.0)),
			"리본": float(_peak.get("리본", 0.0)),
			"파고듦": _worst_penetration,
			"파묻힘": _rest_embed,
			"축오차": _axis_error,
			"잔떨림": _late_motion,
			"복구": _safety_resets,
			"ms": (_usec_sum / maxf(float(_usec_count), 1.0)) * 0.001,
		})

	## 리본 재질 4종을 [b]머리카락과 같은 값[/b]으로 맞춘다.
	##
	## 데모에서 리본은 소재가 넷으로 갈려 있고 슬라이더가 없다(손으로 맞춘 표 값이다).
	## 그대로 두면 리본 열이 [b]케이스 차이가 아니라 소재 차이[/b]를 보여 주게 되어,
	## "모양 유지를 껐는데 리본이 그대로다" 같은 엉뚱한 실패가 난다.
	## 검사 조건은 검사가 정한다 — [constant BASELINE] 과 같은 이유다.
	##
	## [member JiggleChainSettings.SHARED_PROPERTIES] 를 그대로 도는 것이 중요하다.
	## 손으로 나열하면 값이 하나 늘 때마다 [b]리본만 조용히 옛 값을 쓰게[/b] 된다.
	func _mirror_hair_onto_ribbons() -> void:
		for settings: JiggleChainSettings in _demo.ribbon_settings.values():
			for property: String in JiggleChainSettings.SHARED_PROPERTIES:
				settings.set(property, _demo.hair_settings.get(property))

	## [JiggleChainGroup3D] 의 이름 규칙 탐색을 [b]진짜 리그(본 183개)에서[/b] 확인한다.
	##
	## 코드로 만든 리그(데모 01~08)는 곧게 뻗은 몇 마디 한 줄이라
	## [b]탐색이 할 일이 거의 없다.[/b] 갈래지지도 않고, 규칙에 안 맞는 형제도 없다.
	## 이 노드가 실제로 하는 일 — "위쪽이 끊긴 곳을 뿌리로 잡고 한 줄로 이어지는 동안 따라간다" —
	## 은 진짜 리그에서만 시험된다.
	##
	## 기준은 [code]CharacterRig[/code] 다. 같은 알고리즘을 데모가 이미 쓰고 있고,
	## 그쪽은 rigged3 → rigged4 두 벌에 걸쳐 검증된 결과라 비교 대상으로 삼을 만하다.
	func _check_group_discovery(rig: CharacterRig) -> void:
		var expected := {
			"Hair_*": rig.hair_chains,
			"Dress_*": rig.skirt_chains,
			"*Ribbon*": _rule_visible(rig.ribbon_chains),
		}
		var summary := PackedStringArray()
		for pattern: String in expected:
			var group := JiggleChainGroup3D.new()
			group.root_pattern = pattern
			group.tip_axis = CharacterRig.BONE_AXIS
			rig.skeleton.add_child(group)
			var found := group.strands()

			var reference: Array[Dictionary] = expected[pattern]
			summary.append("%s %d/%d" % [pattern, found.size(), reference.size()])
			if found.size() != reference.size():
				_failures.append("그룹 '%s' 이 %d 가닥을 찾았다 (CharacterRig 는 %d 가닥)" % [
					pattern, found.size(), reference.size()
				])
			else:
				# 개수만 같고 다른 가닥을 잡았을 수도 있다. 뿌리·끝 이름까지 맞춰 본다.
				var reference_names := {}
				for info: Dictionary in reference:
					reference_names["%s→%s" % [info["root"], info["end"]]] = true
				for strand: JiggleChainStrand in found:
					var key := "%s→%s" % [strand.root_bone_name, strand.end_bone_name]
					if not reference_names.has(key):
						_failures.append("그룹 '%s' 이 엉뚱한 가닥을 잡았다: %s" % [pattern, key])
						break
			# 프레임이 돌기 전에 뗀다. 이 케이스의 측정에 끼어들면 안 된다.
			rig.skeleton.remove_child(group)
			group.free()
		print("그룹 이름 규칙 탐색(실제 리그): %s" % " · ".join(summary))

	## [b]이름 규칙만으로 잡을 수 있는[/b] 가닥만 남긴다.
	##
	## [CharacterRig] 는 이 리그의 이름 오류를 표로 보정해서 잡지만
	## ([member CharacterRig.MISNAMED_BONES]), 그룹 노드에는 이름 규칙밖에 없어 그 가닥을 못 본다.
	## [b]그건 그룹 노드의 버그가 아니다[/b] — 규칙을 "Back 도 리본"으로 넓히면 다른 리그에서
	## 진짜 등뼈를 잡는다. 여기서 비교할 것은 "규칙이 규칙대로 도는가"뿐이다.
	func _rule_visible(chains: Array[Dictionary]) -> Array[Dictionary]:
		var result: Array[Dictionary] = []
		for info: Dictionary in chains:
			if not CharacterRig.MISNAMED_BONES.has(info["root"]):
				result.append(info)
		return result

	# --- 판정 · 보고 -----------------------------------------------------------

	func _report() -> void:
		if _results.size() == _cases.size():
			_judge()

		print("\n%-24s %7s %9s %7s %7s %8s %8s %7s %8s %5s %6s" % [
			"조건", "가슴°", "머리카락m", "치마m", "리본m", "파고듦m", "파묻힘m", "축오차°",
			"잔떨림m", "복구", "ms"
		])
		for row: Dictionary in _results:
			print("%-24s %7.2f %9.4f %7.4f %7.4f %8.4f %8.4f %7.1f %8.5f %5d %6.2f" % [
				row["name"], row["가슴"], row["머리카락"], row["치마"], row["리본"],
				row["파고듦"], row["파묻힘"], row["축오차"], row["잔떨림"], row["복구"], row["ms"],
			])

		if _failures.is_empty():
			print("\n결과: 통과 — 실제 리그에서 네 그룹 전부 동작")
			get_tree().quit(0)
			return
		print("\n결과: 실패 %d 건" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
		get_tree().quit(1)

	## 이름으로 결과 줄을 찾는다. 인덱스로 집으면 케이스를 하나 끼워 넣을 때마다 조용히 어긋난다.
	func _row(name: String) -> Dictionary:
		for row: Dictionary in _results:
			if row["name"] == name:
				return row
		return {}

	func _judge() -> void:
		var idle := _row("정지")
		var walk := _row("걷기")
		var wrong_axis := _row("걷기 · 축 틀림(Z)")
		var stiff_idle := _row("정지 · 복원 2배")
		var soft_idle := _row("정지 · 모양 끔")
		var soft_walk := _row("걷기 · 모양 끔 · 충돌체 2배")
		var soft_no_collision := _row("걷기 · 모양+충돌 끔 · 충돌체 2배")

		# ⑥ 모양 유지를 빼면 처짐이 커져야 한다. 안 커지면 그 강성이 실제로는 안 걸린 것이다.
		for key: String in ["머리카락", "치마", "리본"]:
			if float(soft_idle[key]) <= float(idle[key]) * 1.05:
				_failures.append(
					"모양 유지를 꺼도 %s 처짐이 안 늘었다 (%.4f → %.4f)"
					% [key, idle[key], soft_idle[key]]
				)
		# 그렇다고 흔들림 자체를 죽이면 안 된다. 모양을 유지하면서도 움직여야 한다.
		#
		# 기준을 "축 늘어진 상태 대비 몇 %"로 잡았다가 걷어냈다. 축 늘어진 치마의 진폭은
		# [b]이상 동작이라 기준이 될 수 없다.[/b] 모양 유지를 제대로 걸수록 그 비율은
		# 당연히 작아지므로, 잘 고칠수록 검사가 실패하는 이상한 지표가 된다.
		# 그냥 절대값으로 묻는다 — 걸을 때 치맛자락이 2cm 는 움직여야 한다.
		if float(walk["치마"]) < 0.02:
			_failures.append(
				"모양 유지가 흔들림까지 죽였다 (걷기 치마 진폭 %.4fm)" % walk["치마"]
			)

		# ⑤ 정지 처짐은 복원 강성으로 조절되는 값이어야 한다.
		# 안 줄어든다면 처짐의 원인이 중력이 아니라 다른 데(충돌·rest 자세)에 있다는 뜻이다.
		if float(stiff_idle["치마"]) >= float(idle["치마"]):
			_failures.append(
				"복원 진동수를 2배로 올려도 치마 처짐이 안 줄었다 (%.4f → %.4f)"
				% [idle["치마"], stiff_idle["치마"]]
			)

		# ① 자극이 없으면 [b]멈춰야[/b] 한다. rest 에서 벗어나는 것 자체는 정상이다 —
		# 중력이 있으면 평형점이 g/k 만큼 옮겨가기 때문이다. 문제는 안 멈추는 것이다.
		# 문턱이 0.002 가 아니라 0.003 인 이유: 이 리그는 [b]앞머리가 머리 충돌체에 닿아 있다.[/b]
		# 공기 저항을 0.03 까지 낮춘 이 검사 조건에서는 접촉면에서 프레임당 0.002m 정도의
		# 떨림이 남는다(모양 유지 0.85 → 0.00205, 0 → 0.00053 으로 모양 힘에 비례한다).
		# 데모 기본값(공기 저항 0.5)에서는 37가닥 전부 0.00000 이다 — 감쇠가 없다시피 한
		# 조건에서만 보이는 접촉 떨림이라 "안 멈춘다"로 볼 값이 아니다.
		if float(idle["잔떨림"]) > 0.003:
			_failures.append("정지 상태인데 안 멈춘다 (프레임당 %.5fm 씩 계속 움직임)" % idle["잔떨림"])
		# rest 자세가 충돌체에 파묻혀 있으면 파라미터로는 못 고친다. 충돌체를 줄여야 한다.
		if float(idle["파묻힘"]) > 0.01:
			_failures.append(
				"rest 자세가 충돌체에 %.4fm 파묻혀 있다 (충돌체 크기 배율을 줄일 것)"
				% idle["파묻힘"]
			)

		# ② 걸으면 네 그룹이 전부 반응해야 한다. 하나라도 0이면 그 그룹은 안 붙은 것이다.
		if float(walk["가슴"]) < 0.5:
			_failures.append("걷는데 가슴이 %.2f° 밖에 안 휜다" % walk["가슴"])
		for key: String in ["머리카락", "치마", "리본"]:
			if float(walk[key]) < 0.005:
				_failures.append("걷는데 %s 변위가 %.4fm 다 (모디파이어가 안 붙었다)" % [
					key, walk[key]
				])

		# ③ 충돌은 [b]충돌이 일하는 조건[/b]에서 비교해야 한다.
		# 모양 유지를 켜 두면 치마가 애초에 다리 근처까지 가지 않아 켜나 끄나 0이 나온다.
		# 그래서 둘 다 모양 유지를 끈 상태에서 충돌만 바꿔 비교한다.
		if float(soft_walk["파고듦"]) > 0.02:
			_failures.append("충돌을 켰는데 치마가 %.4fm 파고든다" % soft_walk["파고듦"])
		if float(soft_no_collision["파고듦"]) <= float(soft_walk["파고듦"]) + 0.005:
			_failures.append(
				"충돌을 꺼도 파고듦이 안 늘었다 (%.4f → %.4f). 충돌체가 안 물렸다"
				% [soft_walk["파고듦"], soft_no_collision["파고듦"]]
			)

		# ⑦ 순간이동. 두 줄이 짝이라 [b]둘 다[/b] 봐야 한다(⑮ — 비교 대상이 일하고 있어야 성립).
		var jump := _row("순간이동")
		var jump_fixed := _row("순간이동 · 문턱 1m")
		# 손잡이를 안 주면 사슬만 제자리에 남아 안전장치가 일한다. 이게 0이 되면
		# 이 검사는 아무것도 안 재고 있는 것이다 — 아래 줄의 "0이어야 한다"도 같이 무의미해진다.
		if int(jump["복구"]) <= 0:
			_failures.append(
				"순간이동 5m 인데 안전장치가 한 번도 안 돌았다 (이 비교가 성립하지 않는다)"
			)
		# 문턱을 주면 통째로 따라가므로 안전장치가 일할 일이 없어야 한다.
		if int(jump_fixed["복구"]) != 0:
			_failures.append(
				"teleport_threshold 를 켰는데 안전장치가 %d 번 돌았다 (순간이동을 못 잡고 있다)"
				% jump_fixed["복구"]
			)
		# 그리고 [b]흔들림까지 죽이면 안 된다.[/b] 순간이동만 흡수하고 평소에는 그대로여야 한다.
		# 정지 처짐이 같은지로 확인한다 — 문턱은 튀는 프레임에만 개입하기 때문이다.
		for key: String in ["머리카락", "치마", "리본"]:
			if not is_equal_approx(float(jump_fixed[key]), float(idle[key])):
				_failures.append(
					"teleport_threshold 가 순간이동 말고 평소 거동까지 바꿨다 (%s %.4f → %.4f)"
					% [key, idle[key], jump_fixed[key]]
				)

		# ④ tip_axis 가 리그와 맞는가. 모디파이어가 믿는 tip 방향이 실제 자식 본 방향과
		# 같아야 한다. [b]틀려도 에러 하나 안 나므로[/b] 이렇게 재는 것 말고는 알 방법이 없다.
		if float(walk["축오차"]) > 5.0:
			_failures.append("tip_axis 가 리그와 %.1f° 어긋난다 (자식 본 방향과 안 맞는다)" % walk["축오차"])
		# 일부러 틀린 축은 반대로 크게 어긋나야 한다. 안 그러면 축 설정이 무시되고 있는 것이다.
		if float(wrong_axis["축오차"]) < 30.0:
			_failures.append(
				"tip_axis 를 Z로 틀었는데 축오차가 %.1f° 뿐이다 (축 설정이 무시된다)"
				% wrong_axis["축오차"]
			)
