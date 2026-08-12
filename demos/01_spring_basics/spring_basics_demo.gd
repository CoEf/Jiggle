class_name SpringBasicsDemo
extends JiggleDemo

## 데모 01 — 스프링-댐퍼 기초
##
## Jiggle의 전부인 단 하나의 식을 눈으로 확인하는 데모.
## 공 세 개가 [b]완전히 같은 목표점[/b]을 쫓지만 감쇠비만 다르다.
## 초록 와이어 구가 "흔들림이 없었다면 있었을 자리"(목표), 노랑 십자가 실제 위치다.

const BALL_RADIUS := 0.085
const BASE_HEIGHT := 1.15
const SPACING := 0.60
const COLORS: Array[Color] = [
	Color(1.00, 0.42, 0.42),
	Color(0.45, 0.95, 0.55),
	Color(0.45, 0.68, 1.00),
]

@export_group("스프링")
## 1초에 몇 번 출렁이는가. 스프링 강성 k = (2*PI*f)^2 로 환산된다.
@export_range(0.2, 8.0, 0.05) var frequency := 2.0
## 왼쪽 공의 감쇠비. 1보다 작으면 출렁인다.
@export_range(0.02, 3.0, 0.01) var zeta_left := 0.12
## 가운데 공의 감쇠비. 정확히 1이면 오버슈트 없이 가장 빨리 멈춘다.
@export_range(0.02, 3.0, 0.01) var zeta_middle := 1.0
## 오른쪽 공의 감쇠비. 1보다 크면 느릿느릿 도착하고 흔들리지 않는다.
@export_range(0.02, 3.0, 0.01) var zeta_right := 2.2

@export_group("적분")
## 같은 방정식이라도 이산화 방식에 따라 결과가 완전히 달라진다.
@export_enum("명시적 오일러 (발산함):0", "반암시적 오일러 (표준):1", "해석적 해 (무조건 안정):2")
var integrator: int = 1
## 시뮬레이션을 1초에 몇 번 계산할지. 낮출수록 dt가 커진다.
@export_enum("15 Hz:15", "30 Hz:30", "60 Hz:60", "120 Hz:120", "240 Hz:240")
var simulation_rate: int = 120

@export_group("힘 · 안전장치")
@export var gravity_enabled := false
## 목표점에서 벗어날 수 있는 최대 거리. 0이면 제한 없음.
@export_range(0.0, 0.8, 0.01) var max_distance := 0.0

var _springs: Array[JiggleSpring] = []
var _balls: Array[MeshInstance3D] = []
var _bases: PackedVector3Array = PackedVector3Array()
var _targets: PackedVector3Array = PackedVector3Array()


func _build() -> void:
	stimulus.kind = Stimulus.Kind.BOUNCE

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6.0, 6.0)
	ground.mesh = plane
	var ground_material := StandardMaterial3D.new()
	ground_material.albedo_color = Color(0.10, 0.11, 0.13)
	ground_material.roughness = 0.95
	ground.material_override = ground_material
	add_child(ground)

	for i in 3:
		var base := Vector3((float(i) - 1.0) * SPACING, BASE_HEIGHT, 0.0)
		_bases.append(base)
		_targets.append(base)

		var ball := MeshInstance3D.new()
		ball.name = "Ball%d" % i
		var sphere := SphereMesh.new()
		sphere.radius = BALL_RADIUS
		sphere.height = BALL_RADIUS * 2.0
		ball.mesh = sphere
		var material := StandardMaterial3D.new()
		material.albedo_color = COLORS[i]
		material.roughness = 0.35
		ball.material_override = material
		add_child(ball)
		_balls.append(ball)

		var spring := JiggleSpring.new()
		spring.reset_to(base)
		_springs.append(spring)


func reset_demo() -> void:
	for i in _springs.size():
		_springs[i].reset_to(_bases[i])
		_targets[i] = _bases[i]
		_balls[i].position = _bases[i]
	stimulus.reset()


func on_params_changed() -> void:
	set_substep_hz(float(simulation_rate))
	_sync_springs()


func _simulate(delta: float) -> void:
	_sync_springs()
	for i in _springs.size():
		var target := _bases[i] + stimulus.offset
		_targets[i] = target
		_balls[i].position = _springs[i].step(delta, target)


func _draw_debug() -> void:
	_draw_grid()
	for i in _springs.size():
		var spring := _springs[i]
		debug.spring_gizmo(
			_targets[i], spring.position, spring.velocity, BALL_RADIUS * 1.35, max_distance
		)
		# 흔들림이 전혀 없을 때의 기준선. 자극이 얼마나 크게 들어오는지 알 수 있다.
		debug.line(
			_bases[i] - Vector3(0.12, 0.0, 0.0),
			_bases[i] + Vector3(0.12, 0.0, 0.0),
			Color(1.0, 1.0, 1.0, 0.18)
		)


