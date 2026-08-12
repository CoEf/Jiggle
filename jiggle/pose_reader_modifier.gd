@tool
@icon("res://jiggle/icons/jiggle_pose_reader.svg")
class_name JigglePoseReader3D
extends SkeletonModifier3D

## 앞선 모디파이어들이 만들어 낸 [b]결과 포즈[/b]를 밖에서 읽을 수 있게 받아 두는 모디파이어.
##
## [b]이게 왜 필요한가[/b]
##
## [SkeletonModifier3D] 가 [method Skeleton3D.set_bone_pose_rotation] 로 쓴 결과는
## 스키닝에는 반영되지만, [b]바깥에서 [method Skeleton3D.get_bone_global_pose] 로 읽으면
## 모디파이어가 돌기 전의 값(대개 rest)이 나온다.[/b] 스켈레톤이 모디파이어 처리를 끝낸 뒤
## 로컬 포즈를 원래대로 되돌리기 때문이다.
##
## 실제로 이 프로젝트에서 겪은 일:
## 내장 [SpringBoneSimulator3D] 의 결과를 [method Skeleton3D.get_bone_global_pose] 로 읽었더니
## 늘 rest 값이 나와서 "내장이 동작하지 않는다"고 한참을 오해했다. 실제로는 잘 돌고 있었다.
##
## 결과를 읽는 방법은 두 가지뿐이다.
## [codeblock]
## 1. 이 클래스처럼 [b]뒤에[/b] 붙인 모디파이어에서 읽는다 (자식 순서 = 실행 순서)
## 2. BoneAttachment3D 를 붙여 그 노드의 global_transform 을 읽는다
## [/codeblock]
## 둘의 결과는 완전히 같다(직접 확인함).
##
## [b]사용법[/b] — 읽고 싶은 모디파이어보다 [b]아래[/b]에 두어야 한다.
## [codeblock]
## Skeleton3D
##   ├─ JiggleChainModifier3D
##   └─ JigglePoseReader3D     ← 여기서 읽어야 실제 결과가 나온다
## [/codeblock]

## 본 인덱스별 월드 위치. 스켈레톤 자신의 global_transform 까지 곱해 둔 값이다.
var world_positions := PackedVector3Array()


# 형제 순서가 바뀌는 것을 알려면 부모의 신호를 받아야 한다. 재부모화에 대비해 들고 있는다.
var _watched_parent: Node = null


func _process_modification_with_delta(_delta: float) -> void:
	var skeleton := get_skeleton()
	if skeleton == null:
		return
	var count := skeleton.get_bone_count()
	if world_positions.size() != count:
		world_positions.resize(count)
	var world := skeleton.global_transform
	for bone in count:
		world_positions[bone] = (world * skeleton.get_bone_global_pose(bone)).origin


## 에디터에 노란 경고를 띄운다.
##
## 이 노드는 [b]순서가 곧 기능[/b]이다. 흔드는 모디파이어보다 위에 두면 아무 에러 없이
## rest 값을 읽어 주고, 그러면 "모디파이어가 동작하지 않는다"는 오진에 그대로 도달한다.
## 이 프로젝트에서 가장 오래 막혔던 문제라, 배치하는 순간 잡아 준다.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	var parent := get_parent()
	if parent != null and parent is not Skeleton3D:
		warnings.append(
			"Skeleton3D 의 직속 자식이어야 한다. 지금은 %s 아래라 에러 하나 없이 그냥 안 돈다."
			% parent.get_class()
		)
		return warnings
	if parent == null:
		return warnings

	var behind := PackedStringArray()
	var found_before := false
	for child in parent.get_children():
		if child == self:
			continue
		if child is not JiggleBoneModifier3D and child is not JiggleChainModifier3D:
			continue
		if child.get_index() < get_index():
			found_before = true
		else:
			behind.append(String(child.name))
	if not behind.is_empty():
		warnings.append(
			"자식 순서 = 실행 순서다. 아래에 있는 %s 의 결과는 안 읽힌다 — 이 노드를 맨 밑으로 내릴 것."
			% ", ".join(behind)
		)
	elif not found_before:
		warnings.append("위에 흔드는 모디파이어가 하나도 없다. 지금은 rest 자세를 읽고 있다.")
	return warnings


func _notification(what: int) -> void:
	if what != NOTIFICATION_PARENTED and what != NOTIFICATION_UNPARENTED:
		return
	# 형제를 위아래로 옮겨도 경고가 따라 바뀌어야 한다. 부모가 그때 신호를 준다.
	if _watched_parent != null and _watched_parent.child_order_changed.is_connected(
		update_configuration_warnings
	):
		_watched_parent.child_order_changed.disconnect(update_configuration_warnings)
	_watched_parent = get_parent()
	if _watched_parent != null:
		_watched_parent.child_order_changed.connect(update_configuration_warnings)
	update_configuration_warnings()
