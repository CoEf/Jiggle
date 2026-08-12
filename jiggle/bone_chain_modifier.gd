@tool
@icon("res://jiggle/icons/jiggle_chain_modifier.svg")
class_name JiggleChainModifier3D
extends SkeletonModifier3D

## 본 [b]사슬[/b]을 흔드는 [SkeletonModifier3D]. 머리카락 · 꼬리 · 끈에 쓴다.
##
## [JiggleBoneModifier3D] 가 본 하나를 스프링으로 흔들었다면,
## 이쪽은 [JiggleVerletChain] 으로 여러 본을 한 번에 흔든다. 알고리즘 골격은 똑같다.
## [codeblock]
## 1. 사슬의 rest 관절 위치를 월드 좌표로 구한다
## 2. 파티클이 그걸 쫓게 한다 (루트는 스켈레톤에 고정)
## 3. 거리 · 각도 · 충돌 제약을 반복해서 푼다
## 4. 관절 방향 → 본 회전으로 되돌린다 (루트부터 끝까지 순서대로)
## [/codeblock]
##
## 4번에서 [b]본은 늘어나지 않는다[/b]는 점이 중요하다. 파티클이 제약을 완전히
## 만족하지 못해 살짝 늘어나 있어도, 재구성된 본 사슬은 항상 정확한 rest 길이를 쓴다.
## 그래서 디버그 화면에서 파티클(십자)과 본 사슬(선)이 어긋나 보일 수 있고,
## 그 어긋남의 크기가 곧 [b]제약이 얼마나 덜 풀렸는가[/b]다.
##
## [b]반드시 [Skeleton3D] 의 직속 자식이어야 한다.[/b] 한 칸만 내려가면 에러도 경고도 없이
## 그냥 안 돈다 — 그래서 [method Node._get_configuration_warnings] 로 에디터가 먼저 잡아 준다.
##
## 같은 소재의 가닥이 여럿이면 재질값을 [JiggleChainSettings] 로 빼서 [member settings] 에 꽂는다.
## 머리카락 17가닥에 값 11개씩을 하나하나 채우는 것이 이 모디파이어를 쓸 때 가장 큰 노동이다.

## 사슬 한 가닥의 시뮬레이션. 실제 계산은 전부 여기서 일어난다.
## [JiggleChainGroup3D] 도 같은 것을 36개 들고 돈다 — 그래서 노드 밖으로 뺐다.
##
## [b]아래 @export 들보다 먼저 선언해야 한다.[/b] 세터가 초기화 시점에 [member chain] 을
## 건드리는데, 멤버 초기화는 선언 순서대로 일어나기 때문이다(3-⑨ · 3-⑲).
var strand := JiggleChainStrand.new()

## 솔버 본체. 코드에서 직접 만져도 된다(데모 03 · 05 · 07이 그렇게 한다).
##
## [member strand] 가 들고 있는 것과 [b]같은 객체[/b]다. 가닥이 바뀌어도 이 참조는 안 바뀌므로
## 한 번 받아 두고 계속 써도 된다.
var chain := strand.chain

## 사슬의 시작 본(스켈레톤에 고정되는 쪽이 아니라, 흔들리기 시작하는 첫 본).
@export var root_bone_name := "": set = _set_root_bone_name
## 사슬의 마지막 본.
@export var end_bone_name := "": set = _set_end_bone_name
## 마지막 본의 "끝" 방향(본 로컬). 중간 본들은 자식 본 위치에서 자동으로 구한다.
@export var tip_axis := Vector3.DOWN: set = _set_tip_axis
## 마지막 본에서 끝점까지의 길이.
@export var tip_length := 0.05: set = _set_tip_length

