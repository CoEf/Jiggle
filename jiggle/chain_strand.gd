@tool
class_name JiggleChainStrand
extends RefCounted

## 본 사슬 [b]한 가닥[/b]의 시뮬레이션 전부. 노드가 아니다.
##
## [b]왜 노드에서 뺐는가[/b] — 사슬을 흔드는 주인이 둘이 되었기 때문이다.
## [codeblock]
## JiggleChainModifier3D   가닥 하나를 노드 하나로   (인스펙터에서 손으로 설정)
## JiggleChainGroup3D      가닥 36개를 노드 하나로   (이름 규칙으로 자동 탐색)
## [/codeblock]
## 둘이 같은 일을 각자 구현하면 반드시 갈라진다. 한쪽만 고친 버그가 다른 쪽에 남고,
## 그 차이가 [b]에러 없이 다른 움직임[/b]으로만 나타나므로 알아채는 데 오래 걸린다.
## 그래서 "본 사슬 하나를 흔든다"는 일 자체를 여기 한 벌만 둔다.
##
## [b]스켈레톤을 들고 있지 않다.[/b] 부를 때마다 받는다.
## [SkeletonModifier3D] 가 아니므로 [code]get_skeleton()[/code] 을 쓸 수 없고,
## 그게 오히려 낫다 — 주인이 누구든 같은 코드가 돈다.
##
## [b]재질값은 여기 없다.[/b] [member chain] 에 주인이 직접 써 넣는다(3-⑨).
## 이 클래스가 매 프레임 값을 밀어 넣으면 코드로 [member chain] 을 직접 만지는 쪽
## (데모 03 · 05 · 07이 그렇게 한다)이 조용히 덮어써진다.

const SUBSTEP := 1.0 / 120.0
const MAX_SUBSTEPS := 6

## 솔버 본체. [b]주인이 직접 만진다.[/b]
var chain := JiggleVerletChain.new()

## 사슬의 시작 본(흔들리기 시작하는 첫 본).
var root_bone_name := ""
## 사슬의 마지막 본.
var end_bone_name := ""
## 마지막 본의 "끝" 방향(본 로컬). 중간 본들은 자식 본 위치에서 자동으로 구한다.
var tip_axis := Vector3.DOWN
## 마지막 본에서 끝점까지의 길이.
var tip_length := 0.05

## 재구성된 본 관절 위치(월드). 디버그 표시용.
var reconstructed := PackedVector3Array()
## 이번 프레임의 기준 관절 위치(월드). 디버그 표시용.
var rest_points := PackedVector3Array()

var _bones := PackedInt32Array()
var _rests: Array[Transform3D] = []
# 이번 프레임의 기준 포즈. respect_animation 이 꺼져 있으면 _rests 와 같은 값이다.
var _bases: Array[Transform3D] = []
var _local_tips := PackedVector3Array()
var _parent_bone := -1
var _resolved := false
var _initialized := false
var _accumulator := 0.0
# 직전 프레임의 기준 좌표계(사슬 뿌리의 부모까지의 월드 변환). motion_inherit 이 쓴다.
var _previous_frame := Transform3D.IDENTITY
var _has_previous_frame := false
var _curves_dirty := true


## 다음 프레임에 파티클을 rest 자리로 되돌린다.
func reset() -> void:
	_initialized = false
	_accumulator = 0.0
	_has_previous_frame = false


## 본 이름이 바뀌었으니 인덱스를 다시 찾으라고 표시한다.
func invalidate() -> void:
	_resolved = false
	_initialized = false


## 곡선을 다시 뽑으라고 표시한다.
func invalidate_curves() -> void:
	_curves_dirty = true


## 본 이름 → 본 인덱스를 지금 당장 찾는다.
##
## [method simulate] 이 알아서 부르므로 보통은 안 불러도 된다. 다만 시뮬레이션이 돌기 [b]전에[/b]
## [method is_valid] 나 [method bone_count] 를 물어보려면 먼저 불러야 한다 —
## 안 그러면 "찾긴 했는데 0마디"라는 답이 나온다.
func resolve(skeleton: Skeleton3D) -> void:
	if not _resolved:
		_resolve(skeleton)


