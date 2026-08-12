extends SceneTree

## [b]어느 손잡이가 무엇을 바꾸는가[/b] — 재질감 파라미터 실측표.
##
## [codeblock]
## godot --headless --path <프로젝트> --script tools/material_sweep.gd
## [/codeblock]
##
## "너무 고무 같다"와 "너무 많이 휜다"는 [b]다른 증상이고 손잡이도 다르다.[/b]
## 그런데 둘 다 "뻣뻣하게 하고 싶다"는 말로 표현되기 때문에 엉뚱한 값을 만지기 쉽다.
##
## 그래서 파라미터를 하나씩만 바꿔 가며 세 가지를 잰다.
## [codeblock]
## 진폭    얼마나 많이 휘는가        (크면 흐물흐물)
## 왕복    몇 번 되돌아오는가        (많으면 고무·스프링 같다)
## 정착    멈추는 데 걸리는 시간     (길면 계속 출렁인다)
## [/codeblock]
##
## [b]측정 방법[/b] — 좌우로 흔들어 충분히 여기시킨 뒤 자극을 [b]0으로 끊고[/b]
## 그때부터의 잔향(ring-down)을 본다. 자극이 계속 들어오면 감쇠를 잴 수 없다.

const DEMO := "res://demos/09_real_character/real_character_demo.gd"
const EXCITE_FRAMES := 90
const MEASURE_FRAMES := 150
## 잔향을 재려면 프레임 간격이 일정해야 한다. 헤드리스는 기본이 무제한이라 고정한다.
const FIXED_FPS := 60

## [b]계측기의 기준선은 고정한다.[/b]
##
## 데모 기본값을 그대로 쓰면 데모를 튜닝할 때마다 과거 측정치와 비교가 불가능해진다.
## 실제로 데모 기본값을 바꾸자 같은 표의 숫자가 통째로 달라져 추세가 뒤집힌 적이 있다.
## 여기서 한 번 정해 두면 몇 달 뒤에 돌려도 같은 표가 나온다.
const BASELINE := {
	&"skirt_drag": 0.05,
	&"skirt_shape_stiffness": 0.40,
	&"skirt_shape_elasticity": 0.0,
	&"skirt_restore_frequency": 0.7,
	&"skirt_angle_limit": 30.0,
	&"skirt_gravity": 9.0,
	&"breast_damping": 0.22,
	&"breast_frequency": 2.4,
	&"breast_gravity": 3.0,
	&"breast_max_angle": 26.0,
}


func _initialize() -> void:
	Engine.max_fps = FIXED_FPS
	print("=== 재질감 파라미터 실측 ===")
	print("좌우 자극으로 여기시킨 뒤 자극을 끊고 잔향을 잰다 (%d fps 고정)" % FIXED_FPS)
	var runner := Runner.new()
	root.add_child(runner)


