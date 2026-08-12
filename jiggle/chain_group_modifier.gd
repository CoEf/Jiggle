@tool
@icon("res://jiggle/icons/jiggle_chain_group.svg")
class_name JiggleChainGroup3D
extends SkeletonModifier3D

## 같은 소재의 사슬 [b]여러 가닥[/b]을 노드 하나로 흔든다. 머리카락 17가닥 · 치마 12가닥.
##
## [JiggleChainModifier3D] 를 실제 캐릭터에 붙였더니 노드가 [b]36개[/b]가 됐다.
## 동작은 하는데 씬 트리가 안 읽히고, 가닥을 하나 빠뜨려도 [b]그 가닥만 안 흔들릴 뿐[/b]
## 아무 에러도 안 난다. 이 노드가 그 36개를 하나로 만든다.
##
## [codeblock]
## Skeleton3D
##  └─ JiggleChainGroup3D "Hair"
##       root_pattern = "Hair_*"
##       settings     = hair_chain_setting.tres
##       colliders    = [머리]
## [/codeblock]
##
## [b]가닥을 손으로 나열하지 않는 것이 더 큰 이득이다.[/b] 근거는 이 프로젝트 안에 있다 —
## 데모 09의 [code]CharacterRig[/code] 가 이름 규칙으로 36가닥을 찾는데, 모델이 rigged3에서
## rigged4로 바뀌며 앞머리가 4마디→3마디, 본이 185→183 이 되었는데도
## [b]고칠 코드가 한 줄도 없었다.[/b] 손으로 나열했으면 전부 다시 적어야 했다.
##
## [b]자식 노드를 쓰지 않는다.[/b] [SkeletonModifier3D] 는 [Skeleton3D] 의 직속 자식이어야만
## 도는데, 가닥을 자식 노드로 두면 그 자식들은 손자가 되어 [b]에러도 경고도 없이 안 돈다.[/b]
## 그래서 가닥은 노드가 아니라 [JiggleChainStrand] 로 들고 있고, 대신 찾아낸 목록을
## 인스펙터에 읽기 전용으로 보여 준다([member found_chains]).
##
## [b]흔드는 코드는 [JiggleChainModifier3D] 와 완전히 같은 것[/b]이다.
## 둘 다 [JiggleChainStrand] 를 돌린다 — 한쪽만 고친 버그가 다른 쪽에 남지 않게 하려는 것이다.

## 사슬로 인정할 최소 본 개수. 2면 "자유 관절 1개 + 끝점"이라 흔들리기는 한다.
const MIN_CHAIN_BONES := 2

## 사슬 뿌리 본을 찾을 이름 규칙. [code]*[/code] 와 [code]?[/code] 를 쓸 수 있다.
##
## 규칙에 맞는 본들을 모아, [b]위쪽이 끊긴 곳[/b](부모가 규칙에 안 맞거나 갈래진 곳)을
## 사슬의 뿌리로 잡고 한 줄로 이어지는 동안 따라 내려간다.
@export var root_pattern := "": set = _set_root_pattern
## 규칙에 맞아도 [b]제외할[/b] 본 이름. 뿌리 이름으로 비교한다.
##
## [b]이름 규칙은 못 찾아도 조용하다.[/b] 반대로 원치 않는 것을 잡아도 조용하다.
## 그래서 제외 목록이 필수다 — 규칙을 복잡하게 만드는 것보다 이쪽이 읽힌다.
@export var excluded_roots: Array[String] = []: set = _set_excluded_roots

## 찾아낸 사슬 목록(읽기 전용). [code]"뿌리 → 끝 (n마디)"[/code] 꼴이다.
##
## [b]이게 이 노드에서 가장 중요한 부분일 수 있다.[/b] 이름 규칙은 못 찾아도 조용하므로,
## [b]무엇을 잡았는지 눈으로 볼 수 없으면 규칙이 반쯤만 맞아도 알 방법이 없다.[/b]
## 실제로 이 프로젝트의 리그에도 [code]Front_Ribbon[/code] 밑에 [code]Back[/code] 이라는
## 규칙에 안 맞는 본이 있어 한 가닥이 빠진다.
##
## [member root_pattern] 바로 아래에 두었다. 규칙을 고치는 칸과 그 결과가 [b]붙어 있어야[/b]
## 오타를 그 자리에서 알아챈다.
@export var found_chains: PackedStringArray = PackedStringArray():
	set = _set_found_chains, get = _get_found_chains

