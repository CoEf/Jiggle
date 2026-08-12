extends SceneTree

## 블로그용 스크린샷 · 시연 영상 캡처 도구.
##
## 데모 허브를 코드로 몰면서 정해진 프레임에 뷰포트를 저장한다.
## 손으로 찍으면 매번 카메라 각도와 자극 위상이 달라져서 다시 찍을 수가 없다.
##
## [codeblock]
## # 스틸 (PNG)
## godot --path <프로젝트> --script tools/capture_shots.gd -- shots
##
## # 시연 영상 (AVI → ffmpeg 로 webm/mp4 변환은 밖에서)
## godot --path <프로젝트> --write-movie <경로>.avi --fixed-fps 60 \
##       --script tools/capture_shots.gd -- movie_demo
## godot --path <프로젝트> --write-movie <경로>.avi --fixed-fps 60 \
##       --script tools/capture_shots.gd -- movie_collision
## [/codeblock]
##
## [b]데모 투어(블로그 입문 시리즈)용 컷[/b] — 데모 01의 개념 네 개를 하나씩 분리해 찍는다.
## 한 영상에 한 가지만 담는 것이 요점이다. 여러 개를 섞으면 글에서 가리킬 수가 없다.
## [codeblock]
## movie_tour1_basic       기본 모습 — 고무줄에 매달린 공
## movie_tour1_damping     감쇠비 — 같은 자극에 세 공이 다르게 반응
## movie_tour1_integrator  적분 방식 3종 — 눈으로는 차이가 안 보인다는 것이 결론
## movie_tour1_gravity     중력 — 평형점이 내려간다
## [/codeblock]
##
## 출력 경로는 [code]OUT_DIR[/code] 하나만 고치면 된다.
##
## [b]에디터 화면 컷은 여기서 못 찍는다.[/b] 에디터 GUI 안에 있는 것은 이 스크립트가 못 본다.
## 캐릭터 씬을 [code]--editor assets/adachi_rigged4/adachi_rigged4_jiggle.tscn[/code] 로 직접 열고,
## [code].godot/editor/*-editstate-*.cfg[/code] 로 뷰포트 상태를 맞춰 둔 뒤 찍는다.
## 블로그에 올린 컷에 쓴 값:
## [codeblock]
## 3D/gizmos_status/Skeleton3D = 1     # 엔진 기본 본 기즈모를 끈다. 안 끄면 이게 화면을 다 먹는다
## 3D/show_grid = false, 3D/show_origin = false
## viewports[*]: position = Vector3(0, 1.37, 0), distance = 0.62,
##               x_rotation = 0.10, y_rotation = 0.62
## [/codeblock]

const OUT_DIR := "C:/Users/Public/Code/_Blog/devlog-blog/public/images/jiggle"
## 프레이밍 후보를 던져 두는 곳. 결과물이 아니라 고르기 위한 임시 파일이다.
const CANDIDATE_DIR := "C:/Users/qaws1/AppData/Local/Temp/claude/jiggle_shots"

## main.gd 의 DEMOS 인덱스.
const DEMO_SPRING := 0
const DEMO_CHAIN := 2
const DEMO_CLOTH := 3
const DEMO_CHARACTER := 8

## Stimulus.Kind
const IDLE := 0
const BOUNCE := 1
const SIDE_STEP := 2
const TWIST := 3
const WALK := 4
const SHOCK := 5

var _main: Node = null
var _out_dir := OUT_DIR


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var mode := "shots"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]

	change_scene_to_file("res://main.tscn")
	await process_frame
	await process_frame
	_main = current_scene
	if _main == null:
		push_error("main.tscn 을 못 띄웠다")
		quit(1)
		return

	# 데모가 만들어지는 첫 프레임은 늘 튄다. 안정될 때까지 흘려보낸다.
	await _frames(30)

	match mode:
		"shots":
			await _capture_stills()
		"candidates":
			await _capture_candidates()
		"movie_demo":
			await _movie_demo()
		"movie_collision":
			await _movie_collision()
		"movie_tour1_basic":
			await _movie_tour1_basic()
		"movie_tour1_damping":
			await _movie_tour1_damping()
		"movie_tour1_integrator":
			await _movie_tour1_integrator()
		"movie_tour1_gravity":
			await _movie_tour1_gravity()
		_:
			push_error("모르는 모드: %s" % mode)
			quit(1)
			return

	print("캡처 완료: ", mode)
	quit()


