@tool
@icon("res://jiggle/icons/jiggle_chain_settings.svg")
class_name JiggleChainSettings
extends Resource

## [JiggleChainModifier3D] 의 [b]재질값[/b]만 따로 뽑아낸 리소스.
##
## 실제 캐릭터에 붙여 보니 사슬 모디파이어가 [b]36개[/b]가 됐다. 머리카락 17가닥은
## 전부 같은 소재인데도 값 11개를 하나하나 채워야 했고, 튜닝하다 하나를 빠뜨리면
## [b]그 가닥만 다르게 움직이는데 아무 에러도 안 난다.[/b] 이 리소스가 없애는 것이 그 노동이다.
##
## [b]무엇을 어디에 두는가[/b] — 이것이 이 설계의 전부다.
## [codeblock]
## 노드에 남는다   이 가닥이 "무엇"인가
##                 root_bone_name · end_bone_name · tip_axis · tip_length · collider_paths
##                 collision_enabled · respect_animation · run_in_editor
##
## 리소스로 뺀다   이 가닥이 "무슨 재질"인가
##                 아래 11개
## [/codeblock]
## 본 이름은 가닥마다 다르므로 공유할 수 없고, 재질은 가닥마다 같으므로 공유해야 한다.
##
## [b]그룹 노드로 일괄 설정하는 것보다 리소스가 나은 이유[/b]
## [codeblock]
## 씬·캐릭터를 넘어 재사용된다   hair_chain_setting.tres 를 다른 캐릭터에도 그대로 쓴다
## 실행 중에 고쳐도 전부 반영된다  이 작업의 90%가 튜닝이다
## 개별 오버라이드가 공짜다        인스펙터의 Make Unique 가 그 노드만 복제해 준다
## 텍스트 파일이라 diff 가 읽힌다
## [/codeblock]
##
## [b]기본값은 [JiggleChainModifier3D] 의 @export 기본값과 정확히 같아야 한다.[/b]
## 리소스를 안 붙였을 때(null)의 동작이 지금과 한 톨도 달라지면 안 되기 때문이다.
## [b]둘 중 한쪽만 고치면 아무 에러 없이 동작만 달라진다.[/b] 값을 고칠 때는 반드시 양쪽을 같이 본다.
##
## [b]실제로 튜닝을 끝낸 값은 [code]assets/adachi_rigged4/data/[/code] 에 여섯 개 있다[/b]
## (머리카락 · 치마 · 리본 4종). 거기서 출발해 Make Unique 로 갈라 나가는 편이 빠르다.

## 노드와 리소스가 [b]둘 다 갖고 있는[/b] 속성 이름.
##
## 이 목록이 곧 "재질이란 무엇인가"의 정의다. 세 곳이 이걸 쓴다 —
## 모디파이어가 인스펙터에서 감출 속성을 고를 때, 솔버에 밀어 넣을 때,
## 그리고 검사가 [b]양쪽 기본값이 같은지[/b] 확인할 때.
const SHARED_PROPERTIES := [
	"iterations",
	"constraint_stiffness",
	"shape_stiffness",
	"shape_elasticity",
	"drag",
	"gravity",
	"restore_frequency",
	"angle_limit_degrees",
	"particle_radius",
	"collision_response",
	"collision_friction",
	"motion_inherit",
	"teleport_threshold",
]