@export_group("재질")
## 이 그룹 전체가 쓰는 재질값. [b]가닥마다 따로 설정할 일이 없어지는 것이 이 노드의 요점이다.[/b]
##
## 안 꽂으면 [JiggleChainSettings] 의 기본값으로 돈다 —
## [JiggleChainModifier3D] 를 아무 설정 없이 붙인 것과 같은 상태다.
@export var settings: JiggleChainSettings = null: set = _set_settings

@export_group("가닥")
## 마지막 본의 "끝" 방향(본 로컬). 중간 본들은 자식 본 위치에서 자동으로 구한다.
## [b]리그마다 다르다.[/b] Rigify · Mixamo · VRM 은 대개 [code]+Y[/code] 다.
@export var tip_axis := Vector3.DOWN: set = _set_tip_axis
## 마지막 본에서 끝점까지의 길이. 0 이하면 [b]마지막 마디 길이를 그대로 쓴다[/b] —
## 가닥마다 굵기가 다른 리그에서 하나하나 적지 않아도 된다.
@export var tip_length := 0.0: set = _set_tip_length

@export_group("충돌")
## 등록된 [JiggleCollider3D] 노드들. 이 그룹의 [b]자식으로 넣은 것도 자동으로 잡힌다.[/b]
@export var collider_paths: Array[NodePath] = []: set = _set_collider_paths
## 끄면 등록된 충돌체를 무시한다.
@export var collision_enabled := true: set = _set_collision_enabled

@export_group("리그 연동")
## [b]애니메이션이 이 사슬의 본들을 직접 회전시키는 리그라면 반드시 켤 것.[/b]
@export var respect_animation := false
## 에디터에서도 흔들림을 미리 보여 줄지.
@export var run_in_editor := true

## 이번 프레임 이 그룹이 쓴 시간(마이크로초). 가닥 전부의 합이다.
var last_usec := 0

var _strands: Array[JiggleChainStrand] = []
var _collider_nodes: Array[JiggleCollider3D] = []
var _colliders_dirty := true
var _discovered := false


## 모든 가닥을 다음 프레임에 rest 자리로 되돌린다.
func reset_simulation() -> void:
	for strand in _strands:
		strand.reset()


## 이름 규칙을 다시 훑는다. 런타임에 리그가 바뀌었다면 부른다.
func rediscover() -> void:
	_discovered = false
	update_configuration_warnings()


## 찾아낸 가닥들. 디버그 표시나 개별 조정에 쓴다.
##
## [b]규칙이 바뀌었으면 여기서 다시 훑는다.[/b] 캐시를 그대로 돌려주면
## [code]root_pattern[/code] 을 고친 직후에 [b]옛 목록[/b]이 나오고, 그건 값이 틀린 것보다
## 알아채기 어렵다 — 다음 프레임에는 맞게 나오므로 재현이 안 된다.
func strands() -> Array[JiggleChainStrand]:
	# get_skeleton() 은 붙인 다음 프레임부터 값을 준다. 인스펙터는 지금 그려야 한다.
	var skeleton := JiggleBoneNames.skeleton_of(self)
	if skeleton != null and not _discovered:
		_discover(skeleton)
	return _strands


func _ready() -> void:
	_sync_solvers()


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if Engine.is_editor_hint() and not run_in_editor:
		reset_simulation()
		return
	if not _discovered:
		_discover(skeleton)
	if _strands.is_empty():
		return

	if _colliders_dirty:
		_refresh_colliders()
	for node in _collider_nodes:
		node.sync()

	var s := settings
	var inherit := s.motion_inherit if s != null else 0.0
	var threshold := s.teleport_threshold if s != null else 0.0
	var total := 0
	for strand in _strands:
		total += strand.simulate(skeleton, delta, respect_animation, inherit, threshold, s)
	last_usec = total


# --- 탐색 --------------------------------------------------------------------


