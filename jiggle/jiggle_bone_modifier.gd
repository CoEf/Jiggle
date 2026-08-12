@tool
@icon("res://jiggle/icons/jiggle_bone_modifier.svg")
class_name JiggleBoneModifier3D
extends SkeletonModifier3D

## 본 하나를 흔드는 커스텀 [SkeletonModifier3D]. 가슴·엉덩이 Jiggle의 표준 구현이다.
##
## [b]반드시 [Skeleton3D] 의 직속 자식이어야[/b] 동작한다.
##
## [b]동작 원리 (4단계)[/b]
## [codeblock]
## 1. 이 본의 "흔들림이 없다면 있어야 할" 끝점(target)을 월드 좌표로 구한다
## 2. 스프링 파티클이 그 target 을 쫓게 한다  → 스켈레톤이 움직이면 자연히 뒤처진다(관성)
## 3. 파티클을 본 원점 기준 구면에 붙여 길이를 유지한다
## 4. rest 방향 → 파티클 방향으로 가는 회전을 만들어 본 포즈에 넣는다
## [/codeblock]
##
## 핵심은 [b]2번[/b]이다. 파티클을 월드 공간에 두는 것만으로 관성이 공짜로 생긴다.
## 별도의 "가속도를 측정해서 힘으로 바꾸는" 코드가 필요 없다.

## 본의 "끝" 방향으로 삼을 로컬 축. 리그마다 본이 향한 축이 달라서 반드시 필요하다.
## 가슴은 보통 +Z(앞), 엉덩이는 -Z(뒤)다.
enum TipAxis { X, NEG_X, Y, NEG_Y, Z, NEG_Z }

const SUBSTEP := 1.0 / 120.0
const MAX_SUBSTEPS := 6

## 흔들 본의 이름. 스켈레톤 아래에 놓으면 인스펙터에서 드롭다운으로 고를 수 있다.
@export var bone_name := "": set = _set_bone_name
@export var tip_axis: TipAxis = TipAxis.Z: set = _set_tip_axis
## 본 원점에서 흔들리는 덩어리 중심까지의 거리. 스프링 팔 길이다.
@export var tip_length := 0.08: set = _set_tip_length

@export_group("스프링")
## 1초에 몇 번 출렁이는가.
@export var frequency := 2.4
## 감쇠비. 0.15~0.3 이 살집 있는 느낌, 1.0 이면 전혀 출렁이지 않는다.
@export var damping_ratio := 0.22
## 상하 강성 배율. 1보다 크면 위아래로 덜 흔들린다.
@export var vertical_ratio := 1.0
## 좌우/앞뒤 강성 배율. 연부 조직은 보통 좌우로 더 잘 흔들린다.
@export var horizontal_ratio := 0.7

@export_group("힘")
## 아래로 당기는 상수 가속도. 정지 상태에서도 rest보다 살짝 처지게 만든다.
## 실제 중력(9.8)을 그대로 쓰면 과하게 늘어지므로 연출값으로 쓴다.
@export var gravity := 3.0
## 스켈레톤이 움직일 때 파티클이 그 이동을 얼마나 그대로 따라가는지.
## 0 = 전혀 안 따라감(관성 최대, 크게 흔들림), 1 = 그대로 따라감(흔들림 없음).
@export var motion_inherit := 0.0

@export_group("제한")
## rest 방향에서 벗어날 수 있는 최대 각도. 끄면 본이 뒤집히며 메쉬가 터진다.
@export var max_angle_degrees := 26.0: set = _set_max_angle_degrees
## 파티클을 본 원점 기준 구면에 붙여 둘지. 끄면 덩어리가 늘었다 줄었다 한다.
@export var keep_length := true
## 흔들린 만큼 축 방향으로 늘리는 연출(부피 보존). 물리는 아니지만 훨씬 살아 보인다.
@export var squash := 0.25

@export_group("리그 연동")
## [b]애니메이션이 이 본을 직접 회전시키는 리그라면 반드시 켤 것.[/b]
##
## 끄면 항상 [b]rest 자세[/b]를 기준으로 흔든다(애니메이션이 없는 리그용, 기본값).
## 켜면 이번 프레임의 [b]애니메이션 포즈[/b]에 흔들림을 곱한다.
## [codeblock]
## 끔  : set_bone_pose_rotation(bone, swing * rest)
## 켬  : set_bone_pose_rotation(bone, swing * 이번_프레임_애니메이션_포즈)
## [/codeblock]
@export var respect_animation := false
## 에디터에서도 흔들림을 미리 보여 줄지. 끄면 에디터에서는 rest 자세 그대로 둔다.
@export var run_in_editor := true

