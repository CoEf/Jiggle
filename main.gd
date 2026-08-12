extends Node3D

## 데모 허브. 데모를 갈아 끼우고, 파라미터 UI·그래프·시간 제어를 붙여 준다.
##
## 데모는 [code].tscn[/code] 없이 스크립트만으로 존재한다([JiggleDemo] 참고).
## 여기서는 스크립트를 [code]load()[/code] 해서 [code]new()[/code] 로 인스턴스를 만들 뿐이다.

const DEMOS: Array[Dictionary] = [
	{"path": "res://demos/01_spring_basics/spring_basics_demo.gd"},
	{"path": "res://demos/02_jiggle_bone/jiggle_bone_demo.gd"},
	{"path": "res://demos/03_bone_chain/bone_chain_demo.gd"},
	{"path": "res://demos/04_cloth/cloth_demo.gd"},
	{"path": "res://demos/05_builtin_springbone/spring_bone_compare_demo.gd"},
	{"path": "res://demos/06_builtin_softbody/soft_body_compare_demo.gd"},
	{"path": "res://demos/07_physical_bones/physical_bone_compare_demo.gd"},
	{"path": "res://demos/08_shader_jiggle/shader_jiggle_demo.gd"},
	{"path": "res://demos/09_real_character/real_character_demo.gd"},
]

const STIMULUS_NAMES: Array[String] = [
	"정지",
	"점프",
	"좌우 이동",
	"몸통 회전",
	"걷기",
	"급정거",
]

const SLOW_SCALE := 0.15

@onready var _camera: OrbitCamera = %Camera
@onready var _demo_root: Node3D = %DemoRoot
@onready var _demo_list: ItemList = %DemoList
@onready var _params: ParamPanel = %ParamPanel
@onready var _description: RichTextLabel = %Description
@onready var _plot: JigglePlot = %Plot
@onready var _stimulus_option: OptionButton = %StimulusOption
@onready var _pause_button: Button = %PauseButton
@onready var _slow_button: Button = %SlowButton

var _demo: JiggleDemo = null
var _slow := false


func _ready() -> void:
	for index in DEMOS.size():
		var script: GDScript = load(DEMOS[index]["path"])
		# 타이틀은 데모 스크립트가 직접 들고 있다. 목록과 데모가 어긋날 일이 없다.
		var probe := script.new() as JiggleDemo
		_demo_list.add_item(probe.get_demo_title())
		probe.free()

	for index in STIMULUS_NAMES.size():
		_stimulus_option.add_item(STIMULUS_NAMES[index], index)

	_demo_list.item_selected.connect(_load_demo)
	_stimulus_option.item_selected.connect(_on_stimulus_selected)
	_params.parameter_changed.connect(_on_parameter_changed)
	%PauseButton.pressed.connect(_toggle_pause)
	%StepButton.pressed.connect(_step_once)
	%SlowButton.pressed.connect(_toggle_slow)
	%ResetButton.pressed.connect(_reset_demo)
	%ImpulseButton.pressed.connect(_trigger_impulse)

	_demo_list.select(0)
	_load_demo(0)


func _process(_delta: float) -> void:
	if _demo == null or get_tree().paused:
		return
	_plot.info_text = _demo.get_plot_info()
	_plot.push_frame(_demo.sample_plot())


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	match key.keycode:
		KEY_SPACE:
			_trigger_impulse()
		KEY_R:
			_reset_demo()
		KEY_P:
			_toggle_pause()
		KEY_PERIOD:
			_step_once()
		KEY_S:
			_toggle_slow()
		_:
			return
	get_viewport().set_input_as_handled()


func _load_demo(index: int) -> void:
	for child in _demo_root.get_children():
		_demo_root.remove_child(child)
		child.queue_free()

	var script: GDScript = load(DEMOS[index]["path"])
	_demo = script.new() as JiggleDemo
	# add_child 시점에 데모의 _ready() 가 돌면서 씬이 구성된다.
	_demo_root.add_child(_demo)

	_params.build_for(_demo)
	_description.text = _demo.get_demo_description()
	_plot.configure(_demo.get_plot_series())
	_plot.clear_samples()
	_camera.frame_target(_demo.get_camera_focus(), _demo.get_camera_distance())
	_stimulus_option.select(_stimulus_option.get_item_index(_demo.stimulus.kind))


func _on_stimulus_selected(index: int) -> void:
	if _demo == null:
		return
	_demo.set_stimulus_kind(_stimulus_option.get_item_id(index))
	_plot.clear_samples()


func _on_parameter_changed() -> void:
	if _demo != null:
		_demo.on_params_changed()


func _reset_demo() -> void:
	if _demo == null:
		return
	_demo.reset_demo()
	_plot.clear_samples()


func _trigger_impulse() -> void:
	if _demo != null:
		_demo.trigger_impulse()


func _toggle_pause() -> void:
	get_tree().paused = not get_tree().paused
	_pause_button.text = "재생 (P)" if get_tree().paused else "일시정지 (P)"


func _toggle_slow() -> void:
	_slow = not _slow
	Engine.time_scale = SLOW_SCALE if _slow else 1.0
	_slow_button.text = "정속 (S)" if _slow else "슬로우 (S)"


## 정지 상태에서 딱 한 프레임만 진행시킨다.
## 스프링이 "지나쳤다가 되돌아오는" 순간을 한 칸씩 뜯어볼 수 있다.
func _step_once() -> void:
	var tree := get_tree()
	tree.paused = false
	await tree.process_frame
	await tree.process_frame
	tree.paused = true
	_pause_button.text = "재생 (P)"
	if _demo != null:
		_plot.info_text = _demo.get_plot_info()
		_plot.push_frame(_demo.sample_plot())