# ── 스틸 ──────────────────────────────────────────────────────────────

func _capture_stills() -> void:
	# 히어로 — 실제 캐릭터. 사슬 표시를 켜야 "인형"이 아니라 "시뮬레이션"으로 읽힌다.
	# 자극은 회전만 하는 TWIST 여야 한다. 급정거는 캐릭터를 0.6 m 옆으로 끌고 가 화면 밖으로 민다.
	await _select_demo(DEMO_CHARACTER)
	await _set_stimulus(TWIST)
	await _set_param("stimulus_amount", 1.2)
	await _set_param("show_chains", true)
	await _set_camera(1.10, -0.06, -1.0, 1.75)
	await _await_twist_center(24)
	await _save_png("jiggle-hero.png")

	# 시연 영상 포스터 (영상이 로드되기 전 보이는 그림)
	await _select_demo(DEMO_CLOTH)
	await _set_stimulus(WALK)
	await _frames(150)
	await _save_png("jiggle-demo-poster.png")

	await _select_demo(DEMO_CHAIN)
	await _apply_long_hair()
	await _set_param("collision_response", 0)
	_main.call("_reset_demo")
	await _frames(160)
	await _save_png("jiggle-collision-poster.png")


## 프레이밍 후보를 한 번에 뽑는다. 골라 쓰고 나면 지워도 되는 경로다.
func _capture_candidates() -> void:
	_out_dir = CANDIDATE_DIR
	DirAccess.make_dir_recursive_absolute(CANDIDATE_DIR)
	await _select_demo(DEMO_CHARACTER)
	await _set_stimulus(SHOCK)
	# ① 위치만 밀기가 실제로 폭주하는지 — 머리카락이 어깨에 얹혀 있어야 조건이 만들어진다.
	await _select_demo(DEMO_CHAIN)
	await _set_param("segment_count", 12)
	await _set_param("segment_length", 0.062)
	await _set_param("drag", 0.02)
	await _set_param("restore_frequency", 0.5)
	await _set_param("angle_limit_degrees", 26.0)
	await _set_param("stimulus_amount", 1.5)
	await _set_stimulus(TWIST)
	await _set_camera(0.55, -0.05, 1.10, 1.85)
	var index := 0
	for response in [0, 2]:
		await _set_param("collision_response", response)
		_main.call("_reset_demo")
		var elapsed := 0
		for target in [70, 160, 260]:
			await _frames(target - elapsed)
			elapsed = target
			await _save_png("cand_%02d_r%d_f%03d.png" % [index, response, target])
			index += 1


# ── 영상 ──────────────────────────────────────────────────────────────

## 데모 01 → 03 → 04 → 09 순회. 시리즈 전체를 한 번에 보여 준다.
##
## 자극은 회전·보행 계열만 쓴다. 급정거는 리그를 0.6 m 씩 끌고 다녀서
## 가까이 잡은 카메라에서는 피사체가 프레임 밖으로 나간다.
func _movie_demo() -> void:
	await _select_demo(DEMO_SPRING)
	await _set_stimulus(IDLE)
	await _frames(30)
	for i in 5:
		_main.call("_trigger_impulse")
		await _frames(56)

	await _select_demo(DEMO_CHAIN)
	await _set_stimulus(TWIST)
	await _set_param("stimulus_amount", 1.3)
	await _set_camera(0.55, -0.05, 1.18, 1.60)
	await _frames(330)

	await _select_demo(DEMO_CLOTH)
	await _set_stimulus(WALK)
	await _frames(330)

	await _select_demo(DEMO_CHARACTER)
	await _set_param("show_chains", true)
	await _set_camera(1.10, -0.06, -1.0, 1.75)
	await _set_stimulus(TWIST)
	await _set_param("stimulus_amount", 1.2)
	await _frames(200)
	await _set_stimulus(WALK)
	await _frames(200)


## 충돌 응답 ① → ② → ③. ①에서 폭주하고 안전장치가 rest 로 되돌리는 게 보여야 한다.
func _movie_collision() -> void:
	await _select_demo(DEMO_CHAIN)
	await _apply_long_hair()

	for response in [0, 1, 2]:
		await _set_param("collision_response", response)
		_main.call("_reset_demo")
		await _frames(340)


# ── 데모 투어 1편 (데모 01) ────────────────────────────────────────────
#
# 네 영상 모두 프리셋 "묵직"(0.9Hz · ζ 0.15/0.45/1.0)에서 출발한다.
# 느린 리듬이라 한 번의 왕복이 눈으로 따라가진다 — 글이 설명하려는 것이 전부 그 왕복이다.