@export_group("시뮬레이션")
## [b]재질값 11개를 통째로 대신하는 리소스.[/b] 붙이면 아래 값들이 인스펙터에서 사라지고
## 리소스 쪽이 쓰인다. 같은 소재의 가닥이 여럿일 때 [code].tres[/code] 하나로 묶으라고 있는 것이다.
##
## [b]안 붙이면(null) 지금까지와 완전히 똑같이 동작한다.[/b] 아래 @export 들이 그대로 쓰인다.
## 하나만 다르게 하고 싶으면 인스펙터의 [b]Make Unique[/b] 로 그 노드만 복제하면 된다.
## 시작값은 [code]assets/adachi_rigged4/data/[/code] 참고.
@export var settings: JiggleChainSettings = null: set = _set_settings
## 제약 반복 횟수. 곧 뻣뻣함이다. 머리카락은 6 정도가 적당하다.
@export_range(1, 32) var iterations := 6: set = _set_iterations
## 거리 제약을 한 번에 얼마나 강하게 적용할지.
@export_range(0.0, 1.0, 0.01) var constraint_stiffness := 1.0: set = _set_constraint_stiffness
## [b]rest 모양을 유지하려는 강성.[/b] 0이면 축 늘어진 밧줄, 1이면 거의 굳는다.
##
## 치마 · 리본 · 굵은 머리채처럼 [b]두께가 있어 원래 형태를 어느 정도 유지하는 재질[/b]에 쓴다.
## 사슬이 통째로 흔들리는 것은 막지 않고 [b]꺾이는 것만[/b] 막는다.
## 얇은 생머리는 0.05~0.15, 치마·리본은 0.3~0.5 정도부터 시작할 것.
@export_range(0.0, 1.0, 0.01) var shape_stiffness := 0.0: set = _set_shape_stiffness
## 모양을 되돌리는 힘이 [b]얼마나 탄성적인가.[/b]
##
## 1이면 되돌아오다 반대편으로 넘어간다(스프링 강판). 0이면 튀지 않고 모양만 복구한다.
## [b]착지처럼 힘이 확 들어오는 순간에 진동이 심하면 이 값이 원인이다.[/b]
## 천 · 가죽 · 두꺼운 리본은 0에 가깝게 둘 것.
@export_range(0.0, 1.0, 0.01) var shape_elasticity := 0.0: set = _set_shape_elasticity
## 매 스텝 속도에서 깎아내는 비율. 공기 저항 겸 안정화 장치.
@export_range(0.0, 0.5, 0.001) var drag := 0.03: set = _set_drag
@export var gravity := Vector3.DOWN * 9.0: set = _set_gravity
## rest 자세로 되돌리려는 힘을 [b]주파수(Hz)[/b]로 준다. 0이면 중력에 완전히 내맡긴다.
## 머리카락은 0.9Hz 정도가 시작점으로 좋다.
@export_range(0.0, 8.0, 0.01) var restore_frequency := 0.0: set = _set_restore_frequency
## 이웃 마디와 벌어질 수 있는 최대 각도. 0이면 제한 없음.
## [b]0으로 두면 머리카락이 자기 위로 접혀 스킨드 메쉬가 뒤집힌다.[/b] 35° 정도부터 시작할 것.
@export_range(0.0, 180.0, 0.5) var angle_limit_degrees := 0.0: set = _set_angle_limit_degrees

@export_group("기준 좌표계")
# 이 둘만 세터가 없다. 솔버 상태가 아니라 [b]모디파이어가 프레임 사이에 하는 일[/b]이라
# chain 에 밀어 넣을 것이 없고, _carry_with_frame() 이 매 프레임 직접 읽어 간다.
## 뿌리가 움직인 만큼을 파티클이 [b]얼마나 그대로 따라갈지.[/b]
## 0이면 전혀 안 따라가 관성이 최대(지금까지의 동작), 1이면 흔들림이 통째로 사라진다.
## 자세한 설명은 [member JiggleChainSettings.motion_inherit].
@export_range(0.0, 1.0, 0.01) var motion_inherit := 0.0
## 한 프레임에 뿌리가 이만큼(m) 넘게 움직이면 [b]순간이동으로 보고 통째로 데려간다.[/b]
## 0이면 끔. 자세한 설명은 [member JiggleChainSettings.teleport_threshold].
@export_range(0.0, 20.0, 0.05, "or_greater") var teleport_threshold := 0.0

