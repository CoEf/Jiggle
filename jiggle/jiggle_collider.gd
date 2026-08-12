@tool
@icon("res://jiggle/icons/jiggle_collider.svg")
class_name JiggleCollider3D
extends Node3D

## [JiggleVerletBody.Collider] 를 [b]씬에서 눈으로 배치[/b]하기 위한 래퍼 노드.
##
## 솔버 쪽 충돌체는 그냥 데이터(캡슐 두 점 + 반지름)라 코드로만 만들 수 있었다.
## 그러면 "머리 충돌체를 어디에 둘 것인가"를 숫자를 고쳐 가며 맞춰야 한다.
## 이 노드를 스켈레톤의 [BoneAttachment3D] 아래에 두면 본을 따라다니는 충돌체가 된다.
## 내장 [SpringBoneCollision3D] 가 정확히 같은 형태다.
##
## [b]쓰는 법[/b] — [JiggleChainModifier3D] 의 자식으로 넣거나
## [member JiggleChainModifier3D.collider_paths] 에 등록하면 자동으로 잡힌다.
## [codeblock]
## Skeleton3D
##   ├─ BoneAttachment3D (Head)
##   │    └─ JiggleCollider3D   radius 0.11, height 0.0   (머리 = 구)
##   └─ JiggleChainModifier3D
##        collider_paths = [ "../BoneAttachment3D/JiggleCollider3D" ]
## [/codeblock]
##
## [b]반지름은 노드 스케일을 따르지 않는다.[/b] 월드 단위 그대로다.
## 시뮬레이션이 쓰는 값과 화면에 보이는 값이 어긋나면 디버깅이 불가능해지기 때문에,
## 스케일이라는 두 번째 경로를 아예 만들지 않았다.

## 캡슐(구)의 반지름. 월드 단위.
@export_range(0.001, 2.0, 0.001, "or_greater") var radius := 0.1: set = _set_radius
## 캡슐 축의 길이. 로컬 [b]+Y[/b] 방향으로 뻗는다. [b]0이면 구[/b]가 된다.
@export_range(0.0, 4.0, 0.001, "or_greater") var height := 0.0: set = _set_height

# 매 프레임 새로 만들지 않고 같은 인스턴스를 계속 갱신한다.
# 모디파이어가 이 인스턴스를 배열에 담아 두기 때문에, 새로 만들면 연결이 끊긴다.
var _collider := JiggleVerletBody.Collider.new()


## 솔버가 쓸 충돌체. [b]항상 같은 인스턴스[/b]를 돌려주므로 한 번만 받아 두면 된다.
func to_collider() -> JiggleVerletBody.Collider:
	sync()
	return _collider


## 노드의 현재 월드 변환을 충돌체에 반영한다. 시뮬레이션 스텝 직전에 호출한다.
func sync() -> void:
	var axis := global_transform.basis.y.normalized() * (height * 0.5)
	var origin := global_position
	_collider.point_a = origin - axis
	_collider.point_b = origin + axis
	_collider.radius = radius


## [param from] 아래에 있는 모든 [JiggleCollider3D] 를 모아 솔버용 배열로 만든다.
static func collect(from: Node) -> Array[JiggleVerletBody.Collider]:
	var result: Array[JiggleVerletBody.Collider] = []
	_gather(from, result)
	return result


static func _gather(node: Node, into: Array[JiggleVerletBody.Collider]) -> void:
	for child in node.get_children():
		var collider := child as JiggleCollider3D
		if collider != null:
			into.append(collider.to_collider())
		_gather(child, into)


## 에디터에 노란 경고를 띄운다.
##
## 충돌체는 [b]자리를 정확히 잡아 놓고도 아무 데도 안 물려 있으면 그냥 장식[/b]이 된다.
## 그 상태에서도 에러는 하나도 안 나므로,
## "충돌이 안 먹는다"를 파라미터 문제로 오해하게 된다.
func _get_configuration_warnings() -> PackedStringArray:
	var warnings := PackedStringArray()
	# ① 모디파이어의 자손이면 자동으로 잡힌다.
	var cursor := get_parent()
	while cursor != null:
		if cursor is JiggleChainModifier3D:
			return warnings
		cursor = cursor.get_parent()
	# ② 아니면 누군가 collider_paths 에 등록해 두었어야 한다.
	if _referenced_by_any(_search_root()):
		return warnings
	warnings.append(
		"이 충돌체를 쓰는 모디파이어가 없다. JiggleChainModifier3D 의 자식으로 넣거나 "
		+ "그쪽 collider_paths 에 등록할 것. (코드에서 chain.colliders 를 직접 채운다면 무시해도 된다.)"
	)
	return warnings


## 참조를 찾아볼 범위. 씬 루트가 가장 자연스럽고, 없으면 트리의 꼭대기까지 올라간다.
func _search_root() -> Node:
	if owner != null:
		return owner
	var cursor: Node = self
	while cursor.get_parent() != null:
		cursor = cursor.get_parent()
	return cursor


func _referenced_by_any(node: Node) -> bool:
	var modifier := node as JiggleChainModifier3D
	if modifier != null:
		for path in modifier.collider_paths:
			if modifier.get_node_or_null(path) == self:
				return true
	for child in node.get_children():
		if _referenced_by_any(child):
			return true
	return false


func _set_radius(value: float) -> void:
	radius = value


func _set_height(value: float) -> void:
	height = value


func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		update_configuration_warnings()
