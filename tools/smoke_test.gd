extends SceneTree

## 헤드리스 회귀 검사.
##
## [codeblock]
## godot --headless --path <프로젝트> --script tools/smoke_test.gd
## [/codeblock]
##
## 모든 데모를 [b]모든 프리셋 × 모든 자극[/b] 조합으로 잠깐씩 돌려 보고,
## 위치가 NaN/무한대가 되거나 터무니없이 멀리 날아가지 않았는지 확인한다.
##
## Jiggle은 "보기에 좋은가"를 자동으로 판정할 수 없다. 대신 [b]터지지 않았는가[/b]는
## 자동으로 확인할 수 있고, 실제로 스프링 코드에서 나는 사고는 거의 전부 그쪽이다.

const DEMO_PATHS: Array[String] = [
	"res://demos/01_spring_basics/spring_basics_demo.gd",
	"res://demos/02_jiggle_bone/jiggle_bone_demo.gd",
	"res://demos/03_bone_chain/bone_chain_demo.gd",
	"res://demos/04_cloth/cloth_demo.gd",
	"res://demos/05_builtin_springbone/spring_bone_compare_demo.gd",
	"res://demos/06_builtin_softbody/soft_body_compare_demo.gd",
	"res://demos/07_physical_bones/physical_bone_compare_demo.gd",
	"res://demos/08_shader_jiggle/shader_jiggle_demo.gd",
	"res://demos/09_real_character/real_character_demo.gd",
]
const FRAMES_PER_CASE := 90
const IMPULSE_EVERY := 25
const DISTANCE_LIMIT := 100.0


func _initialize() -> void:
	print("=== Jiggle 스모크 테스트 ===")
	var runner := Runner.new()
	runner.demo_paths = DEMO_PATHS
	runner.frames_per_case = FRAMES_PER_CASE
	root.add_child(runner)


class Runner:
	extends Node

	var demo_paths: Array[String] = []
	var frames_per_case := 90

	var _cases: Array[Dictionary] = []
	var _case_index := -1
	var _frames := 0
	var _demo: JiggleDemo = null
	var _failures: PackedStringArray = PackedStringArray()
	var _checked := 0

	func _ready() -> void:
		for path in demo_paths:
			var script: GDScript = load(path)
			var probe := script.new() as JiggleDemo
			var presets := probe.get_presets()
			var unstable := probe.get_unstable_presets()
			var names: Array = presets.keys() if not presets.is_empty() else [""]
			probe.free()
			for preset_name: String in names:
				# 일부러 발산시키는 프리셋은 검사 대상이 아니다.
				if unstable.has(preset_name):
					continue
				for kind in Stimulus.Kind.values():
					_cases.append({"path": path, "preset": preset_name, "kind": kind})
		print("검사할 조합: %d 개" % _cases.size())
		_next_case()

	func _process(_delta: float) -> void:
		if _demo == null:
			return
		_frames += 1
		if _frames % IMPULSE_EVERY == 0:
			_demo.trigger_impulse()
		var problem := _inspect()
		if not problem.is_empty():
			_fail(problem)
			_next_case()
			return
		if _frames >= frames_per_case:
			var self_check := _demo.smoke_check()
			if not self_check.is_empty():
				_fail(self_check)
			_next_case()

	func _next_case() -> void:
		if _demo != null:
			_demo.queue_free()
			_demo = null
		_case_index += 1
		if _case_index >= _cases.size():
			_report()
			return
		var case: Dictionary = _cases[_case_index]
		var script: GDScript = load(case["path"])
		_demo = script.new() as JiggleDemo
		add_child(_demo)
		if not String(case["preset"]).is_empty():
			_demo.apply_preset(case["preset"])
		_demo.set_stimulus_kind(case["kind"])
		_frames = 0

	func _inspect() -> String:
		_checked += 1
		return _scan(_demo)

	## 씬 전체를 훑어 좌표가 유한하고 상식적인 범위인지 확인한다.
	func _scan(node: Node) -> String:
		var spatial := node as Node3D
		if spatial != null:
			var origin := spatial.global_transform.origin
			if not _is_finite(origin):
				return "%s 의 위치가 NaN/무한대" % spatial.name
			if origin.length() > DISTANCE_LIMIT:
				return "%s 가 %.0fm 밖으로 날아감" % [spatial.name, origin.length()]
		var skeleton := node as Skeleton3D
		if skeleton != null:
			for bone in skeleton.get_bone_count():
				var pose := skeleton.get_bone_global_pose(bone).origin
				if not _is_finite(pose):
					return "본 %s 의 포즈가 NaN/무한대" % skeleton.get_bone_name(bone)
				if pose.length() > DISTANCE_LIMIT:
					return "본 %s 가 %.0fm 밖으로 날아감" % [
						skeleton.get_bone_name(bone), pose.length()
					]
		for child in node.get_children():
			var problem := _scan(child)
			if not problem.is_empty():
				return problem
		return ""

	func _fail(message: String) -> void:
		var case: Dictionary = _cases[_case_index]
		var label := "%s [%s / 자극 %d]" % [
			String(case["path"]).get_file(), case["preset"], case["kind"]
		]
		_failures.append("%s → %s" % [label, message])
		printerr("  실패: %s → %s" % [label, message])

	func _report() -> void:
		print("검사한 프레임: %d" % _checked)
		if _failures.is_empty():
			print("결과: 통과 — 모든 조합에서 발산·NaN 없음")
			get_tree().quit(0)
			return
		print("결과: 실패 %d 건" % _failures.size())
		for failure in _failures:
			print("  - ", failure)
		get_tree().quit(1)

	static func _is_finite(value: Vector3) -> bool:
		return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)