## 사슬이 실제로 잡혔는가. 이름이 틀렸거나 두 본이 안 이어져 있으면 false.
## [method resolve] 나 [method simulate] 이 한 번 돈 뒤에만 의미가 있다.
func is_valid() -> bool:
	return not _bones.is_empty()


## 이 가닥이 흔드는 본 개수.
func bone_count() -> int:
	return _bones.size()


## 한 프레임 진행한다. 걸린 시간(마이크로초)을 돌려준다.
##
## [param settings] 는 곡선을 뽑을 때만 쓴다. 나머지 재질값은 이미 [member chain] 에 들어 있다.
func simulate(
	skeleton: Skeleton3D,
	delta: float,
	respect_animation: bool,
	motion_inherit: float,
	teleport_threshold: float,
	settings: JiggleChainSettings
) -> int:
	if not _resolved:
		_resolve(skeleton)
	if _bones.is_empty():
		return 0
	var started := Time.get_ticks_usec()

	_capture_bases(skeleton, respect_animation)
	var frame := _chain_parent_transform(skeleton)
	rest_points = _compute_rest_points(frame)
	if not _initialized:
		chain.setup(rest_points)
		_initialized = true
		# 곡선은 입자 수만큼 뽑아야 하는데, 그 수를 여기서야 알 수 있다.
		_curves_dirty = true
	if _curves_dirty:
		_rebuild_curve_weights(settings)
	# 기준 좌표계가 움직인 만큼 파티클을 데려간다. [b]pin_root 보다 먼저[/b] —
	# 뿌리는 어차피 바로 뒤에서 스켈레톤이 정한 자리로 고정된다.
	_carry_with_frame(frame, motion_inherit, teleport_threshold)
	chain.set_rest(rest_points)
	chain.pin_root(rest_points[0])
	chain.root_direction = (rest_points[1] - rest_points[0]).normalized()

	# 고정 timestep. Verlet은 속도를 "이전 위치와의 차이"로 유추하므로
	# dt가 프레임마다 흔들리면 속도 자체가 틀어진다. 스프링보다 훨씬 민감하다.
	_accumulator += delta
	var steps := 0
	while _accumulator >= SUBSTEP and steps < MAX_SUBSTEPS:
		chain.step(SUBSTEP)
		_accumulator -= SUBSTEP
		steps += 1
	if steps >= MAX_SUBSTEPS:
		_accumulator = 0.0

	_apply_to_bones(skeleton)
	return Time.get_ticks_usec() - started


## 루트 본에서 끝 본까지의 본 인덱스를 순서대로 돌려준다.
## 이름이 틀렸거나 두 본이 이어져 있지 않으면 빈 배열이다.
func resolve_bone_indices(skeleton: Skeleton3D) -> PackedInt32Array:
	var result := PackedInt32Array()
	if skeleton == null:
		return result
	var root_index := skeleton.find_bone(root_bone_name)
	var end_index := skeleton.find_bone(end_bone_name)
	if root_index < 0 or end_index < 0:
		return result
	# 끝에서 루트까지 부모를 타고 올라간 뒤 뒤집는다.
	var upward := PackedInt32Array()
	var cursor := end_index
	while cursor >= 0:
		upward.append(cursor)
		if cursor == root_index:
			break
		cursor = skeleton.get_bone_parent(cursor)
	if upward.is_empty() or upward[upward.size() - 1] != root_index:
		return result
	for i in range(upward.size() - 1, -1, -1):
		result.append(upward[i])
	return result


