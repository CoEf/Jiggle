class_name JiggleBody
extends Node3D

## 코드로만 만드는 스킨드 캐릭터. 외부 3D 모델을 전혀 쓰지 않는다.
##
## [Skeleton3D] 를 손으로 조립하고([method Skeleton3D.add_bone]),
## [ProcSkin] 으로 만든 [ArrayMesh] 에 본 가중치를 구워 넣은 뒤
## [method Skeleton3D.create_skin_from_rest_transforms] 로 둘을 연결한다.
##
## 정점 색에 [b]Jiggle 본 가중치[/b]를 미리 칠해 두었기 때문에,
## "웨이트 보기"를 켜면 어느 부위가 얼마나 흔들릴지 그대로 보인다.

const HIPS := &"Hips"
const SPINE := &"Spine"
const CHEST := &"Chest"
const NECK := &"Neck"
const BREAST_L := &"BreastL"
const BREAST_R := &"BreastR"
const GLUTE_L := &"GluteL"
const GLUTE_R := &"GluteR"

const HIPS_Y := 0.92
const SPINE_Y := 1.04
const CHEST_Y := 1.20
const NECK_Y := 1.34

## 가슴 본은 몸 앞(+Z), 엉덩이 본은 몸 뒤(-Z)를 향한다.
const BREAST_OFFSET := Vector3(0.072, 0.015, 0.045)
const GLUTE_OFFSET := Vector3(0.075, -0.03, -0.05)

const SKIN_COLOR := Color(0.84, 0.66, 0.58)
const JIGGLE_COLOR := Color(1.0, 0.30, 0.42)

var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D

var _material := StandardMaterial3D.new()
var _jiggle_bones: PackedInt32Array = PackedInt32Array()


func build(ghost: bool = false) -> void:
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)
	_build_bones()

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Body"
	mesh_instance.mesh = _build_mesh()
	skeleton.add_child(mesh_instance)
	# 스킨은 "메쉬의 본 인덱스 → 스켈레톤의 본"을 이어 주는 다리다.
	# rest 포즈에서 만든 것이므로 메쉬도 rest 자세로 만들어야 한다.
	mesh_instance.skeleton = NodePath("..")
	mesh_instance.skin = skeleton.create_skin_from_rest_transforms()
	_setup_material(ghost)


func bone(bone_name: StringName) -> int:
	return skeleton.find_bone(bone_name)


## 정점 색(= Jiggle 본 가중치)을 그대로 보여줄지, 살색으로 보여줄지.
func set_weight_view(enabled: bool) -> void:
	_material.vertex_color_use_as_albedo = enabled


## 스킨을 떼어 낸다. 메쉬는 rest 자세로 굳고 본이 아무리 움직여도 변형되지 않는다.
## 데모 08에서 "본 없이 셰이더만으로 흔드는" 쪽 몸을 만들 때 쓴다.
func detach_skin() -> void:
	mesh_instance.skin = null
	mesh_instance.skeleton = NodePath()


## 본의 rest 위치(스켈레톤 로컬). 마커를 같은 자리에 놓을 때 쓴다.
func bone_rest_position(bone_index: int) -> Vector3:
	return skeleton.get_bone_global_rest(bone_index).origin


## 본의 현재 글로벌 위치(월드 좌표). 디버그 그리기에 쓴다.
func bone_world_position(bone_index: int) -> Vector3:
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)).origin


func reset_pose() -> void:
	skeleton.reset_bone_poses()


func _build_bones() -> void:
	_add_bone(HIPS, -1, Vector3(0.0, HIPS_Y, 0.0))
	_add_bone(SPINE, 0, Vector3(0.0, SPINE_Y - HIPS_Y, 0.0))
	_add_bone(CHEST, 1, Vector3(0.0, CHEST_Y - SPINE_Y, 0.0))
	_add_bone(NECK, 2, Vector3(0.0, NECK_Y - CHEST_Y, 0.0))
	_add_bone(BREAST_L, 2, BREAST_OFFSET)
	_add_bone(BREAST_R, 2, Vector3(-BREAST_OFFSET.x, BREAST_OFFSET.y, BREAST_OFFSET.z))
	_add_bone(GLUTE_L, 0, GLUTE_OFFSET)
	_add_bone(GLUTE_R, 0, Vector3(-GLUTE_OFFSET.x, GLUTE_OFFSET.y, GLUTE_OFFSET.z))
	_jiggle_bones = PackedInt32Array(
		[bone(BREAST_L), bone(BREAST_R), bone(GLUTE_L), bone(GLUTE_R)]
	)


func _add_bone(bone_name: StringName, parent: int, local_origin: Vector3) -> void:
	var index := skeleton.add_bone(String(bone_name))
	skeleton.set_bone_parent(index, parent)
	# rest basis 를 단위행렬로 두면 본 로컬축 = 월드축이라 이해하기 쉽다.
	# 실제 리그는 본마다 축이 제각각이라 Jiggle 구현에서 늘 이 부분이 함정이 된다.
	skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, local_origin))
	skeleton.reset_bone_poses()


