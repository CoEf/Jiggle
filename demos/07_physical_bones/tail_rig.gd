class_name TailRig
extends Node3D

## 데모 07용 최소 리그: 천장에 매달린 [b]꼬리 하나[/b].
##
## 데모 03의 머리카락과 구조는 같지만, 물리 본(래그돌)과 비교하려면
## 본 하나하나에 충돌 셰이프를 붙여야 해서 훨씬 단순한 모양이 필요하다.

const ANCHOR := Vector3(0.0, 1.35, 0.0)
const SKIN_COLOR := Color(0.78, 0.72, 0.66)

var skeleton: Skeleton3D
var mesh_instance: MeshInstance3D
var bone_names: PackedStringArray = PackedStringArray()
var segment_length := 0.11
var radius := 0.035

var _material := StandardMaterial3D.new()


func build(segments: int, length: float, tail_color: Color) -> void:
	segment_length = length
	skeleton = Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	add_child(skeleton)

	var anchor_bone := skeleton.add_bone("Anchor")
	skeleton.set_bone_parent(anchor_bone, -1)
	skeleton.set_bone_rest(anchor_bone, Transform3D(Basis.IDENTITY, ANCHOR))

	var bones := PackedInt32Array()
	var joints := PackedVector3Array()
	var cursor := ANCHOR
	var parent := anchor_bone
	bone_names = PackedStringArray()
	for index in segments:
		var bone := skeleton.add_bone("T%d" % index)
		skeleton.set_bone_parent(bone, parent)
		skeleton.set_bone_rest(bone, Transform3D(Basis.IDENTITY, Vector3(0.0, -length, 0.0)))
		cursor += Vector3(0.0, -length, 0.0)
		bones.append(bone)
		joints.append(cursor)
		bone_names.append("T%d" % index)
		parent = bone
	joints.append(cursor + Vector3(0.0, -length, 0.0))

	var radii := PackedFloat32Array()
	for i in joints.size():
		radii.append(radius)
	var color_fn := func(_weights: Dictionary) -> Color:
		return tail_color

	var st := ProcSkin.begin()
	ProcSkin.add_tube(st, joints, bones, anchor_bone, radii, color_fn, 3, 10)
	ProcSkin.add_ellipsoid(
		st,
		ANCHOR + Vector3(0.0, 0.05, 0.0),
		Vector3(0.09, 0.05, 0.09),
		ProcSkin.single_bone(anchor_bone),
		func(_w: Dictionary) -> Color: return SKIN_COLOR
	)
	skeleton.reset_bone_poses()

	mesh_instance = MeshInstance3D.new()
	mesh_instance.name = "Tail"
	mesh_instance.mesh = ProcSkin.finish(st, _material)
	skeleton.add_child(mesh_instance)
	mesh_instance.skeleton = NodePath("..")
	mesh_instance.skin = skeleton.create_skin_from_rest_transforms()
	_material.vertex_color_use_as_albedo = true
	_material.roughness = 0.55


func tip_length() -> float:
	return segment_length


func reset_pose() -> void:
	skeleton.reset_bone_poses()