func sample_plot() -> Dictionary:
	return {
		"left": _springs[0].position.y - _targets[0].y,
		"middle": _springs[1].position.y - _targets[1].y,
		"right": _springs[2].position.y - _targets[2].y,
	}


func get_plot_series() -> Array[Dictionary]:
	return [
		{"id": "left", "color": COLORS[0]},
		{"id": "middle", "color": COLORS[1]},
		{"id": "right", "color": COLORS[2]},
	]


func get_plot_info() -> String:
	var kc := JiggleSpring.params_from_frequency(frequency, zeta_middle)
	return "목표 대비 상하 변위   |   f = %.2f Hz → k = %.0f   |   ζ = %.2f / %.2f / %.2f" % [
		frequency, kc.x, zeta_left, zeta_middle, zeta_right
	]


func get_demo_title() -> String:
	return "01 · 스프링-댐퍼 기초"


func get_demo_description() -> String:
	return """[b]Jiggle은 결국 이 한 줄이다:[/b]  [code]a = k(목표 − 현재) − c·속도[/code]
공 세 개는 같은 목표를 쫓지만 [b]감쇠비 ζ = c / (2√k)[/b] 만 다르다. 왼쪽부터 부족감쇠 · 임계감쇠 · 과감쇠.
[color=#8ab4ff]해볼 것[/color]  ① 자극을 [b]임펄스(스페이스)[/b]로 주고 그래프에서 곡선 세 개를 비교 → 오버슈트가 곧 "출렁임"이다.
② [b]적분[/b]을 '명시적 오일러'로 바꾸고 [b]Hz[/b]를 15로 내려 보기 → 에너지가 늘어나며 발산한다. dt가 커지면 이산화 오차가 폭주한다는 뜻.
③ 같은 조건에서 '해석적 해'로 바꾸면 Hz를 아무리 내려도 멀쩡하다. 대신 비용이 비싸고 비선형 확장이 어렵다.
④ [b]중력[/b]을 켜면 정지 상태의 위치가 목표보다 아래로 내려간다 — 중력은 평형점을 g/k 만큼 옮기는 것과 같기 때문."""


func get_param_labels() -> Dictionary:
	return {
		&"show_debug": "디버그 표시",
		&"frequency": "진동수 (Hz)",
		&"zeta_left": "ζ 왼쪽 (빨강)",
		&"zeta_middle": "ζ 가운데 (초록)",
		&"zeta_right": "ζ 오른쪽 (파랑)",
		&"integrator": "적분 방식",
		&"simulation_rate": "시뮬레이션 주기",
		&"gravity_enabled": "중력",
		&"max_distance": "최대 이탈 거리",
	}


func get_presets() -> Dictionary:
	return {
		"교과서": {
			&"frequency": 2.0,
			&"zeta_left": 0.12,
			&"zeta_middle": 1.0,
			&"zeta_right": 2.2,
			&"integrator": 1,
			&"simulation_rate": 120,
		},
		"젤리": {&"frequency": 3.4, &"zeta_left": 0.06, &"zeta_middle": 0.2, &"zeta_right": 0.5},
		"묵직": {&"frequency": 0.9, &"zeta_left": 0.15, &"zeta_middle": 0.45, &"zeta_right": 1.0},
		"발산시키기": {&"frequency": 6.0, &"integrator": 0, &"simulation_rate": 30},
	}


func get_unstable_presets() -> PackedStringArray:
	# 이 프리셋은 "명시적 오일러 + 큰 dt = 발산"을 보여 주는 것이 목적이다.
	return PackedStringArray(["발산시키기"])


func get_camera_focus() -> Vector3:
	return Vector3(0.0, 1.05, 0.0)


func get_camera_distance() -> float:
	return 2.6


func _sync_springs() -> void:
	var zetas := [zeta_left, zeta_middle, zeta_right]
	for i in _springs.size():
		var spring := _springs[i]
		spring.configure(frequency, zetas[i])
		spring.integrator = integrator as JiggleSpring.Integrator
		spring.gravity = Vector3.DOWN * 9.8 if gravity_enabled else Vector3.ZERO
		spring.max_distance = max_distance


func _draw_grid() -> void:
	var color := Color(1.0, 1.0, 1.0, 0.06)
	for i in range(-6, 7):
		var t := float(i) * 0.25
		debug.line(Vector3(t, 0.001, -1.5), Vector3(t, 0.001, 1.5), color)
		debug.line(Vector3(-1.5, 0.001, t), Vector3(1.5, 0.001, t), color)