## 기본 모습. 고무줄에 매달린 공을 튕기며 노는 그림.
##
## 점프 자극(1초 주기)이 스프링(0.9Hz)과 거의 공진해서 진폭이 크게 나온다.
## 입문 글의 첫 컷이므로 "무슨 일이 일어나는 물건인지"가 한눈에 보이는 편이 낫다.
func _movie_tour1_basic() -> void:
	await _select_demo(DEMO_SPRING)
	await _apply_preset("묵직")
	await _set_stimulus(BOUNCE)
	_main.call("_reset_demo")
	await _frames(840)


## 감쇠비만 다른 세 공. [b]자극을 임펄스로 줘야 비교가 성립한다.[/b]
##
## 점프처럼 계속 흔들면 세 공이 전부 자극 주기에 끌려가 차이가 묻힌다.
## 한 번 툭 치고 각자 멈출 때까지 두면 ζ가 곧 "몇 번 왕복하는가"로 보인다.
##
## [b]자극을 15배로 키운다.[/b] 기본 세기로는 그래프에만 차이가 보이고 3D 화면에서는
## 공이 거의 제자리인 것처럼 보인다. 그래프를 읽을 줄 아는 사람에게는 충분하지만
## 입문 글의 독자에게는 아니다.
##
## 배수가 커 보이는 이유는 [b]임펄스 자체가 감쇠가 센 스프링[/b]이기 때문이다
## ([Stimulus] 의 [code]-200x - 16v[/code], ζ≈0.57). 초기 속도를 넣어도 최고점까지 가기 전에
## 절반 넘게 깎여서, 배수 6배가 목표 이동 0.12m 밖에 안 된다. 15배가 되어야
## [method _movie_tour1_basic] 의 점프 자극과 같은 0.3m가 나온다 —
## 카메라를 당기지 않고도 읽히므로 네 영상의 프레이밍이 전부 같게 유지된다.
func _movie_tour1_damping() -> void:
	await _select_demo(DEMO_SPRING)
	await _apply_preset("묵직")
	await _set_stimulus(IDLE)
	await _set_stimulus_amount(15.0)
	_main.call("_reset_demo")
	await _frames(40)
	for i in 4:
		_main.call("_trigger_impulse")
		await _frames(220)


## 적분 방식 3종. [b]구간마다 리셋해서 위상을 맞춘다.[/b]
##
## 결론이 "거의 똑같이 보인다"이므로 시작 조건이 같아야 주장이 성립한다.
## 리셋 없이 이어 찍으면 그냥 자극 위상이 다른 세 장면이 된다.
func _movie_tour1_integrator() -> void:
	await _select_demo(DEMO_SPRING)
	await _apply_preset("묵직")
	await _set_stimulus(BOUNCE)
	for integrator in [0, 1, 2]:
		await _set_param("integrator", integrator)
		_main.call("_reset_demo")
		await _frames(300)


## 중력 켜기/끄기. [b]자극은 정지여야 한다.[/b]
##
## 보여 줄 것이 "쉬는 자리가 내려간다"는 것뿐이라, 흔드는 자극이 있으면
## 처짐인지 흔들림인지 구별이 안 된다. 초록 와이어 구(목표)는 제자리에 있고
## 공만 그 아래에 매달리는 그림이 나와야 한다.
func _movie_tour1_gravity() -> void:
	await _select_demo(DEMO_SPRING)
	await _apply_preset("묵직")
	await _set_stimulus(IDLE)
	_main.call("_reset_demo")
	await _frames(180)
	await _set_param("gravity_enabled", true)
	await _frames(420)
	await _set_param("gravity_enabled", false)
	await _frames(300)


## 충돌이 실제로 일을 하는 조건. 기본 길이로는 끝이 어깨에 안 닿아서
## 응답 방식을 바꿔도 화면에 아무 차이가 안 난다(= 비교가 성립하지 않는다).
func _apply_long_hair() -> void:
	await _set_param("segment_count", 12)
	await _set_param("segment_length", 0.062)
	await _set_param("drag", 0.02)
	await _set_param("restore_frequency", 0.5)
	await _set_param("angle_limit_degrees", 26.0)
	await _set_param("stimulus_amount", 1.5)
	await _set_stimulus(TWIST)
	await _set_camera(0.55, -0.05, 1.10, 1.85)