# --- 디버그 표시용 공개 상태 (데모가 읽어서 그린다) ---
var particle_position := Vector3.ZERO
var particle_velocity := Vector3.ZERO
var target_position := Vector3.ZERO
var bone_origin := Vector3.ZERO
var swing_angle := 0.0
var limit_radius := 0.0

var _spring := JiggleSpring.new()
var _bone := -1
var _parent_bone := -1
var _rest := Transform3D.IDENTITY
# 이번 프레임의 기준 포즈. respect_animation 이 꺼져 있으면 _rest 와 같다.
var _base := Transform3D.IDENTITY
var _previous_target := Vector3.ZERO
var _initialized := false
var _accumulator := 0.0
var _warned := false


## 다음 프레임에 파티클을 rest 위치로 되돌린다.
func reset_simulation() -> void:
	_initialized = false
	_accumulator = 0.0


func _process_modification_with_delta(delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	if Engine.is_editor_hint() and not run_in_editor:
		# 포즈를 아예 쓰지 않는다. 스켈레톤이 rest 를 그대로 쓰게 둔다.
		_initialized = false
		return
	if _bone < 0:
		_resolve(skeleton)
		if _bone < 0:
			return

	# 0) 이번 프레임의 기준 포즈. 애니메이션 리그면 애니메이션 포즈, 아니면 rest.
	#
	# 여기서 get_bone_pose() 를 읽어도 우리 자신의 지난 프레임 출력이 되돌아오지 않는다.
	# 스켈레톤이 모디파이어 처리를 끝낸 뒤 로컬 포즈를 원래대로 복구하기 때문이다.
	# (같은 성질 때문에 모디파이어 결과를 밖에서 읽을 수 없다 — JigglePoseReader3D 참고)
	_base = skeleton.get_bone_pose(_bone) if respect_animation else _rest

	# 1) 흔들림이 없다면 이 본의 끝이 있어야 할 자리(월드 좌표).
	var parent_global := skeleton.global_transform
	if _parent_bone >= 0:
		parent_global = parent_global * skeleton.get_bone_global_pose(_parent_bone)
	var rest_direction := (_base.basis * tip_vector()).normalized()
	bone_origin = parent_global * _base.origin
	target_position = bone_origin + (parent_global.basis * rest_direction).normalized() * tip_length

	if not _initialized:
		_spring.reset_to(target_position)
		_previous_target = target_position
		_initialized = true

	# 스켈레톤 이동분 중 일부를 파티클에 그대로 물려준다.
	# 이 한 줄이 "얼마나 관성적으로 굴 것인가"를 조절하는 유일한 손잡이다.
	_spring.position += (target_position - _previous_target) * motion_inherit
	_previous_target = target_position

	_configure_spring(parent_global.basis)

	# 2) 고정 timestep 으로 스프링을 적분한다.
	# 모디파이어는 렌더 프레임마다 불리므로 delta 가 프레임레이트에 따라 출렁인다.
	# 그대로 쓰면 144Hz와 60Hz에서 흔들림이 달라진다.
	_accumulator += delta
	var steps := 0
	while _accumulator >= SUBSTEP and steps < MAX_SUBSTEPS:
		_spring.step(SUBSTEP, target_position)
		_accumulator -= SUBSTEP
		steps += 1
	if steps >= MAX_SUBSTEPS:
		_accumulator = 0.0

	# 3) 길이 유지: 본은 늘어나지 않는다고 보고 구면에 투영한다.
	if keep_length:
		_project_to_sphere()
	particle_position = _spring.position
	particle_velocity = _spring.velocity

	# 4) 방향 → 본 회전.
	_apply_to_bone(skeleton, parent_global.basis)


func _resolve(skeleton: Skeleton3D) -> void:
	_bone = skeleton.find_bone(bone_name)
	if _bone < 0:
		# 이름이 한 글자만 틀려도 모디파이어는 아무 말 없이 아무것도 안 한다.
		# 그 침묵이 원인을 찾는 데 가장 오래 걸리는 실수라 한 번은 알려 준다.
		if not _warned and not bone_name.is_empty():
			_warned = true
			push_warning("JiggleBoneModifier3D: '%s' 라는 본이 없다" % bone_name)
		return
	_parent_bone = skeleton.get_bone_parent(_bone)
	_rest = skeleton.get_bone_rest(_bone)
	_base = _rest
	_initialized = false


func _configure_spring(parent_basis: Basis) -> void:
	var base := JiggleSpring.params_from_frequency(frequency, damping_ratio)
	# 축별로 강성을 다르게 주면 "위아래보다 좌우로 잘 흔들리는" 비등방 거동이 나온다.
	# 이게 실제 연부 조직과 완벽한 구슬을 가르는 가장 큰 차이다.
	var scale := Vector3(horizontal_ratio, vertical_ratio, horizontal_ratio)
	_spring.stiffness = Vector3(base.x, base.x, base.x) * scale
	# 강성을 축마다 바꿨으면 감쇠도 sqrt(k) 에 맞춰 같이 바꿔야 감쇠비가 유지된다.
	# 이걸 빼먹으면 한 축만 유난히 오래 흔들린다 — 아주 흔한 버그다.
	_spring.damping = Vector3(
		2.0 * damping_ratio * sqrt(_spring.stiffness.x),
		2.0 * damping_ratio * sqrt(_spring.stiffness.y),
		2.0 * damping_ratio * sqrt(_spring.stiffness.z),
	)
	# 강성 축은 부모 본을 따라 회전해야 한다. 몸이 돌면 "위아래"도 같이 돌기 때문.
	_spring.frame = parent_basis.orthonormalized()
	_spring.gravity = Vector3.DOWN * gravity
	# 최대 각도에 대응하는 현(弦)의 길이. 스프링이 각도 제한 너머로 달아나지 못하게 막는다.
	limit_radius = 2.0 * tip_length * sin(deg_to_rad(max_angle_degrees) * 0.5)
	_spring.max_distance = limit_radius if max_angle_degrees > 0.0 else 0.0


func _project_to_sphere() -> void:
	var offset := _spring.position - bone_origin
	var distance := offset.length()
	if distance < 0.00001:
		return
	var normal := offset / distance
	_spring.position = bone_origin + normal * tip_length
	# 반경 방향 속도를 지우지 않으면 길이가 계속 늘었다 줄었다 하려고 해서 떨린다.
	_spring.velocity -= normal * _spring.velocity.dot(normal)


func _apply_to_bone(skeleton: Skeleton3D, parent_basis: Basis) -> void:
	var offset := particle_position - bone_origin
	if offset.length_squared() < 0.0000001:
		return

	# 월드 방향을 부모 본 공간으로 되돌린다. 본 포즈는 항상 부모 기준이기 때문.
	var current := (parent_basis.orthonormalized().inverse() * offset).normalized()
	var rest_direction := (_base.basis * tip_vector()).normalized()
	var swing := Quaternion(rest_direction, current)
	if max_angle_degrees > 0.0:
		swing = _limit_swing(swing, deg_to_rad(max_angle_degrees))
	swing_angle = 2.0 * acos(clampf(absf(swing.w), -1.0, 1.0))

	# _base 는 respect_animation 이 꺼져 있으면 rest, 켜져 있으면 이번 프레임의 애니메이션 포즈다.
	skeleton.set_bone_pose_rotation(_bone, swing * _base.basis.get_rotation_quaternion())

	if squash <= 0.0:
		skeleton.set_bone_pose_scale(_bone, Vector3.ONE)
		return
	# 스쿼시&스트레치: 많이 휘었을수록 축 방향으로 늘리고 옆으로 줄인다(부피 보존).
	# 물리적 유도가 아니라 애니메이션 연출 기법이지만, 있고 없고의 차이가 아주 크다.
	var limit := deg_to_rad(maxf(max_angle_degrees, 1.0))
	var stretch := 1.0 + squash * clampf(swing_angle / limit, 0.0, 1.0)
	var lateral := 1.0 / sqrt(stretch)
	var bone_scale := Vector3(lateral, lateral, lateral)
	bone_scale[_tip_axis_index()] = stretch
	skeleton.set_bone_pose_scale(_bone, bone_scale)


## [member tip_axis] 를 본 로컬 방향 벡터로 바꾼다.
func tip_vector() -> Vector3:
	match tip_axis:
		TipAxis.X:
			return Vector3.RIGHT
		TipAxis.NEG_X:
			return Vector3.LEFT
		TipAxis.Y:
			return Vector3.UP
		TipAxis.NEG_Y:
			return Vector3.DOWN
		TipAxis.NEG_Z:
			return Vector3.FORWARD
		_:
			return Vector3.BACK


func _tip_axis_index() -> int:
	match tip_axis:
		TipAxis.X, TipAxis.NEG_X:
			return 0
		TipAxis.Y, TipAxis.NEG_Y:
			return 1
		_:
			return 2


## 회전량을 [param limit] 라디안 이내로 줄인다.
## 이 안전장치가 없으면 큰 자극에서 본이 반대로 뒤집히며 메쉬가 터진다.
static func _limit_swing(rotation: Quaternion, limit: float) -> Quaternion:
	# q 와 -q 는 같은 회전이지만 각도 계산은 다르게 나온다. 짧은 쪽으로 통일한다.
	var shortest := rotation if rotation.w >= 0.0 else -rotation
	var angle := 2.0 * acos(clampf(shortest.w, -1.0, 1.0))
	if angle <= limit or angle < 0.00001:
		return shortest
	return Quaternion.IDENTITY.slerp(shortest, limit / angle)


# --- 인스펙터 · 에디터 연동 ---------------------------------------------------


## 에디터에 노란 경고를 띄운다.
##
## [b]이 모디파이어의 최악 함정은 에러도 경고도 없이 아무 일도 안 일어나는 것이다.[/b]
## 노드를 [Skeleton3D] 한 칸 아래에 넣거나 본 이름이 한 글자 틀리면 조용히 안 돈다.
## 실행해 봐야 알 수 있는 것을 [b]배치하는 순간[/b] 알려 주는 것이 요점이다.
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

	if bone_name.is_empty():
		warnings.append("흔들 본(bone_name)을 정해야 한다.")
	elif skeleton.find_bone(bone_name) < 0:
		warnings.append("'%s' 라는 본이 이 스켈레톤에 없다 (bone_name)." % bone_name)
	if tip_length <= 0.0:
		warnings.append("tip_length 가 0 이하다. 스프링 팔 길이가 0 이면 아무 방향도 안 나온다.")
	return warnings


func _set_bone_name(value: String) -> void:
	bone_name = value
	# 이름이 바뀌면 캐시해 둔 본 인덱스를 버려야 한다. 안 그러면 옛 본을 계속 흔든다.
	_bone = -1
	_initialized = false
	_warned = false
	update_configuration_warnings()


func _set_tip_axis(value: TipAxis) -> void:
	tip_axis = value


func _set_tip_length(value: float) -> void:
	tip_length = value
	update_configuration_warnings()


func _set_max_angle_degrees(value: float) -> void:
	max_angle_degrees = value


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		# 부모가 바뀌면 본 목록이 통째로 달라진다. 드롭다운을 다시 만들게 한다.
		_bone = -1
		notify_property_list_changed()
		update_configuration_warnings()


## [member bone_name] 을 자유 입력 대신 [b]본 이름 드롭다운[/b]으로 바꾼다.
## 내장 [PhysicalBone3D] · [SpringBoneCollision3D] 가 노출하는 것과 같은 모양이다.
##
## [method Object._get_property_list] 로 속성을 새로 선언하는 방법도 있지만, 그러면
## [code]@export[/code] 로 선언한 다른 속성들과 인스펙터 순서가 어긋난다. 여기서 필요한 것은
## [b]이미 있는 속성의 힌트만 바꾸는 것[/b]이라 이쪽이 맞다.
##
## 스켈레톤을 못 찾으면 손대지 않는다([JiggleBoneNames] 주석 참고).
func _validate_property(property: Dictionary) -> void:
	if property.name != "bone_name":
		return
	var hint := JiggleBoneNames.enum_hint(JiggleBoneNames.skeleton_of(self))
	if hint.is_empty():
		return
	property.hint = PROPERTY_HINT_ENUM
	property.hint_string = hint
