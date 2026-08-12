class_name HairRig
extends Node3D

## 코드로만 만드는 "머리 + 머리카락 다발" 리그.
##
## 머리·목·어깨는 [b]충돌체[/b] 역할을 하고, 머리카락 다발은 각각
## [JiggleChainModifier3D] 가 흔든다.
##
## 머리카락 튜브는 [method ProcSkin.add_tube] 로 만든 진짜 스킨드 메쉬라,
## 본이 휘면 표면도 같이 휜다. 관절마다 가중치가 이웃과 50:50으로 섞이므로
## 각지지 않고 부드럽게 굽는다.

const HEAD_BONE := &"Head"
const HEAD_CENTER := Vector3(0.0, 1.45, 0.0)
const HEAD_RADIUS := 0.115
const NECK_TOP := Vector3(0.0, 1.33, 0.0)
const NECK_BOTTOM := Vector3(0.0, 1.09, 0.0)
# 어깨 높이는 [b]기본 길이 머리카락의 끝이 닿지 않도록[/b] 잡았다.
#
# rest 자세가 충돌체 안에 파묻혀 있으면, 복원력이 안으로 당기고 충돌이 밖으로 밀어내는
# 상태가 영구히 지속된다. 그러면 그 가닥만 자극이 올 때마다 표면에 끌리면서
# 다른 가닥과 눈에 띄게 다르게 움직인다. 시뮬레이션 파라미터로는 절대 못 고친다.
#
# 기본값 기준: 끝점 y ≈ 1.177, 축까지 거리 ≈ 0.127, 필요 거리 0.080 → 여유 47mm.
const SHOULDER_LEFT := Vector3(0.20, 1.05, 0.0)
const SHOULDER_RIGHT := Vector3(-0.20, 1.05, 0.0)
const SHOULDER_RADIUS := 0.072

const SKIN_COLOR := Color(0.84, 0.66, 0.58)
const HAIR_COLOR := Color(0.22, 0.15, 0.13)
const HAIR_ROOT_RADIUS := 0.024
const HAIR_TIP_RADIUS := 0.006

var skeleton: Skeleton3D
var body_mesh: MeshInstance3D
var hair_mesh: MeshInstance3D
## 각 다발의 [code]{ root: StringName, end: StringName, tip_axis: Vector3, tip_length: float }[/code]
var strands: Array[Dictionary] = []
## 월드 좌표로 갱신되는 충돌체. [method refresh_colliders] 가 매 프레임 채운다.
var colliders: Array[JiggleVerletBody.Collider] = []

var _body_material := StandardMaterial3D.new()
var _hair_material := StandardMaterial3D.new()
var _bone_depth := {}
var _local_colliders: Array[PackedVector3Array] = []
var _collider_radii := PackedFloat32Array()


func build(strand_count: int, segment_count: int, segment_length: float) -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)

	var head := skeleton.add_bone(String(HEAD_BONE))
	skeleton.set_bone_parent(head, -1)
	skeleton.set_bone_rest(head, Transform3D(Basis.IDENTITY, HEAD_CENTER))

	var tip_length := segment_length * 0.7
	var hair_tool := ProcSkin.begin()
	var color_fn := _make_depth_color(segment_count)

	for strand in strand_count:
		var outward := _strand_direction(strand, strand_count)
		var bones := PackedInt32Array()
		var joints := PackedVector3Array()
		var cursor := HEAD_CENTER + outward * (HEAD_RADIUS * 0.94)
		var parent := head

		for segment in segment_count:
			var offset := outward * (HEAD_RADIUS * 0.94)
			if segment > 0:
				offset = _segment_direction(outward, segment - 1) * segment_length
				cursor += offset
			var index := skeleton.add_bone("H%d_%d" % [strand, segment])
			skeleton.set_bone_parent(index, parent)
			# rest basis 를 단위행렬로 두면 본 로컬축 = 월드축이라 읽기 쉽다.
			skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, offset))
			bones.append(index)
			joints.append(cursor)
			_bone_depth[index] = float(segment)
			parent = index

		var tip_axis := _segment_direction(outward, segment_count - 1)
		joints.append(cursor + tip_axis * tip_length)

		var radii := PackedFloat32Array()
		for i in joints.size():
			radii.append(
				lerpf(HAIR_ROOT_RADIUS, HAIR_TIP_RADIUS, float(i) / float(joints.size() - 1))
			)
		ProcSkin.add_tube(hair_tool, joints, bones, head, radii, color_fn)

		strands.append({
			"root": StringName("H%d_0" % strand),
			"end": StringName("H%d_%d" % [strand, segment_count - 1]),
			"tip_axis": tip_axis,
			"tip_length": tip_length,
		})

	skeleton.reset_bone_poses()
	_build_body(head)
	hair_mesh = _attach_mesh("Hair", ProcSkin.finish(hair_tool, _hair_material))
	_setup_materials()
	_build_colliders()