func _resolve(skeleton: Skeleton3D) -> void:
	_resolved = true
	_rests = []
	_bases = []
	_local_tips = PackedVector3Array()
	_bones = resolve_bone_indices(skeleton)
	if _bones.is_empty():
		return

	for bone in _bones:
		_rests.append(skeleton.get_bone_rest(bone))
	_bases = _rests.duplicate()
	# 중간 본의 "끝 방향"은 자식 본이 어디 붙어 있는지로 정해진다.
	# 리그마다 본 축이 제각각이라, 축을 가정하지 않고 이렇게 구하는 편이 안전하다.
	for i in _bones.size():
		if i + 1 < _bones.size():
			_local_tips.append(_rests[i + 1].origin.normalized())
		else:
			_local_tips.append(tip_axis.normalized())

	_parent_bone = skeleton.get_bone_parent(_bones[0])
	_initialized = false


## 이번 프레임의 기준 포즈를 잡는다.
##
## [param respect_animation] 이 켜져 있으면 [method Skeleton3D.get_bone_pose] 를 읽는다.
## 우리 자신의 지난 프레임 출력이 되돌아올 걱정은 없다 — 스켈레톤이 모디파이어 처리 후
## 로컬 포즈를 복구하므로, 여기서 읽히는 것은 애니메이션이 방금 써 넣은 값이다.
func _capture_bases(skeleton: Skeleton3D, respect_animation: bool) -> void:
	for i in _bones.size():
		_bases[i] = skeleton.get_bone_pose(_bones[i]) if respect_animation else _rests[i]


## [JiggleChainSettings] 의 곡선을 입자 수만큼 뽑아 솔버에 넣는다.
##
## 곡선의 가로축은 [b]뿌리(0)에서 끝(1)까지[/b]다. 모양 강성만 구간별이라 한 칸 밀어서 뽑는다 —
## 구간 [code]i[/code] 는 입자 [code]i[/code] 와 [code]i+1[/code] 사이이므로 바깥쪽 입자의 자리를 쓴다.
##
## 리소스가 없거나 곡선이 비어 있으면 [b]빈 배열[/b]을 넣는다. 솔버는 그때 전부 1.0 으로 보므로
## 지금까지의 동작과 정확히 같아진다.
func _rebuild_curve_weights(settings: JiggleChainSettings) -> void:
	_curves_dirty = false
	var count := chain.positions.size()
	if count < 2:
		# 아직 입자가 없다. 다음 프레임에 다시 시도해야 하므로 dirty 를 도로 세운다.
		_curves_dirty = true
		return
	var s := settings
	chain.restore_weights = sample_curve(s.restore_curve if s != null else null, count, 0)
	chain.drag_weights = sample_curve(s.drag_curve if s != null else null, count, 0)
	chain.radius_weights = sample_curve(s.radius_curve if s != null else null, count, 0)
	chain.shape_weights = sample_curve(s.shape_curve if s != null else null, count, 1)


## [param curve] 를 [param count] 개 입자에 맞춰 뽑는다.
## [param skip_root] 가 1이면 구간용이라 뿌리 쪽 한 칸을 건너뛴다.
##
## [b]점이 0개인 곡선은 없는 것으로 친다.[/b] 인스펙터에서 [Curve] 를 새로 만들면 점이 0개인데,
## [method Curve.sample] 이 그때 0을 돌려주므로 그대로 쓰면 사슬이 통째로 흐물해진다.
## "곡선을 붙였더니 흔들림이 사라졌다"는 원인을 찾기 아주 어려운 종류의 실패다.
static func sample_curve(curve: Curve, count: int, skip_root: int) -> PackedFloat32Array:
	var weights := PackedFloat32Array()
	if curve == null or curve.point_count == 0 or count < 2:
		return weights
	var last := float(count - 1)
	weights.resize(count - skip_root)
	for i in weights.size():
		weights[i] = curve.sample(float(i + skip_root) / last)
	return weights