## 이름 규칙에 맞는 본들을 사슬로 묶는다.
##
## 사슬의 시작은 [b]"위쪽이 끊긴 곳"[/b]이다. 부모가 규칙에 안 맞거나(예: [code]Hair_*[/code] 의
## 부모는 Head), 부모가 갈래져서 형제가 여럿이면 거기가 새 사슬의 뿌리다.
##
## 데모 09의 [code]CharacterRig._discover_chains()[/code] 와 같은 알고리즘이다.
## 거기서 실제 리그 두 벌에 걸쳐 검증된 방식이라 그대로 가져왔다.
func _discover(skeleton: Skeleton3D) -> void:
	_discovered = true
	_strands.clear()
	if root_pattern.is_empty():
		return

	var count := skeleton.get_bone_count()
	for bone in count:
		if not _matches(skeleton.get_bone_name(bone)):
			continue
		var parent := skeleton.get_bone_parent(bone)
		if parent >= 0 and _matches(skeleton.get_bone_name(parent)):
			# 부모도 같은 그룹이다. 형제가 나 하나뿐이면 사슬 중간이므로 건너뛴다.
			if _matching_children(skeleton, parent).size() == 1:
				continue
		var root_name := skeleton.get_bone_name(bone)
		if excluded_roots.has(root_name):
			continue

		var bones := PackedInt32Array([bone])
		var cursor := bone
		while true:
			var children := _matching_children(skeleton, cursor)
			if children.size() != 1:
				break
			cursor = children[0]
			bones.append(cursor)
		if bones.size() < MIN_CHAIN_BONES:
			continue

		var strand := JiggleChainStrand.new()
		strand.root_bone_name = root_name
		strand.end_bone_name = skeleton.get_bone_name(bones[bones.size() - 1])
		strand.tip_axis = tip_axis
		# 0 이하면 마지막 마디 길이를 그대로 쓴다. 가닥마다 굵기가 달라도 알아서 맞는다.
		strand.tip_length = (
			tip_length if tip_length > 0.0
			else skeleton.get_bone_rest(bones[bones.size() - 1]).origin.length()
		)
		# 지금 풀어 둔다. 시뮬레이션이 돌기 전에도 인스펙터가 마디 수를 물어보기 때문이다.
		strand.resolve(skeleton)
		_strands.append(strand)

	_sync_solvers()
	_colliders_dirty = true


func _matching_children(skeleton: Skeleton3D, bone: int) -> PackedInt32Array:
	var result := PackedInt32Array()
	for child in skeleton.get_bone_count():
		if skeleton.get_bone_parent(child) != bone:
			continue
		if _matches(skeleton.get_bone_name(child)):
			result.append(child)
	return result


func _matches(bone_name: String) -> bool:
	return bone_name.match(root_pattern)


# --- 충돌체 ------------------------------------------------------------------


func _refresh_colliders() -> void:
	_colliders_dirty = false
	_collider_nodes.clear()
	for path in collider_paths:
		var node := get_node_or_null(path) as JiggleCollider3D
		if node != null and not _collider_nodes.has(node):
			_collider_nodes.append(node)
	_gather_child_colliders(self)
	var list: Array[JiggleVerletBody.Collider] = []
	if collision_enabled:
		for node in _collider_nodes:
			list.append(node.to_collider())
	# 가닥 전부가 [b]같은 충돌체 인스턴스[/b]를 본다. 매 프레임 sync() 한 번이면 전부 갱신된다.
	for strand in _strands:
		strand.chain.colliders = list


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


## 재질값을 모든 가닥의 솔버에 밀어 넣는다.
##
## [JiggleChainModifier3D] 와 달리 여기는 [b]리소스가 없을 때 쓸 노드 쪽 값이 없다.[/b]
## 그럴 때는 리소스 기본값 한 벌을 만들어 쓴다 — 그 기본값이 곧 솔버 기본값이므로
## (검사가 그 일치를 확인한다) 아무것도 안 꽂은 그룹은 기본 설정으로 도는 것이 된다.
func _sync_solvers() -> void:
	var s := settings if settings != null else _default_settings()
	for strand in _strands:
		var chain := strand.chain
		chain.iterations = s.iterations
		chain.constraint_stiffness = s.constraint_stiffness
		chain.shape_stiffness = s.shape_stiffness
		chain.shape_elasticity = s.shape_elasticity
		chain.drag = s.drag
		chain.gravity = s.gravity
		chain.restore_stiffness = (
			JiggleSpring.params_from_frequency(s.restore_frequency, 1.0).x
			if s.restore_frequency > 0.0 else 0.0
		)
		chain.angle_limit = deg_to_rad(s.angle_limit_degrees)
		chain.particle_radius = s.particle_radius
		chain.collision_response = s.collision_response
		chain.collision_friction = s.collision_friction
		strand.invalidate_curves()