class Runner:
	extends Node

	## 한 번에 하나씩만 바꾼다. 나머지는 전부 데모 기본값.
	## [b]잔향(release)[/b] — 좌우로 흔들다 자극을 끊고 스스로 멈추는 과정을 본다.
	## 감쇠를 재는 유일한 방법이지만, 풀어준 순간의 변위가 위상에 좌우되므로
	## [b]진폭은 안 찍는다.[/b] 못 믿을 숫자를 표에 넣으면 없느니만 못하다.
	##
	## [b]착지(bounce)[/b] — 점프를 반복시켜 놓고 자극을 끊지 않는다.
	## 구동 자체가 2.5초에 4번 방향을 바꾸므로 [b]왕복이 4를 넘는 만큼이 재질의 떨림[/b]이다.
	## 진폭은 여러 주기의 최대치라 위상에 안 휘둘린다.
	var _sweeps: Array[Dictionary] = [
		{
			"label": "잔향 · 가슴 감쇠비 (damping_ratio)",
			"param": &"breast_damping",
			"values": [0.10, 0.22, 0.45, 0.80],
			"probe": "breast",
		},
		{
			"label": "잔향 · 가슴 진동수",
			"param": &"breast_frequency",
			"values": [1.5, 2.4, 4.0],
			"probe": "breast",
		},
		{
			"label": "잔향 · 치마 공기 저항 (drag)",
			"param": &"skirt_drag",
			"values": [0.01, 0.05, 0.12, 0.25],
		},
		{
			"label": "잔향 · 치마 모양 유지",
			"param": &"skirt_shape_stiffness",
			"values": [0.0, 0.2, 0.4, 0.7],
		},
		# 여기부터는 착지 측정. 힘이 확 들어오는 순간이 진짜 문제다.
		{
			"label": "착지 · 모양 탄성 (모양 유지 0.4 고정)",
			"param": &"skirt_shape_elasticity",
			"values": [0.0, 0.35, 0.7, 1.0],
			"drive": "bounce",
		},
		{
			"label": "착지 · 모양 유지 (탄성 0 고정)",
			"param": &"skirt_shape_stiffness",
			"values": [0.0, 0.2, 0.4, 0.7],
			"drive": "bounce",
		},
		{
			"label": "착지 · 치마 공기 저항 (drag)",
			"param": &"skirt_drag",
			"values": [0.01, 0.05, 0.12, 0.25],
			"drive": "bounce",
		},
		{
			"label": "착지 · 치마 중력",
			"param": &"skirt_gravity",
			"values": [3.0, 9.0, 15.0],
			"drive": "bounce",
		},
		{
			"label": "착지 · 치마 각도 제한",
			"param": &"skirt_angle_limit",
			"values": [10.0, 30.0, 60.0],
			"drive": "bounce",
		},
		{
			"label": "착지 · 치마 복원 진동수",
			"param": &"skirt_restore_frequency",
			"values": [0.0, 0.7, 1.5, 3.0],
			"drive": "bounce",
		},
		# 위 표에서 고른 값을 한꺼번에 적용해 본다. 추천은 재고 나서 해야 한다.
		{
			"label": "착지 · 조합 (0=기본, 1=뻣뻣한 천)",
			"drive": "bounce",
			"combos": [
				{"value": 0.0, "set": {}},
				{
					"value": 1.0,
					"set": {
						&"skirt_drag": 0.15,
						&"skirt_shape_stiffness": 0.60,
						&"skirt_angle_limit": 22.0,
					},
				},
			],
		},
	]

	var _cases: Array[Dictionary] = []
	var _case := -1
	var _demo: RealCharacterDemo = null
	var _frames := 0
	var _release := Vector3.ZERO
	var _signal := PackedFloat32Array()
	var _probe := "skirt"
	var _drive := "release"
	var _results: Array[Dictionary] = []
	## 마지막 몇 프레임의 평균을 평형점으로 본다.
	const TAIL := 20

	func _ready() -> void:
		for sweep: Dictionary in _sweeps:
			var probe: String = sweep.get("probe", "skirt")
			if sweep.has("combos"):
				for combo: Dictionary in sweep["combos"]:
					_cases.append({
						"label": sweep["label"],
						"set": combo["set"],
						"value": combo["value"],
						"probe": probe,
						"drive": sweep.get("drive", "release"),
					})
				continue
			for value: float in sweep["values"]:
				_cases.append({
					"label": sweep["label"],
					"set": {sweep["param"]: value},
					"value": value,
					"probe": probe,
					"drive": sweep.get("drive", "release"),
				})
		_next_case()

	func _process(_delta: float) -> void:
		if _demo == null:
			return
		_frames += 1

		if _frames == EXCITE_FRAMES:
			# 잔향 측정은 자극을 끊는다. 착지 측정은 계속 뛰게 두고 그 위의 떨림을 본다.
			if _drive == "release":
				_demo.stimulus.amount = 0.0
				_demo.stimulus_amount = 0.0
			_release = _offset()
			return
		if _frames <= EXCITE_FRAMES:
			return

		# 처음 벗어난 방향으로 사영해 부호 있는 1차원 신호로 만든다.
		if _release.length_squared() > 0.000001:
			_signal.append(_offset().dot(_release.normalized()))
		if _frames >= EXCITE_FRAMES + MEASURE_FRAMES:
			_finish_case()
			_next_case()

	## 관측 대상이 "흔들림이 없었다면 있었을 자리"에서 벗어난 벡터.
	func _offset() -> Vector3:
		if _probe == "breast":
			if _demo.breast_modifiers.is_empty():
				return Vector3.ZERO
			var modifier := _demo.breast_modifiers[0]
			return modifier.particle_position - modifier.target_position
		if _demo.skirt_modifiers.is_empty():
			return Vector3.ZERO
		var chain := _demo.skirt_modifiers[0].chain
		var tip := chain.positions.size() - 1
		if tip < 1 or chain.rest_positions.size() <= tip:
			return Vector3.ZERO
		return chain.positions[tip] - chain.rest_positions[tip]

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
			printerr("모델을 못 불러왔다")
			get_tree().quit(1)
			return

		# 관측 대상 외에는 꺼서 비용과 잡음을 줄인다.
		_probe = case["probe"]
		_demo.hair_enabled = false
		_demo.ribbon_enabled = false
		_demo.skirt_enabled = _probe == "skirt"
		_demo.breast_enabled = _probe == "breast"
		for key: StringName in BASELINE:
			_demo.set(key, BASELINE[key])
		var overrides: Dictionary = case["set"]
		for key: StringName in overrides:
			_demo.set(key, overrides[key])
		_drive = case["drive"]
		_demo.stimulus_amount = 1.4
		_demo.on_params_changed()
		_demo.set_stimulus_kind(
			Stimulus.Kind.BOUNCE if _drive == "bounce" else Stimulus.Kind.SIDE_STEP
		)

		_frames = 0
		_signal = PackedFloat32Array()
		_release = Vector3.ZERO

	func _finish_case() -> void:
		var case: Dictionary = _cases[_case]
		# [b]평형점을 빼고 잰다.[/b] 중력이 걸린 사슬은 rest 가 아니라 처진 자리에서 멈춘다.
		# 그 상수 오프셋을 안 빼면 "진동이 안 끝난다"는 잘못된 결론이 나온다
		# (실제로 모양 유지 0에서 정착 2.48s 라는 엉뚱한 값이 나왔었다).
		var swing := _detrended()
		_results.append({
			"label": case["label"],
			"value": case["value"],
			# 잔향 측정의 진폭은 "풀어준 순간 어디까지 밀려 있었나"에 좌우된다.
			# 파라미터가 아니라 위상이 정하는 값이라 안 찍는다.
			"진폭": _peak(swing) if _drive == "bounce" else -1.0,
			"왕복": _reversals(swing),
			# 자극을 계속 주는 착지 측정에서는 "멈추는 시간"이라는 개념 자체가 없다.
			"정착": _settle_seconds(swing) if _drive == "release" else -1.0,
			"처짐": _equilibrium(),
		})

	# --- 지표 -----------------------------------------------------------------

	## 잔향 구간의 마지막 평균 = 이 설정에서 결국 멈추는 자리(평형점).
	func _equilibrium() -> float:
		if _signal.is_empty():
			return 0.0
		var count := mini(TAIL, _signal.size())
		var total := 0.0
		for i in range(_signal.size() - count, _signal.size()):
			total += _signal[i]
		return total / float(count)

	## 평형점을 뺀 순수 진동 성분.
	func _detrended() -> PackedFloat32Array:
		var base := _equilibrium()
		var result := PackedFloat32Array()
		result.resize(_signal.size())
		for i in _signal.size():
			result[i] = _signal[i] - base
		return result

	func _peak(values: PackedFloat32Array) -> float:
		var best := 0.0
		for value in values:
			best = maxf(best, absf(value))
		return best

	## 방향이 몇 번 뒤집혔는가. [b]이것이 "고무 같다"의 정체다.[/b]
	## 한 번 밀렸다가 그냥 돌아오면 0~1, 스프링처럼 왕복하면 여러 번 센다.
	## 잡음으로 세는 것을 막으려고 진폭의 5% 이상 움직였을 때만 방향을 갱신한다.
	func _reversals(values: PackedFloat32Array) -> int:
		var deadband := _peak(values) * 0.05
		if deadband < 0.00001 or values.size() < 3:
			return 0
		var count := 0
		var direction := 0
		var anchor: float = values[0]
		for i in range(1, values.size()):
			var change: float = values[i] - anchor
			if absf(change) < deadband:
				continue
			var next_direction := 1 if change > 0.0 else -1
			if direction != 0 and next_direction != direction:
				count += 1
			direction = next_direction
			anchor = values[i]
		return count

	## 진폭의 15% 아래로 내려가 다시는 안 올라온 시점(초).
	func _settle_seconds(values: PackedFloat32Array) -> float:
		var threshold := _peak(values) * 0.15
		if threshold < 0.00001:
			return 0.0
		var last := 0
		for i in values.size():
			if absf(values[i]) > threshold:
				last = i
		return float(last) / float(FIXED_FPS)

	# --- 보고 -----------------------------------------------------------------

	func _report() -> void:
		var current := ""
		for row: Dictionary in _results:
			if row["label"] != current:
				current = row["label"]
				print("\n[%s]" % current)
				print("  %8s %10s %8s %10s %10s" % ["값", "진폭m", "왕복", "정착s", "처짐m"])
			var settle: float = row["정착"]
			var peak: float = row["진폭"]
			print("  %8.2f %10s %8d %10s %10.4f" % [
				row["value"],
				"-" if peak < 0.0 else "%.4f" % peak,
				row["왕복"],
				"-" if settle < 0.0 else "%.2f" % settle,
				row["처짐"],
			])
		print("\n읽는 법  (전부 평형점 기준. 처짐은 평형점 자체가 rest 에서 얼마나 밀렸는지)")
		print("  진폭 ↓ = 덜 휜다      (뻣뻣한 소재)")
		print("  왕복 ↓ = 덜 튕긴다    (고무 느낌이 사라진다)  ← '탄력적이다'의 정체")
		print("  정착 ↓ = 빨리 멈춘다")
		print("  처짐 ↓ = 원래 모양을 유지한다")
		print("  '-' 는 그 측정 방식으로는 의미가 없는 값이라 일부러 안 찍은 것이다")
		print("  착지 측정의 왕복은 구동만으로 4가 나온다. 4를 넘는 만큼이 재질의 떨림이다")
		get_tree().quit(0)