@export_group("충돌")
## 등록된 [JiggleCollider3D] 노드들. 이 모디파이어의 [b]자식으로 넣은 것도 자동으로 잡힌다.[/b]
## 둘 다 비어 있으면 [member chain] 의 [code]colliders[/code] 를 건드리지 않는다.
@export var collider_paths: Array[NodePath] = []: set = _set_collider_paths
## 끄면 등록된 충돌체를 무시한다. 충돌이 원인인지 아닌지 가려낼 때 가장 먼저 만지는 스위치다.
## ([JiggleCollider3D] 를 하나도 안 쓰고 코드로 [member chain] 을 채우는 경우에는 영향이 없다.)
@export var collision_enabled := true: set = _set_collision_enabled
## 파티클 자체의 두께. 충돌 시 이만큼 여유를 둔다.
@export_range(0.0, 0.2, 0.001, "or_greater") var particle_radius := 0.008: set = _set_particle_radius
## 충돌한 입자의 속도 처리 방식. 이유는 [JiggleVerletBody] 주석에 있다.
## [b]고민할 필요 없이 STABLE 이 정답이다.[/b] 나머지 둘은 왜 그런지 보라고 남겨 둔 것이다.
@export var collision_response: JiggleVerletBody.CollisionResponse = (
	JiggleVerletBody.CollisionResponse.STABLE
): set = _set_collision_response
## 표면을 스칠 때 접선 속도를 얼마나 깎을지. 0이면 얼음처럼 미끄러진다.
@export_range(0.0, 1.0, 0.01) var collision_friction := 0.2: set = _set_collision_friction

@export_group("리그 연동")
## [b]애니메이션이 이 사슬의 본들을 직접 회전시키는 리그라면 반드시 켤 것.[/b]
## 끄면 항상 rest 자세를 기준으로 흔든다(애니메이션이 없는 리그용, 기본값).
@export var respect_animation := false
## 에디터에서도 흔들림을 미리 보여 줄지. 끄면 에디터에서는 rest 자세 그대로 둔다.
@export var run_in_editor := true

## 재구성된 본 관절 위치(월드). 디버그 표시용.
var reconstructed := PackedVector3Array()
## 이번 프레임의 기준 관절 위치(월드). 디버그 표시용.
## [member respect_animation] 이 켜져 있으면 rest 가 아니라 애니메이션 포즈 기준이다.
var rest_points := PackedVector3Array()
## 이번 프레임 이 모디파이어가 쓴 시간(마이크로초). 내장 구현과 비용을 비교할 때 쓴다.
var last_usec := 0

var _collider_nodes: Array[JiggleCollider3D] = []
var _colliders_dirty := true
var _warned := false


func reset_simulation() -> void:
	strand.reset()


func _ready() -> void:
	# 인스펙터에서 채운 값을 솔버로 밀어 넣는다.
	# 기본값이 솔버 기본값과 동일하므로, 코드에서 chain 을 직접 쓰는 쪽은 영향받지 않는다.
	_sync_solver()


## 흔드는 일 자체는 [member strand] 가 한다. 여기서 하는 일은
## [b]노드에서만 할 수 있는 것[/b] 뿐이다 — 스켈레톤 찾기, 충돌체 노드 동기화, 경고.
func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if Engine.is_editor_hint() and not run_in_editor:
		# 포즈를 아예 쓰지 않는다. 스켈레톤이 rest 를 그대로 쓰게 둔다.
		strand.reset()
		return

	if _colliders_dirty:
		_refresh_colliders()
	for node in _collider_nodes:
		node.sync()

	var s := settings
	last_usec = strand.simulate(
		skeleton,
		delta,
		respect_animation,
		s.motion_inherit if s != null else motion_inherit,
		s.teleport_threshold if s != null else teleport_threshold,
		s
	)
	reconstructed = strand.reconstructed
	rest_points = strand.rest_points
	_warn_if_unresolved()


## 이름 오타든 끊긴 사슬이든, [b]조용히 아무것도 안 하는 것이 가장 나쁘다.[/b]
## 에디터에서는 [method _get_configuration_warnings] 가 먼저 잡지만,
## 코드로 만든 사슬에는 그게 안 보이므로 실행 중에도 한 번은 알려 준다.
func _warn_if_unresolved() -> void:
	if _warned or strand.is_valid():
		return
	if root_bone_name.is_empty() and end_bone_name.is_empty():
		return
	_warned = true
	push_warning(
		"JiggleChainModifier3D: '%s' → '%s' 사슬을 못 찾았다 (이름 오타이거나 두 본이 이어져 있지 않다)"
		% [root_bone_name, end_bone_name]
	)