func _build_mesh() -> ArrayMesh:
	var breast_l := bone(BREAST_L)
	var breast_r := bone(BREAST_R)
	var glute_l := bone(GLUTE_L)
	var glute_r := bone(GLUTE_R)
	var hips := bone(HIPS)
	var spine := bone(SPINE)
	var chest := bone(CHEST)
	var neck := bone(NECK)

	var jiggle_set := _jiggle_bones
	# RGB 는 눈으로 보는 색, [b]알파는 Jiggle 가중치 그 자체[/b]다.
	# 데모 08의 정점 셰이더가 이 알파를 읽어 "어디를 얼마나 밀지"를 정한다.
	# 스키닝 없이 흔들려면 가중치를 메쉬 어딘가에 실어 보내야 하는데, 정점 색이 가장 싸다.
	var color_fn := func(weights: Dictionary) -> Color:
		var amount := 0.0
		for jiggle_bone in jiggle_set:
			amount += float(weights.get(jiggle_bone, 0.0))
		amount = clampf(amount, 0.0, 1.0)
		var color := SKIN_COLOR.lerp(JIGGLE_COLOR, amount)
		color.a = amount
		return color

	# 몸통: 높이에 따라 Hips → Spine → Chest → Neck 로 가중치가 넘어간다.
	var torso_fn := func(position: Vector3) -> Dictionary:
		var a := smoothstep(HIPS_Y, SPINE_Y, position.y)
		var b := smoothstep(SPINE_Y, CHEST_Y, position.y)
		var c := smoothstep(CHEST_Y, NECK_Y, position.y)
		return {
			hips: 1.0 - a,
			spine: a * (1.0 - b),
			chest: b * (1.0 - c),
			neck: c,
		}

	var hips_fn := ProcSkin.single_bone(hips)
	var chest_fn := ProcSkin.single_bone(chest)
	var neck_fn := ProcSkin.single_bone(neck)

	var st := ProcSkin.begin()
	ProcSkin.add_capsule(
		st, Vector3(0.0, 0.86, 0.0), Vector3(0.0, 1.30, 0.0), 0.125, torso_fn, color_fn
	)
	ProcSkin.add_ellipsoid(
		st, Vector3(0.0, 1.47, 0.0), Vector3(0.10, 0.115, 0.10), neck_fn, color_fn, 12, 18
	)
	ProcSkin.add_capsule(
		st, Vector3(0.135, 1.26, 0.0), Vector3(0.20, 0.98, 0.0), 0.042, chest_fn, color_fn, 4, 12
	)
	ProcSkin.add_capsule(
		st, Vector3(-0.135, 1.26, 0.0), Vector3(-0.20, 0.98, 0.0), 0.042, chest_fn, color_fn, 4, 12
	)
	ProcSkin.add_capsule(
		st, Vector3(0.065, 0.92, 0.0), Vector3(0.075, 0.07, 0.0), 0.062, hips_fn, color_fn, 4, 14
	)
	ProcSkin.add_capsule(
		st, Vector3(-0.065, 0.92, 0.0), Vector3(-0.075, 0.07, 0.0), 0.062, hips_fn, color_fn, 4, 14
	)

	# 흔들리는 덩어리들. 뿌리 쪽에 전이 구간을 둬야 회전할 때 표면이 꺾이지 않는다.
	var breast_origin_l := Vector3(BREAST_OFFSET.x, CHEST_Y + BREAST_OFFSET.y, BREAST_OFFSET.z)
	var breast_origin_r := Vector3(-BREAST_OFFSET.x, CHEST_Y + BREAST_OFFSET.y, BREAST_OFFSET.z)
	var glute_origin_l := Vector3(GLUTE_OFFSET.x, HIPS_Y + GLUTE_OFFSET.y, GLUTE_OFFSET.z)
	var glute_origin_r := Vector3(-GLUTE_OFFSET.x, HIPS_Y + GLUTE_OFFSET.y, GLUTE_OFFSET.z)

	ProcSkin.add_ellipsoid(
		st,
		breast_origin_l + Vector3(0.0, -0.01, 0.043),
		Vector3(0.072, 0.072, 0.072),
		ProcSkin.blend_along_axis(chest, breast_l, breast_origin_l, Vector3.BACK, -0.03, 0.05),
		color_fn
	)
	ProcSkin.add_ellipsoid(
		st,
		breast_origin_r + Vector3(0.0, -0.01, 0.043),
		Vector3(0.072, 0.072, 0.072),
		ProcSkin.blend_along_axis(chest, breast_r, breast_origin_r, Vector3.BACK, -0.03, 0.05),
		color_fn
	)
	ProcSkin.add_ellipsoid(
		st,
		glute_origin_l + Vector3(0.0, -0.015, -0.038),
		Vector3(0.080, 0.090, 0.076),
		ProcSkin.blend_along_axis(hips, glute_l, glute_origin_l, Vector3.FORWARD, -0.02, 0.06),
		color_fn
	)
	ProcSkin.add_ellipsoid(
		st,
		glute_origin_r + Vector3(0.0, -0.015, -0.038),
		Vector3(0.080, 0.090, 0.076),
		ProcSkin.blend_along_axis(hips, glute_r, glute_origin_r, Vector3.FORWARD, -0.02, 0.06),
		color_fn
	)

	return ProcSkin.finish(st, _material)


func _setup_material(ghost: bool) -> void:
	_material.roughness = 0.55
	if ghost:
		# 고스트: "흔들림이 없었다면 어디에 있었을까"를 겹쳐 보여 주는 반투명 몸.
		_material.albedo_color = Color(0.45, 0.85, 1.0, 0.30)
		_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.cull_mode = BaseMaterial3D.CULL_FRONT
		mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		_material.albedo_color = SKIN_COLOR
		_material.vertex_color_use_as_albedo = false