## 기준 좌표계가 이번 프레임에 움직인 만큼 파티클을 따라 옮긴다.
##
## [b]파티클이 월드 공간에 있다는 것이 관성 구현의 전부다.[/b] 몸이 움직이면
## 파티클은 그냥 뒤처지고, 그 뒤처짐이 곧 흔들림이 된다 — 가속도를 재서 힘으로 바꾸는
## 코드가 한 줄도 없는 이유다. 대가는 [b]몸이 크게 움직이면 사슬만 제자리에 남는다[/b]는 것.
## 순간이동에서는 rest 에서 수 미터 벗어나 [code]safety_radius[/code] 가 통째로 되돌려 버린다
## (터지지는 않지만 사슬이 딱 굳었다 풀리는 것으로 보인다).
##
## 두 손잡이가 그 사이를 메운다.
## [codeblock]
## motion_inherit      늘 조금씩 따라간다   — 빠르게 달릴 때 과하게 눕는 것을 줄인다
## teleport_threshold  갑자기 튀면 통째로   — 순간이동 · 컷 전환 · 리스폰
## [/codeblock]
##
## [b]첫 프레임에는 아무것도 안 한다.[/b] 비교할 직전 좌표계가 없는데 IDENTITY 와 비교하면
## 스켈레톤이 원점에 있지 않은 모든 리그에서 첫 프레임에 사슬이 통째로 끌려간다.
func _carry_with_frame(
	frame: Transform3D, motion_inherit: float, teleport_threshold: float
) -> void:
	var previous_frame := _previous_frame
	var had_previous := _has_previous_frame
	_previous_frame = frame
	_has_previous_frame = true
	if not had_previous:
		return

	var inherit := clampf(motion_inherit, 0.0, 1.0)
	if teleport_threshold > 0.0:
		if frame.origin.distance_to(previous_frame.origin) > teleport_threshold:
			inherit = 1.0
	if inherit <= 0.0:
		return
	chain.carry(frame * previous_frame.affine_inverse(), inherit)


## 흔들림이 없었다면 관절들이 있었을 자리(월드).
func _compute_rest_points(world: Transform3D) -> PackedVector3Array:
	var points := PackedVector3Array()
	for i in _bones.size():
		world = world * _bases[i]
		points.append(world.origin)
	points.append(world * (_local_tips[_local_tips.size() - 1] * tip_length))
	return points


## 사슬 루트의 [b]부모[/b] 본까지의 월드 변환.
## 부모는 우리가 건드리지 않으므로, 여기서 시작해야 자기 출력이 다음 프레임 입력으로
## 되먹임되는 사고를 피할 수 있다.
func _chain_parent_transform(skeleton: Skeleton3D) -> Transform3D:
	var world := skeleton.global_transform
	if _parent_bone >= 0:
		world = world * skeleton.get_bone_global_pose(_parent_bone)
	return world


func _apply_to_bones(skeleton: Skeleton3D) -> void:
	var world := _chain_parent_transform(skeleton)
	reconstructed = PackedVector3Array()

	for i in _bones.size():
		var base := _bases[i]
		var origin := world * base.origin
		reconstructed.append(origin)

		var rest_direction := (base.basis * _local_tips[i]).normalized()
		var swing := Quaternion.IDENTITY
		var offset := chain.positions[i + 1] - origin
		if offset.length_squared() > 0.0000001:
			# 본 포즈는 부모 기준이므로 월드 방향을 부모 공간으로 되돌린다.
			var parent_basis := world.basis.orthonormalized()
			var desired := (parent_basis.inverse() * offset).normalized()
			# 시뮬레이션이 터졌다면 정규화 결과가 0 벡터가 될 수 있다.
			# Quaternion(from, to) 에 0 벡터를 넣으면 엔진 에러가 쏟아지므로 반드시 막는다.
			if not rest_direction.is_zero_approx() and not desired.is_zero_approx():
				swing = Quaternion(rest_direction, desired)

		skeleton.set_bone_pose_rotation(_bones[i], swing * base.basis.get_rotation_quaternion())
		# 다음 본의 부모 변환. 스켈레톤 캐시에 의존하지 않고 직접 누적한다.
		world = world * Transform3D((Basis(swing) * base.basis).orthonormalized(), base.origin)

	reconstructed.append(world * (_local_tips[_local_tips.size() - 1] * tip_length))