## 루트 본에서 끝 본까지의 본 인덱스를 순서대로 돌려준다.
## 이름이 틀렸거나 두 본이 이어져 있지 않으면 빈 배열이다.
func resolve_bone_indices(skeleton: Skeleton3D) -> PackedInt32Array:
	return strand.resolve_bone_indices(skeleton)


# --- 충돌체 ------------------------------------------------------------------


## 등록된 경로와 자식 노드에서 [JiggleCollider3D] 를 모아 솔버에 물린다.
##
## [b]하나도 못 찾으면 [member chain] 의 colliders 를 건드리지 않는다.[/b]
## 코드에서 직접 충돌체 배열을 채워 쓰는 쪽(데모가 그렇다)을 덮어쓰지 않기 위해서다.
func _refresh_colliders() -> void:
	_colliders_dirty = false
	_collider_nodes.clear()
	for path in collider_paths:
		var node := get_node_or_null(path) as JiggleCollider3D
		if node != null and not _collider_nodes.has(node):
			_collider_nodes.append(node)
	_gather_child_colliders(self)
	if _collider_nodes.is_empty():
		return
	var list: Array[JiggleVerletBody.Collider] = []
	if collision_enabled:
		for node in _collider_nodes:
			list.append(node.to_collider())
	chain.colliders = list


## 충돌체 목록을 다시 수집한다. 런타임에 [JiggleCollider3D] 를 추가·제거했다면 부른다.
func refresh_colliders() -> void:
	_colliders_dirty = true


func _gather_child_colliders(node: Node) -> void:
	for child in node.get_children():
		var collider := child as JiggleCollider3D
		if collider != null and not _collider_nodes.has(collider):
			_collider_nodes.append(collider)
		_gather_child_colliders(child)


# --- 인스펙터 · 에디터 연동 ---------------------------------------------------


## 재질값 전부를 솔버로 밀어 넣는다. [member settings] 가 붙어 있으면 그쪽이 이긴다.
##
## [b]리소스가 없을 때는 아무것도 안 바뀌는 것이 정상이다.[/b] @export 기본값을
## 솔버 기본값과 똑같이 맞춰 두었기 때문이다. 그래야 코드에서 [member chain] 을
## 직접 만지는 쪽(데모가 그렇다)이 [code]_ready()[/code] 한 번에 덮어써지지 않는다.
func _sync_solver() -> void:
	if chain == null:
		return
	# 리소스가 바뀌면 곡선도 같이 바뀌었을 수 있다. 다음 프레임에 다시 뽑는다.
	strand.invalidate_curves()
	var s := settings
	chain.iterations = s.iterations if s != null else iterations
	chain.constraint_stiffness = s.constraint_stiffness if s != null else constraint_stiffness
	chain.shape_stiffness = s.shape_stiffness if s != null else shape_stiffness
	chain.shape_elasticity = s.shape_elasticity if s != null else shape_elasticity
	chain.drag = s.drag if s != null else drag
	chain.gravity = s.gravity if s != null else gravity
	chain.restore_stiffness = _restore_stiffness()
	chain.angle_limit = deg_to_rad(
		s.angle_limit_degrees if s != null else angle_limit_degrees
	)
	chain.particle_radius = s.particle_radius if s != null else particle_radius
	chain.collision_response = s.collision_response if s != null else collision_response
	chain.collision_friction = s.collision_friction if s != null else collision_friction


## 주파수(Hz) → 강성. 복원력도 결국 [JiggleSpring] 과 같은 2차 시스템이다.
func _restore_stiffness() -> float:
	var frequency := settings.restore_frequency if settings != null else restore_frequency
	if frequency <= 0.0:
		return 0.0
	return JiggleSpring.params_from_frequency(frequency, 1.0).x