## 다발마다 하나씩 만들어야 하는 모디파이어의 재료.
func strand_count() -> int:
	return strands.size()


## 본의 현재 글로벌 위치(월드). 내장 시뮬레이터의 결과를 읽을 때 쓴다.
func bone_world_position(bone_index: int) -> Vector3:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)).origin


func set_hair_color(color: Color) -> void:
	_hair_material.albedo_color = color


## 머리 충돌체 하나만 담은 목록. 데모 05에서 양쪽 조건을 맞추는 데 쓴다.
func head_collider_only() -> Array[JiggleVerletBody.Collider]:
	var only: Array[JiggleVerletBody.Collider] = []
	if not colliders.is_empty():
		only.append(colliders[0])
	return only


## 내장 [SpringBoneSimulator3D] 가 쓰는 충돌체를 스켈레톤에 붙인다.
##
## 자작 쪽은 [JiggleVerletBody.Collider](그냥 데이터)를 쓰지만, 내장 쪽은 [b]씬 노드[/b]를 요구한다.
## 본에 붙어 따라다니는 것은 같지만, 노드라서 에디터에서 눈으로 배치할 수 있다는 차이가 있다.
func add_spring_bone_collider() -> SpringBoneCollisionSphere3D:
	var sphere := SpringBoneCollisionSphere3D.new()
	sphere.name = "HeadCollision"
	sphere.bone_name = String(HEAD_BONE)
	sphere.radius = HEAD_RADIUS * 0.95
	skeleton.add_child(sphere)
	return sphere


## 머리카락을 본 인덱스별 색으로 칠할지(관절 전이 구간이 보인다), 그냥 머리색으로 둘지.
func set_bone_color_view(enabled: bool) -> void:
	_hair_material.vertex_color_use_as_albedo = enabled
	# 본 색을 볼 때는 조명을 빼야 한다. 안 그러면 음영에 묻혀 색 구분이 안 된다.
	_hair_material.shading_mode = (
		BaseMaterial3D.SHADING_MODE_UNSHADED if enabled else BaseMaterial3D.SHADING_MODE_PER_PIXEL
	)


## 충돌체를 현재 월드 좌표로 갱신한다. 리그가 움직이면 충돌체도 따라가야 한다.
func refresh_colliders() -> void:
	var world := global_transform
	for i in colliders.size():
		colliders[i].point_a = world * _local_colliders[i][0]
		colliders[i].point_b = world * _local_colliders[i][1]


func reset_pose() -> void:
	skeleton.reset_bone_poses()