## 제약 반복 횟수. 곧 뻣뻣함이다. 머리카락은 6 정도가 적당하다.
@export_range(1, 32) var iterations := 6: set = _set_iterations
## 거리 제약을 한 번에 얼마나 강하게 적용할지.
@export_range(0.0, 1.0, 0.01) var constraint_stiffness := 1.0: set = _set_constraint_stiffness
## [b]rest 모양을 유지하려는 강성.[/b] 0이면 축 늘어진 밧줄, 1이면 거의 굳는다.
##
## 치마 · 리본 · 굵은 머리채처럼 [b]두께가 있어 원래 형태를 어느 정도 유지하는 재질[/b]에 쓴다.
## 얇은 생머리는 0.05~0.15, 치마·리본은 0.3~0.6 정도부터 시작할 것.
@export_range(0.0, 1.0, 0.01) var shape_stiffness := 0.0: set = _set_shape_stiffness
## 모양을 되돌리는 힘이 [b]얼마나 탄성적인가.[/b]
##
## 1이면 되돌아오다 반대편으로 넘어간다(스프링 강판). 0이면 튀지 않고 모양만 복구한다.
## [b]착지처럼 힘이 확 들어오는 순간에 진동이 심하면 이 값이 원인이다.[/b]
@export_range(0.0, 1.0, 0.01) var shape_elasticity := 0.0: set = _set_shape_elasticity
## 매 스텝 속도에서 깎아내는 비율. 공기 저항 겸 안정화 장치.
@export_range(0.0, 0.5, 0.001) var drag := 0.03: set = _set_drag
@export var gravity := Vector3.DOWN * 9.0: set = _set_gravity
## rest 자세로 되돌리려는 힘을 [b]주파수(Hz)[/b]로 준다. 0이면 중력에 완전히 내맡긴다.
@export_range(0.0, 8.0, 0.01) var restore_frequency := 0.0: set = _set_restore_frequency
## 이웃 마디와 벌어질 수 있는 최대 각도. 0이면 제한 없음.
## [b]0으로 두면 머리카락이 자기 위로 접혀 스킨드 메쉬가 뒤집힌다.[/b] 35° 정도부터 시작할 것.
@export_range(0.0, 180.0, 0.5) var angle_limit_degrees := 0.0: set = _set_angle_limit_degrees

@export_group("뿌리 → 끝 곡선")
## 곡선의 [b]가로축은 뿌리(0)에서 끝(1)까지, 세로축은 위 값에 곱할 배수[/b]다.
## 비워 두면(null) 사슬 전체가 한 값을 쓴다 — 지금까지의 동작이다.
##
## 사슬 하나가 통째로 한 값이면 뿌리와 끝이 똑같이 뻣뻣하다. 머리카락에서 가장 흔히 원하는
## "끝으로 갈수록 부드럽게"가 그래서 안 나온다. 내장 [SpringBoneSimulator3D] 에는
## radius/stiffness/drag/gravity 각각에 곡선이 있는데 우리에게는 없던 것이다.
##
## [b]점이 하나도 없는 [Curve] 는 무시한다.[/b] 인스펙터에서 새로 만들면 점이 0개인데,
## [method Curve.sample] 이 그때 0을 돌려주므로 그대로 쓰면 [b]사슬이 통째로 흐물해진다.[/b]
## 곡선을 붙였을 뿐인데 흔들림이 사라지면 원인을 찾기 어렵다.
##
## [b]배수의 기본 범위는 0~1[/b]이다([Curve] 자체의 기본값). 1보다 크게 주고 싶으면
## 곡선의 [code]max_value[/code] 를 올린다.
@export var restore_curve: Curve = null: set = _set_restore_curve
## [member shape_stiffness] 배수. [b]구간별[/b]로 적용된다.
## 치마에서 "허리는 형태를 지키고 밑단은 흐물거리게"가 이걸로 나온다.
@export var shape_curve: Curve = null: set = _set_shape_curve
## [member drag] 배수. 끝으로 갈수록 낮추면 끝만 오래 흔들린다.
@export var drag_curve: Curve = null: set = _set_drag_curve
## [member particle_radius] 배수. 끝으로 갈수록 가늘어지는 머리채에 쓴다.
@export var radius_curve: Curve = null: set = _set_radius_curve

@export_group("기준 좌표계")
## 뿌리가 움직인 만큼을 파티클이 [b]얼마나 그대로 따라갈지.[/b]
##
## 파티클이 월드 공간에 있어서 관성이 공짜로 생기는데, 대가로 몸이 크게 움직이면
## 사슬만 제자리에 남는다. 이 값이 그 사이의 손잡이다.
## [codeblock]
## 0.0  전혀 안 따라간다 — 관성 최대 (지금까지의 동작, 기본값)
## 1.0  완전히 따라간다  — 관성 0, 흔들림이 통째로 사라진다
## [/codeblock]
## 빠르게 달리는 캐릭터에서 사슬이 과하게 뒤로 눕는다면 0.2~0.4 부터 시작할 것.
## [JiggleBoneModifier3D] 의 같은 이름 속성과 같은 일을 한다.
@export_range(0.0, 1.0, 0.01) var motion_inherit := 0.0: set = _set_motion_inherit
## 한 프레임에 뿌리가 이만큼(m) 넘게 움직이면 [b]순간이동으로 보고 통째로 데려간다.[/b]
##
## [member motion_inherit] 과 달리 이건 켜고 끄는 안전장치다. 순간이동·컷 전환·리스폰에서
## 사슬만 제자리에 남는 것을 막는다. 0이면 끔(기본값).
##
## [b]이게 없으면 안 터지는 것이 아니라 조용히 rest 로 되돌려질 뿐이다[/b]
## ([code]safety_radius[/code]). 눈에는 사슬이 순간적으로 딱 굳었다 풀리는 것으로 보인다.
## 캐릭터 키의 절반쯤(사람이면 0.8~1.0)이 시작점으로 무난하다.
@export_range(0.0, 20.0, 0.05, "or_greater") var teleport_threshold := 0.0: set = _set_teleport_threshold