## 리소스가 붙거나 바뀌면 솔버를 통째로 다시 채운다.
##
## [b]changed 신호를 받는 것이 이 설계의 절반이다.[/b] 이 작업의 90%가 튜닝인데,
## 신호를 안 받으면 [code].tres[/code] 를 고쳐도 실행 중에는 아무 일도 안 일어난다.
func _set_settings(value: JiggleChainSettings) -> void:
	# 초기화 때(null → null) 여기서 끊긴다. 아직 아래 @export 들이 안 채워진 시점이라
	# 그대로 _sync_solver() 를 부르면 0으로 초기화된 값이 솔버에 들어간다.
	if settings == value:
		return
	if settings != null and settings.changed.is_connected(_sync_solver):
		settings.changed.disconnect(_sync_solver)
	settings = value
	if settings != null and not settings.changed.is_connected(_sync_solver):
		settings.changed.connect(_sync_solver)
	_sync_solver()
	# 어느 쪽 값이 쓰이는지 인스펙터에 바로 보이게 한다(_validate_property 참고).
	notify_property_list_changed()


## 에디터에 노란 경고를 띄운다.
##
## [b]이 모디파이어의 최악 함정은 에러도 경고도 없이 아무 일도 안 일어나는 것이다.[/b]
## 노드를 한 칸만 잘못 넣거나 본 이름이 한 글자 틀려도 조용히 안 돈다.
## 실제 캐릭터에서 이 노드가 36개가 되면 어느 놈이 놀고 있는지 알 방법이 없어진다.
## 그래서 [b]실행하기 전에[/b] 에디터가 먼저 말해 주게 한다.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var parent := get_parent()
	if parent != null and parent is not Skeleton3D:
		# 여기서 끝낸다. 스켈레톤이 없으면 아래 검사는 전부 의미가 없다.
		warnings.append(
			"Skeleton3D 의 직속 자식이어야 한다. 지금은 %s 아래라 에러 하나 없이 그냥 안 돈다."
			% parent.get_class()
		)
		return warnings

	# get_skeleton() 은 붙인 다음 프레임부터 값을 준다. 경고는 지금 떠야 한다.
	var skeleton := JiggleBoneNames.skeleton_of(self)
	if skeleton == null or skeleton.get_bone_count() == 0:
		# 아직 부모가 없거나 본이 안 채워진 상태. 재촉할 일이 아니다.
		return warnings

	if root_bone_name.is_empty() or end_bone_name.is_empty():
		warnings.append("root_bone_name 과 end_bone_name 을 둘 다 정해야 사슬이 잡힌다.")
		return warnings
	for label: Array in [["root_bone_name", root_bone_name], ["end_bone_name", end_bone_name]]:
		if skeleton.find_bone(label[1]) < 0:
			warnings.append("'%s' 라는 본이 이 스켈레톤에 없다 (%s)." % [label[1], label[0]])
	if not warnings.is_empty():
		return warnings

	if resolve_bone_indices(skeleton).is_empty():
		warnings.append(
			"'%s' 와 '%s' 가 이어져 있지 않다. end 에서 부모를 타고 올라갔을 때 root 가 나와야 한다."
			% [root_bone_name, end_bone_name]
		)
	# 0 벡터를 normalized() 하면 0 벡터가 나온다 — 마지막 마디가 조용히 사라진다.
	if tip_axis.is_zero_approx():
		warnings.append("tip_axis 가 0 벡터다. 마지막 본의 끝 방향을 정할 수 없다.")
	if tip_length <= 0.0:
		warnings.append("tip_length 가 0 이하다. 마지막 마디의 길이가 0 이 되어 각도·모양 제약이 건너뛰어진다.")
	return warnings


# --- 가닥 설정 세터 -------------------------------------------------------------
#
# "이 가닥이 무엇인가"는 [member strand] 가 들고 있으므로 그쪽에도 같이 써 준다.
# 본 이름이나 축이 바뀌면 캐시해 둔 본 인덱스를 버려야 한다 — 안 그러면 옛 본을 계속 흔든다.


func _set_root_bone_name(value: String) -> void:
	root_bone_name = value
	strand.root_bone_name = value
	strand.invalidate()
	_warned = false
	update_configuration_warnings()


func _set_end_bone_name(value: String) -> void:
	end_bone_name = value
	strand.end_bone_name = value
	strand.invalidate()
	_warned = false
	update_configuration_warnings()


func _set_tip_axis(value: Vector3) -> void:
	tip_axis = value
	strand.tip_axis = value
	strand.invalidate()
	update_configuration_warnings()


