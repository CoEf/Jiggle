class_name JiggleDemo
extends Node3D

## 모든 데모의 공통 뼈대.
##
## 데모는 [code].tscn[/code] 없이 [b]전부 코드로[/b] 자기 씬을 만든다.
## 학습 목적상 "이 오브젝트가 어디서 왔는지"가 에디터 인스펙터가 아니라
## 스크립트 한 곳에 다 보이는 편이 훨씬 낫기 때문이다.
##
## 하위 클래스가 채워야 할 것:
## [codeblock]
## _build()          씬 구성 (한 번만)
## _simulate(delta)  고정 timestep 시뮬레이션
## _draw_debug()     디버그 라인 그리기
## reset_demo()      초기 상태로 되돌리기
## [/codeblock]

## 한 프레임에 허용할 최대 서브스텝. 이 이상 밀리면 따라잡기를 포기한다.
## (포기하지 않으면 느려질수록 더 많이 계산해서 더 느려지는 악순환에 빠진다.)
const MAX_SUBSTEPS := 8

## 디버그 라인을 그릴지. 결과만 보고 싶을 때 끈다.
@export var show_debug := true

var stimulus := Stimulus.new()
var debug: JiggleDebugDraw

var _accumulator := 0.0
var _substep_hz := 120.0


func _ready() -> void:
	debug = JiggleDebugDraw.new()
	add_child(debug)
	_build()
	on_params_changed()
	reset_demo()


func _process(delta: float) -> void:
	if delta <= 0.0:
		return
	stimulus.step(delta)
	_frame_update(delta)
	_advance(delta)
	_post_simulate(delta)
	if show_debug:
		debug.begin()
		_draw_debug()
		debug.end()
	else:
		debug.begin()
		debug.end()


## 프레임 delta 를 고정 크기 서브스텝으로 쪼개 시뮬레이션한다.
##
## 이렇게 하지 않으면 60fps에서 튜닝한 흔들림이 144fps나 렉이 걸린 순간에
## 전혀 다르게 보인다. Jiggle 구현에서 가장 흔한 버그다.
func _advance(delta: float) -> void:
	var step := 1.0 / maxf(_substep_hz, 1.0)
	_accumulator += delta
	var steps := 0
	while _accumulator >= step and steps < MAX_SUBSTEPS:
		_simulate(step)
		_accumulator -= step
		steps += 1
	if steps >= MAX_SUBSTEPS:
		_accumulator = 0.0


func set_substep_hz(hz: float) -> void:
	_substep_hz = maxf(hz, 1.0)
	_accumulator = 0.0


func get_substep_hz() -> float:
	return _substep_hz


func trigger_impulse() -> void:
	stimulus.trigger_impulse()


func set_stimulus_kind(kind: int) -> void:
	stimulus.kind = kind as Stimulus.Kind
	stimulus.reset()
	reset_demo()


## 프리셋을 적용한다. 프리셋은 { 속성이름: 값 } 딕셔너리다.
func apply_preset(preset_name: String) -> void:
	var presets := get_presets()
	if not presets.has(preset_name):
		return
	var values: Dictionary = presets[preset_name]
	for key: StringName in values:
		set(key, values[key])
	on_params_changed()


# --- 하위 클래스가 덮어쓰는 부분 -------------------------------------------------

func _build() -> void:
	pass


## 프레임당 정확히 한 번 호출된다. 자극을 씬에 반영하는 등
## "서브스텝마다 반복하면 안 되는" 일을 여기서 한다.
func _frame_update(_delta: float) -> void:
	pass


func _simulate(_delta: float) -> void:
	pass


## 서브스텝을 다 돌린 뒤 프레임당 한 번 호출된다.
## 시뮬레이션 결과를 메쉬로 굽는 것처럼 "한 번만 하면 되는" 일을 여기서 한다.
func _post_simulate(_delta: float) -> void:
	pass


func _draw_debug() -> void:
	pass


func reset_demo() -> void:
	pass


## 슬라이더가 움직였을 때 호출된다. 바뀐 값을 시뮬레이터에 밀어 넣는 곳.
func on_params_changed() -> void:
	pass


func get_demo_title() -> String:
	return "데모"


## 하단 설명 패널에 뿌릴 BBCode 텍스트.
func get_demo_description() -> String:
	return ""


## { 속성이름: "한글 라벨" }
func get_param_labels() -> Dictionary:
	return {}


## { "프리셋 이름": { 속성이름: 값 } }
func get_presets() -> Dictionary:
	return {}


## 그래프에 그릴 계열 목록. [{ "id": "a", "color": Color(...) }, ...]
func get_plot_series() -> Array[Dictionary]:
	return []


## 이번 프레임의 그래프 샘플. { "a": 0.13, ... }
func sample_plot() -> Dictionary:
	return {}


## 그래프 위에 띄울 한 줄 정보(감쇠비, 계산된 k/c 등).
func get_plot_info() -> String:
	return ""


## 헤드리스 검사용 자체 점검. 문제가 없으면 빈 문자열을 돌려준다.
## [code]tools/smoke_test.gd[/code] 가 데모마다 호출한다.
func smoke_check() -> String:
	return ""


## [b]일부러[/b] 발산하도록 만든 프리셋 이름들. 스모크 테스트는 이들을 건너뛴다.
## "이렇게 하면 터진다"를 보여 주는 것이 목적인 프리셋이 여기 들어간다.
func get_unstable_presets() -> PackedStringArray:
	return PackedStringArray()


func get_camera_focus() -> Vector3:
	return Vector3(0.0, 1.0, 0.0)


func get_camera_distance() -> float:
	return 3.0