func _build_body(head: int) -> void:
	var head_fn := ProcSkin.single_bone(head)
	var skin_fn := func(_weights: Dictionary) -> Color:
		return SKIN_COLOR
	var st := ProcSkin.begin()
	ProcSkin.add_ellipsoid(
		st, HEAD_CENTER, Vector3(HEAD_RADIUS, 0.132, HEAD_RADIUS * 1.05), head_fn, skin_fn
	)
	ProcSkin.add_capsule(st, NECK_BOTTOM, NECK_TOP, 0.045, head_fn, skin_fn, 4, 14)
	ProcSkin.add_capsule(
		st, SHOULDER_RIGHT, SHOULDER_LEFT, SHOULDER_RADIUS, head_fn, skin_fn, 6, 18
	)
	body_mesh = _attach_mesh("Body", ProcSkin.finish(st, _body_material))


func _attach_mesh(mesh_name: String, mesh: ArrayMesh) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = mesh_name
	instance.mesh = mesh
	skeleton.add_child(instance)
	instance.skeleton = NodePath("..")
	instance.skin = skeleton.create_skin_from_rest_transforms()
	return instance


func _setup_materials() -> void:
	_body_material.albedo_color = SKIN_COLOR
	_body_material.roughness = 0.6
	_hair_material.albedo_color = HAIR_COLOR
	_hair_material.roughness = 0.35
	_hair_material.vertex_color_use_as_albedo = false


func _build_colliders() -> void:
	_local_colliders.clear()
	_local_colliders.append(PackedVector3Array([HEAD_CENTER, HEAD_CENTER]))
	_local_colliders.append(PackedVector3Array([NECK_BOTTOM, NECK_TOP]))
	_local_colliders.append(PackedVector3Array([SHOULDER_RIGHT, SHOULDER_LEFT]))
	_collider_radii = PackedFloat32Array([HEAD_RADIUS * 0.95, 0.045, SHOULDER_RADIUS])
	colliders.clear()
	for i in _local_colliders.size():
		colliders.append(
			JiggleVerletBody.Collider.new(
				_local_colliders[i][0], _local_colliders[i][1], _collider_radii[i]
			)
		)
	refresh_colliders()


## 다발이 머리에서 뻗어 나가는 방향. 뒤통수를 중심으로 좌우로 펼친다.
##
## 머리 꼭대기가 아니라 [b]헤어라인 높이[/b](pitch 0.35)에 심는다.
## 꼭대기에서 심으면 아래로 내려가는 rest 사슬이 머리를 관통해 버린다.
static func _strand_direction(index: int, count: int) -> Vector3:
	var t := 0.5 if count <= 1 else float(index) / float(count - 1)
	var yaw := lerpf(-2.0, 2.0, t)
	var pitch := 0.35
	return Vector3(sin(yaw) * cos(pitch), sin(pitch), -cos(yaw) * cos(pitch))


## 마디가 향하는 방향. 첫 마디부터 이미 [b]거의 아래[/b]를 보게 만드는 것이 중요하다.
##
## 각도 제한은 첫 마디를 "rest 방향 기준"으로 묶는다. 그래서 첫 마디의 rest가
## 수평에 가까우면 머리카락이 영영 아래로 못 내려오고 옆으로 뻗친 채 굳는다.
## 리그 형상 하나가 시뮬레이션 결과를 통째로 망치는 대표적인 예다.
static func _segment_direction(outward: Vector3, index: int) -> Vector3:
	var down_weight := clampf(float(index) * 0.25 + 0.75, 0.0, 1.0)
	return outward.lerp(Vector3.DOWN, down_weight).normalized()


## 가중치를 본 깊이로 환산해 색을 만든다. 관절에서 색이 섞이는 폭이 곧 전이 구간이다.
func _make_depth_color(segment_count: int) -> Callable:
	var depth_map := _bone_depth
	var span := maxf(float(segment_count - 1), 1.0)
	return func(weights: Dictionary) -> Color:
		var depth := 0.0
		var total := 0.0
		for bone: int in weights:
			var weight: float = weights[bone]
			depth += float(depth_map.get(bone, 0.0)) * weight
			total += weight
		if total > 0.0:
			depth /= total
		return Color.from_hsv(fmod(depth / span * 0.75 + 0.02, 1.0), 0.7, 0.95)