func _set_tip_length(value: float) -> void:
	tip_length = value
	strand.tip_length = value
	update_configuration_warnings()


# --- 재질값 세터 ---------------------------------------------------------------
#
# 전부 [code]settings == null[/code] 일 때만 솔버에 쓴다. 리소스가 붙어 있는데도 여기서
# 밀어 넣으면 두 경로가 같은 값을 놓고 싸우고, [b]나중에 쓴 쪽이 이기는 순서 의존[/b]이 된다.
# 리소스가 붙으면 아래 @export 들은 인스펙터에서도 사라지고 코드로 써도 무시된다 —
# "지금 어느 값이 쓰이는가"에 답이 하나뿐이어야 하기 때문이다.
#
# 매 프레임 덮어쓰지 않고 세터에서만 쓰는 것도 같은 이유다. 그래야 코드로 chain 을
# 직접 만지는 쪽(데모가 그렇다)이 이긴다.


func _set_iterations(value: int) -> void:
	iterations = value
	if chain != null and settings == null:
		chain.iterations = value


func _set_constraint_stiffness(value: float) -> void:
	constraint_stiffness = value
	if chain != null and settings == null:
		chain.constraint_stiffness = value


func _set_shape_stiffness(value: float) -> void:
	shape_stiffness = value
	if chain != null and settings == null:
		chain.shape_stiffness = value


func _set_shape_elasticity(value: float) -> void:
	shape_elasticity = value
	if chain != null and settings == null:
		chain.shape_elasticity = value


func _set_drag(value: float) -> void:
	drag = value
	if chain != null and settings == null:
		chain.drag = value


func _set_gravity(value: Vector3) -> void:
	gravity = value
	if chain != null and settings == null:
		chain.gravity = value


func _set_restore_frequency(value: float) -> void:
	restore_frequency = value
	if chain != null and settings == null:
		chain.restore_stiffness = _restore_stiffness()


func _set_angle_limit_degrees(value: float) -> void:
	angle_limit_degrees = value
	if chain != null and settings == null:
		chain.angle_limit = deg_to_rad(value)


func _set_particle_radius(value: float) -> void:
	particle_radius = value
	if chain != null and settings == null:
		chain.particle_radius = value


func _set_collision_response(value: JiggleVerletBody.CollisionResponse) -> void:
	collision_response = value
	if chain != null and settings == null:
		chain.collision_response = value


func _set_collision_friction(value: float) -> void:
	collision_friction = value
	if chain != null and settings == null:
		chain.collision_friction = value


func _set_collider_paths(value: Array[NodePath]) -> void:
	collider_paths = value
	_colliders_dirty = true


func _set_collision_enabled(value: bool) -> void:
	collision_enabled = value
	_colliders_dirty = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		# 부모가 바뀌면 스켈레톤이 통째로 달라진다. 본 인덱스를 다시 찾게 한다.
		strand.invalidate()
		_warned = false
		notify_property_list_changed()
		update_configuration_warnings()


## 인스펙터 표시를 두 가지 손본다.
##
## [b]① 본 이름은 드롭다운으로.[/b] 손으로 적게 두면 오타 한 글자에 조용히 안 돈다.
##
## [b]② [member settings] 가 붙어 있으면 재질값들을 감춘다.[/b] 안 쓰이는 값을 그대로
## 보여 주면 그걸 움직여 놓고 "왜 안 바뀌지"를 하게 된다. 값이 두 군데 보이는데
## 한쪽만 진짜인 것이 여기서 제일 헷갈릴 상황이라, 아예 하나만 남긴다.
## (저장은 계속 된다 — 리소스를 떼면 원래 값이 그대로 돌아온다.)
func _validate_property(property: Dictionary) -> void:
	var name := String(property.name)
	if name == "root_bone_name" or name == "end_bone_name":
		var hint := JiggleBoneNames.enum_hint(JiggleBoneNames.skeleton_of(self))
		if hint.is_empty():
			return
		property.hint = PROPERTY_HINT_ENUM
		property.hint_string = hint
		return
	if settings != null and JiggleChainSettings.SHARED_PROPERTIES.has(name):
		property.usage = int(property.usage) & ~PROPERTY_USAGE_EDITOR