@export_group("충돌")
## 파티클 자체의 두께. 충돌 시 이만큼 여유를 둔다.
@export_range(0.0, 0.2, 0.001, "or_greater") var particle_radius := 0.008: set = _set_particle_radius
## 충돌한 입자의 속도 처리 방식. [b]고민할 필요 없이 STABLE 이 정답이다.[/b]
@export var collision_response: JiggleVerletBody.CollisionResponse = (
	JiggleVerletBody.CollisionResponse.STABLE
): set = _set_collision_response
## 표면을 스칠 때 접선 속도를 얼마나 깎을지. 0이면 얼음처럼 미끄러진다.
@export_range(0.0, 1.0, 0.01) var collision_friction := 0.2: set = _set_collision_friction


# --- 세터 --------------------------------------------------------------------
#
# 전부 emit_changed() 를 부른다. 이걸 빠뜨린 값 하나는 [b]인스펙터에서 슬라이더를 움직여도
# 아무 반응이 없는데 에러도 안 나는[/b] 상태가 된다. 여기서 가장 나쁜 종류의 실패다.
# 모디파이어는 changed 신호를 받아 솔버에 다시 밀어 넣는다.


func _set_iterations(value: int) -> void:
	iterations = value
	emit_changed()


func _set_constraint_stiffness(value: float) -> void:
	constraint_stiffness = value
	emit_changed()


func _set_shape_stiffness(value: float) -> void:
	shape_stiffness = value
	emit_changed()


func _set_shape_elasticity(value: float) -> void:
	shape_elasticity = value
	emit_changed()


func _set_drag(value: float) -> void:
	drag = value
	emit_changed()


func _set_gravity(value: Vector3) -> void:
	gravity = value
	emit_changed()


func _set_restore_frequency(value: float) -> void:
	restore_frequency = value
	emit_changed()


func _set_angle_limit_degrees(value: float) -> void:
	angle_limit_degrees = value
	emit_changed()


## 곡선은 그 자체가 [Resource] 라 [b]안의 점을 움직여도 여기 세터는 안 불린다.[/b]
## 곡선의 [code]changed[/code] 를 그대로 이어 받아야 인스펙터에서 곡선을 편집하는 순간 반영된다.
## 이걸 빼먹으면 "곡선을 붙여도 아무 일도 안 일어난다"가 된다.
func _relay_curve(old: Curve, new: Curve) -> Curve:
	if old != null and old.changed.is_connected(emit_changed):
		old.changed.disconnect(emit_changed)
	if new != null and not new.changed.is_connected(emit_changed):
		new.changed.connect(emit_changed)
	return new


func _set_restore_curve(value: Curve) -> void:
	restore_curve = _relay_curve(restore_curve, value)
	emit_changed()


func _set_shape_curve(value: Curve) -> void:
	shape_curve = _relay_curve(shape_curve, value)
	emit_changed()


func _set_drag_curve(value: Curve) -> void:
	drag_curve = _relay_curve(drag_curve, value)
	emit_changed()


func _set_radius_curve(value: Curve) -> void:
	radius_curve = _relay_curve(radius_curve, value)
	emit_changed()


func _set_motion_inherit(value: float) -> void:
	motion_inherit = value
	emit_changed()


func _set_teleport_threshold(value: float) -> void:
	teleport_threshold = value
	emit_changed()


func _set_particle_radius(value: float) -> void:
	particle_radius = value
	emit_changed()


func _set_collision_response(value: JiggleVerletBody.CollisionResponse) -> void:
	collision_response = value
	emit_changed()


func _set_collision_friction(value: float) -> void:
	collision_friction = value
	emit_changed()