# 매번 새로 만들면 프레임마다 쓰레기가 생긴다. 한 번 만들어 두고 계속 쓴다.
static var _fallback: JiggleChainSettings = null


static func _default_settings() -> JiggleChainSettings:
	if _fallback == null:
		_fallback = JiggleChainSettings.new()
	return _fallback


func _set_settings(value: JiggleChainSettings) -> void:
	if settings == value:
		return
	if settings != null and settings.changed.is_connected(_sync_solvers):
		settings.changed.disconnect(_sync_solvers)
	settings = value
	if settings != null and not settings.changed.is_connected(_sync_solvers):
		settings.changed.connect(_sync_solvers)
	_sync_solvers()


func _set_root_pattern(value: String) -> void:
	root_pattern = value
	_discovered = false
	update_configuration_warnings()
	notify_property_list_changed()


func _set_excluded_roots(value: Array[String]) -> void:
	excluded_roots = value
	_discovered = false
	notify_property_list_changed()


func _set_tip_axis(value: Vector3) -> void:
	tip_axis = value
	for strand in _strands:
		strand.tip_axis = value
		strand.invalidate()
	update_configuration_warnings()


func _set_tip_length(value: float) -> void:
	tip_length = value
	# 0 이하면 가닥마다 다른 길이를 쓰므로 다시 탐색해야 한다.
	_discovered = false


func _set_collider_paths(value: Array[NodePath]) -> void:
	collider_paths = value
	_colliders_dirty = true


func _set_collision_enabled(value: bool) -> void:
	collision_enabled = value
	_colliders_dirty = true


## 파생 데이터라 쓰기가 없다. [b]인스펙터에서도 회색으로 잠긴다[/b]
## ([method _validate_property] 에서 READ_ONLY 를 붙인다) — 세터가 조용히 무시하기만 하면
## 고칠 수 있는 것처럼 보이는데 아무 일도 안 일어나는, 가장 피하고 싶은 모양이 된다.
func _set_found_chains(_value: PackedStringArray) -> void:
	pass


## 에디터에서는 시뮬레이션이 안 돌고 있을 수도 있으므로 [method strands] 가 그 자리에서 훑는다.
func _get_found_chains() -> PackedStringArray:
	var list := PackedStringArray()
	for strand in strands():
		list.append("%s → %s (%d마디)" % [
			strand.root_bone_name, strand.end_bone_name, strand.bone_count()
		])
	return list


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		_discovered = false
		notify_property_list_changed()
		update_configuration_warnings()


## [member found_chains] 는 탐색 결과라 [b]씬에 저장하면 안 된다.[/b]
## 저장하면 리그를 고친 뒤에도 옛 목록이 [code].tscn[/code] 에 남아 있다가 그대로 보인다 —
## 3-⑳ 과 같은 종류의 "재현 안 되는" 혼란이다. 인스펙터에만 보이고 읽기 전용으로 잠근다.
func _validate_property(property: Dictionary) -> void:
	if property.name == "found_chains":
		property.usage = PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_READ_ONLY


## 에디터에 노란 경고를 띄운다.
##
## 이름 규칙은 [b]하나도 못 찾아도 조용하다.[/b] 그룹 노드에서는 그게 더 위험하다 —
## 노드 하나가 가닥 36개를 대신하므로, 규칙 한 글자가 틀리면 [b]전부 안 흔들린다.[/b]
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var parent := get_parent()
	if parent != null and parent is not Skeleton3D:
		warnings.append(
			"Skeleton3D 의 직속 자식이어야 한다. 지금은 %s 아래라 에러 하나 없이 그냥 안 돈다."
			% parent.get_class()
		)
		return warnings

	var skeleton := JiggleBoneNames.skeleton_of(self)
	if skeleton == null or skeleton.get_bone_count() == 0:
		return warnings

	if root_pattern.is_empty():
		warnings.append("root_pattern 을 정해야 한다 (예: \"Hair_*\").")
		return warnings
	if not _discovered:
		_discover(skeleton)
	if _strands.is_empty():
		warnings.append(
			"'%s' 에 맞는 사슬을 하나도 못 찾았다. 규칙이 틀렸거나 마디가 %d개 미만이다."
			% [root_pattern, MIN_CHAIN_BONES]
		)
		return warnings
	if tip_axis.is_zero_approx():
		warnings.append("tip_axis 가 0 벡터다. 마지막 본의 끝 방향을 정할 수 없다.")
	return warnings