# ── 허브 조작 ─────────────────────────────────────────────────────────

func _select_demo(index: int) -> void:
	_main.get_node("%DemoList").select(index)
	_main.call("_load_demo", index)
	await _frames(40)


func _set_stimulus(kind: int) -> void:
	var demo: Node = _main.get("_demo")
	demo.call("set_stimulus_kind", kind)
	# 목록 UI 도 같이 맞춰 준다. 화면에 찍히는 값이 실제 값과 달라선 안 된다.
	var option: OptionButton = _main.get_node("%StimulusOption")
	option.select(option.get_item_index(kind))
	await _frames(2)


## 궤도 카메라를 직접 몬다. 손으로 돌리면 다시 찍을 때 같은 그림이 안 나온다.
## [param focus_y] 가 음수면 데모가 정한 초점을 그대로 쓴다.
func _set_camera(yaw: float, pitch: float, focus_y: float, distance: float) -> void:
	var camera: OrbitCamera = _main.get_node("%Camera")
	camera.yaw = yaw
	camera.pitch = pitch
	if focus_y < 0.0:
		camera.focus = _main.get("_demo").call("get_camera_focus")
	else:
		camera.focus = Vector3(0.0, focus_y, 0.0)
	camera.distance = distance
	camera.call("_apply")
	await _frames(2)


## 자극 세기. 데모 01은 이것을 슬라이더로 노출하지 않아 [Stimulus] 를 직접 만진다.
## [method set_stimulus_kind] 가 리셋을 겸하므로 반드시 그 뒤에 불러야 한다.
func _set_stimulus_amount(amount: float) -> void:
	var stimulus: Object = _main.get("_demo").get("stimulus")
	stimulus.amount = amount
	await _frames(2)


## 데모가 들고 있는 프리셋을 그대로 적용한다.
## 값을 여기 다시 적으면 데모 쪽 프리셋이 바뀔 때 영상만 옛 값으로 남는다.
func _apply_preset(preset_name: String) -> void:
	var demo: Node = _main.get("_demo")
	demo.call("apply_preset", preset_name)
	_main.get_node("%ParamPanel").call("refresh_values")
	await _frames(4)


func _set_param(property: String, value: Variant) -> void:
	var demo: Node = _main.get("_demo")
	demo.set(property, value)
	demo.call("on_params_changed")
	# 슬라이더가 옛 값을 보여 주면 영상이 거짓말을 한다.
	_main.get_node("%ParamPanel").call("refresh_values")
	await _frames(4)


# ── 저장 ──────────────────────────────────────────────────────────────

func _frames(count: int) -> void:
	for i in count:
		await process_frame


## 몸통 회전이 정면을 지나가는(각속도 최대) 순간까지 기다린 뒤 [param after] 프레임을 더 간다.
##
## TWIST 는 회전만 있고 이동이 없어서 캐릭터가 화면에서 안 밀린다.
## 급정거로 히어로 컷을 찍으면 자극 자체가 캐릭터를 0.6 m 옆으로 끌고 가 버린다.
func _await_twist_center(after: int) -> void:
	var stimulus: Object = _main.get("_demo").get("stimulus")
	var previous: float = stimulus.euler.y
	for i in 400:
		await process_frame
		var current: float = stimulus.euler.y
		if previous < 0.0 and current >= 0.0:
			break
		previous = current
	await _frames(after)


## 급정거 자극이 "탁" 하고 되돌아오는 순간까지 기다린 뒤 [param after] 프레임을 더 간다.
##
## SHOCK 은 2초 주기 톱니파라, 아무 때나 찍으면 천천히 밀리는 구간이 잡힌다.
## 흔들림이 가장 큰 건 톱니가 꺾이고 나서 몇 프레임 뒤다.
func _await_shock(after: int) -> void:
	var stimulus: Object = _main.get("_demo").get("stimulus")
	var previous: float = stimulus.offset.z
	for i in 400:
		await process_frame
		var current: float = stimulus.offset.z
		if current - previous < -0.2:
			break
		previous = current
	await _frames(after)


func _save_png(file_name: String) -> void:
	await RenderingServer.frame_post_draw
	var image := get_root().get_texture().get_image()
	var path := "%s/%s" % [_out_dir, file_name]
	var error := image.save_png(path)
	if error != OK:
		push_error("저장 실패 %s (%d)" % [path, error])
		return
	print("saved  %s  %dx%d" % [path, image.get_width(), image.get_height()])
