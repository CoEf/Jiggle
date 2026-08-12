class_name CharacterRig
extends Node3D

## 외부에서 가져온 실제 캐릭터(.glb)를 모디파이어가 붙을 수 있는 상태로 감싼다.
##
## 지금까지의 데모는 리그를 [b]코드로 만들었다.[/b] 그래서 본 축이 단위행렬이고,
## 이름도 내가 정했고, rest 자세가 충돌체에 파묻힐 일도 없었다.
## 실제 리그는 [b]셋 다 아니다.[/b] 이 클래스가 하는 일은 그 차이를 흡수하는 것뿐이다.
##
## [b]이 리그에서 실측한 것[/b] (Rigify 계열, 본 183개)
## [codeblock]
## 본이 뻗은 방향   자식 rest 위치가 전부 (0, +len, 0) → 본 로컬 +Y
##                  이 프로젝트의 자작 리그(단위행렬)와 완전히 다르다
## 가슴             breast.L / breast.R  (본은 있지만 이 모델은 가슴 메쉬가 없다)
## 머리카락         Hair_Fringe.* 3마디 · Hair_Side.* 4마디 · Hair_Back.* 2마디
## 치마             Dress_*.001~004  12가닥, Head 가 아니라 spine 의 자식
## 리본             Back_Ribbon_Tail.* 4마디
## 이름 오류        앞리본 왼쪽 뿌리만 "Back" 으로 들어와 있다 → [member MISNAMED_BONES]
## [/codeblock]
##
## 사슬 길이를 코드에 적어 두지 않고 [b]이름 규칙으로 찾는다.[/b] 그래서 모델이 바뀌어
## 앞머리가 4마디에서 3마디가 되어도(실제로 그랬다) 고칠 것이 없다.
##
## [b]tip_axis 를 추측하지 말 것.[/b] 리그마다 다르고, 틀리면 본이 엉뚱한 방향으로 누워
## "시뮬레이션이 안 된다"는 잘못된 결론에 도달한다. [code]tools/inspect_rig.gd[/code] 로 찍어 보고 정한다.

const MODEL := "res://assets/adachi_rigged4/adachi_rigged4.glb"

## 이 리그의 본 로컬축 중 자식 쪽을 향하는 축. 위 실측 결과.
const BONE_AXIS := Vector3.UP

## 흔들 대상 그룹. 이름 규칙만 다르고 처리는 전부 같다.
const HAIR_PREFIX := "Hair_"
const SKIRT_PREFIX := "Dress_"
const RIBBON_TOKEN := "Ribbon"
const BREAST_BONES: Array[String] = ["breast.L", "breast.R"]

## 이 리그의 [b]이름 오류[/b]를 바로잡는 표. [code]실제 본 이름: 원래 뜻한 이름[/code].
##
## 앞리본 왼쪽 뿌리가 [code]Front_Ribbon_Side.01.L[/code] 이 아니라 [code]Back[/code] 으로
## 들어와 있다(오른쪽은 멀쩡하다). 이름 규칙으로만 보면 이 본은 리본이 아니라서
## [b]왼쪽 앞리본 한 가닥이 통째로 빠진다[/b] — 에러도 경고도 없이 그 가닥만 안 흔들린다.
##
## 규칙 자체를 "Back 도 리본"으로 넓히지 않는 이유는, 다른 리그에서 진짜 등뼈를 잡기 때문이다.
## [b]규칙은 규칙대로 두고 예외는 표로 둔다.[/b] 표에 있는 이름은 눈에 보이지만
## 규칙 안에 숨은 예외는 안 보인다.
const MISNAMED_BONES := {"Back": "Front_Ribbon_Side.01.L"}

## 사슬로 인정할 최소 본 개수. 2면 "자유 관절 1개 + 끝점"이라 흔들리기는 한다.
const MIN_CHAIN_BONES := 2

## 충돌체 반지름(골반 너비 배수). [b]절대값으로 박으면 다른 모델에서 전부 틀린다.[/b]
##
## 머리만 [code]adachi_rigged4_jiggle.tscn[/code] 에서 손으로 맞춘 값이다.
## [code]Head[/code] 본 원점은 목 밑이라 계산값(0.60)으로는 구가 턱 밑에 박히고
## 머리통은 비어 있었다 — 머리카락이 두개골을 그냥 통과했다.
## 골반·허벅지는 계산값이 그대로 맞아서 안 건드렸다.
const HEAD_RADIUS_RATIO := 1.065
const HIP_RADIUS_RATIO := 0.62
const THIGH_RADIUS_RATIO := 0.32

## 머리 충돌체 중심(골반 너비 배수). 역시 손으로 맞춘 값이다 — 위로 올리고 뒤통수 쪽으로 뺐다.
##
## [b]반지름 배율 슬라이더를 따라 움직이지 않는다.[/b] 같이 움직이면 충돌체를 키울 때
## 구가 머리 위로 떠올라 "크기를 키웠더니 머리카락이 안 막힌다"가 된다.
const HEAD_OFFSET_RATIO := Vector3(0.0, 2.006, -0.496)

var skeleton: Skeleton3D = null
## 각 항목: { "root": String, "end": String, "bones": int, "length": float }
var hair_chains: Array[Dictionary] = []
var skirt_chains: Array[Dictionary] = []
var ribbon_chains: Array[Dictionary] = []
## 가슴처럼 본 하나로 처리할 것: { "bone": String, "tip_length": float }
var breasts: Array[Dictionary] = []

## 씬에 배치한 충돌체 노드들. 본을 따라다닌다.
var head_collider: JiggleCollider3D = null
var hip_collider: JiggleCollider3D = null
var thigh_colliders: Array[JiggleCollider3D] = []

## 골반 너비. 이 리그의 "몸 크기"를 재는 기준자로 쓴다.
## 충돌체 반지름을 절대값으로 박아 두면 다른 모델에서 전부 틀리기 때문이다.
var hip_width := 0.2

## 모델 파일 자체가 없는 경우. [b]코드 문제와 구분해야 한다[/b] —
## 이 프로젝트의 다른 데모는 전부 외부 에셋이 0개라, 여기만 파일에 의존한다.
var model_missing := false

var _model: Node3D = null
var _collider_scale := 1.0


## 모델을 불러와 붙인다. 실패하면 false.
func build() -> bool:
	if not ResourceLoader.exists(MODEL):
		model_missing = true
		push_warning("CharacterRig: %s 가 없다. 데모 09는 비어 있는 상태로 뜬다." % MODEL)
		return false
	var packed: PackedScene = load(MODEL)
	if packed == null:
		push_error("CharacterRig: %s 를 못 불러왔다" % MODEL)
		return false
	_model = packed.instantiate() as Node3D
	if _model == null:
		return false
	add_child(_model)
	skeleton = _find_skeleton(_model)
	if skeleton == null:
		push_error("CharacterRig: Skeleton3D 가 없다")
		return false

	hair_chains = _discover_chains(
		func(n: String) -> bool: return true_name(n).begins_with(HAIR_PREFIX)
	)
	skirt_chains = _discover_chains(
		func(n: String) -> bool: return true_name(n).begins_with(SKIRT_PREFIX)
	)
	ribbon_chains = _discover_chains(
		func(n: String) -> bool: return true_name(n).contains(RIBBON_TOKEN)
	)
	_discover_breasts()
	_measure()
	_build_colliders()
	return true


## 이름 규칙을 판정할 때 쓸 이름. 리그의 오타를 [member MISNAMED_BONES] 로 걷어낸 것이다.
## [b]사슬에 적어 넣는 이름은 여전히 실제 본 이름[/b]이어야 한다 — 스켈레톤은 오타 쪽만 안다.
static func true_name(bone_name: String) -> String:
	return MISNAMED_BONES.get(bone_name, bone_name)


## 충돌체 반지름을 한꺼번에 키우거나 줄인다. 눈으로 맞추라고 슬라이더로 뺀다.
##
## [b]위치는 안 건드린다.[/b] 충돌체를 키우는 것과 옮기는 것은 다른 일이다.
func set_collider_scale(value: float) -> void:
	_collider_scale = value
	if head_collider != null:
		head_collider.radius = hip_width * HEAD_RADIUS_RATIO * value
	if hip_collider != null:
		hip_collider.radius = hip_width * HIP_RADIUS_RATIO * value
	for collider in thigh_colliders:
		collider.radius = hip_width * THIGH_RADIUS_RATIO * value


## 본의 월드 위치. 모디파이어 [b]바깥[/b]에서 부르므로 rest 값이 나온다 —
## 충돌체를 배치하려고 리그 치수를 재는 지금은 그게 맞다.
func bone_world(bone_name: String) -> Vector3:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0:
		return Vector3.ZERO
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone)).origin


## 메쉬만 숨긴다. 본이 실제로 어떻게 움직이는지 볼 때 쓴다.
func set_model_visible(value: bool) -> void:
	if _model != null:
		_model.visible = value


func all_colliders() -> Array[JiggleCollider3D]:
	var list: Array[JiggleCollider3D] = []
	if head_collider != null:
		list.append(head_collider)
	if hip_collider != null:
		list.append(hip_collider)
	list.append_array(thigh_colliders)
	return list


# --- 탐색 --------------------------------------------------------------------


## 이름 규칙에 맞는 본들을 사슬로 묶는다.
##
## 사슬의 시작은 [b]"위쪽이 끊긴 곳"[/b]이다. 부모가 규칙에 안 맞거나(예: Hair_ 의 부모는 Head),
## 부모가 갈래져서 형제가 여럿이면 거기가 새 사슬의 뿌리다.
func _discover_chains(matches: Callable) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var count := skeleton.get_bone_count()
	for bone in count:
		if not matches.call(skeleton.get_bone_name(bone)):
			continue
		var parent := skeleton.get_bone_parent(bone)
		if parent >= 0 and matches.call(skeleton.get_bone_name(parent)):
			# 부모도 같은 그룹이다. 형제가 나 하나뿐이면 사슬 중간이므로 건너뛴다.
			if _matching_children(parent, matches).size() == 1:
				continue
		# 여기서부터 아래로 한 줄로 이어지는 동안 따라 내려간다.
		var bones := PackedInt32Array([bone])
		var cursor := bone
		while true:
			var children := _matching_children(cursor, matches)
			if children.size() != 1:
				break
			cursor = children[0]
			bones.append(cursor)
		if bones.size() < MIN_CHAIN_BONES:
			continue
		var length := 0.0
		for i in range(1, bones.size()):
			length += skeleton.get_bone_rest(bones[i]).origin.length()
		result.append({
			"root": skeleton.get_bone_name(bones[0]),
			"end": skeleton.get_bone_name(bones[bones.size() - 1]),
			"bones": bones.size(),
			# 마지막 본 뒤에 붙일 끝점 길이. 직전 마디와 같게 두면 자연스럽다.
			"tip_length": skeleton.get_bone_rest(bones[bones.size() - 1]).origin.length(),
			"length": length,
		})
	return result


func _matching_children(bone: int, matches: Callable) -> PackedInt32Array:
	var result := PackedInt32Array()
	for child in skeleton.get_bone_count():
		if skeleton.get_bone_parent(child) != bone:
			continue
		if matches.call(skeleton.get_bone_name(child)):
			result.append(child)
	return result


## 가슴은 사슬이 아니라 본 하나다. 자식 본까지의 거리가 곧 tip_length 다.
func _discover_breasts() -> void:
	breasts = []
	for bone_name in BREAST_BONES:
		var bone := skeleton.find_bone(bone_name)
		if bone < 0:
			continue
		var tip_length := 0.08
		for child in skeleton.get_bone_count():
			if skeleton.get_bone_parent(child) == bone:
				tip_length = skeleton.get_bone_rest(child).origin.length()
				break
		breasts.append({"bone": bone_name, "tip_length": tip_length})


# --- 충돌체 ------------------------------------------------------------------


func _measure() -> void:
	var left := bone_world("thigh.L")
	var right := bone_world("thigh.R")
	var measured := left.distance_to(right)
	if measured > 0.001:
		hip_width = measured


## [JiggleCollider3D] 를 [BoneAttachment3D] 아래에 둔다. 그러면 본을 따라다닌다.
##
## 캡슐은 노드 로컬 [b]+Y[/b] 방향으로 뻗는데, 이 리그는 본 축도 +Y 라
## 어태치먼트 아래에 그냥 놓으면 캡슐이 자동으로 본을 따라 눕는다.
## (본 축이 다른 리그라면 어태치먼트에 회전을 줘야 한다 — 그래서 축을 먼저 재는 것이다.)
func _build_colliders() -> void:
	head_collider = _add_collider("Head", 0.0, "HeadCollider")
	if head_collider != null:
		head_collider.position = hip_width * HEAD_OFFSET_RATIO
	hip_collider = _add_collider("spine", hip_width * 0.55, "HipCollider")
	if hip_collider != null:
		# spine 의 +Y 는 위(가슴 쪽)를 향한다. 골반은 원점보다 아래에 있다.
		hip_collider.position = Vector3(0.0, -hip_width * 0.30, 0.0)

	thigh_colliders = []
	for side in ["L", "R"]:
		var thigh := bone_world("thigh.%s" % side)
		var shin := bone_world("shin.%s" % side)
		var length := thigh.distance_to(shin)
		var collider := _add_collider("thigh.%s" % side, length * 0.8, "ThighCollider_%s" % side)
		if collider == null:
			continue
		# 어태치먼트는 본 원점(허벅지 위쪽)에 있다. 캡슐 중심을 본 가운데로 내린다.
		collider.position = Vector3(0.0, length * 0.4, 0.0)
		thigh_colliders.append(collider)

	set_collider_scale(1.0)


## 내장 [SpringBoneSimulator3D] 가 쓰는 충돌체를 [b]같은 자리에[/b] 붙인다.
##
## 이쪽은 [JiggleCollider3D](자체 노드)를, 내장은 [SpringBoneCollision3D](엔진 노드)를 쓴다.
## 비교를 하려면 위치·반지름이 같아야 하므로 위에서 잰 치수를 그대로 재사용한다.
## 내장 쪽은 [b]본에 직접 붙는다[/b] — [BoneAttachment3D] 가 필요 없다는 점이 다르다.
func attach_spring_bone_colliders() -> void:
	_add_spring_sphere("Head", hip_width * HEAD_RADIUS_RATIO, hip_width * HEAD_OFFSET_RATIO)
	_add_spring_sphere("spine", hip_width * HIP_RADIUS_RATIO, Vector3(0.0, -hip_width * 0.30, 0.0))
	for side in ["L", "R"]:
		var length := bone_world("thigh.%s" % side).distance_to(bone_world("shin.%s" % side))
		var capsule := SpringBoneCollisionCapsule3D.new()
		capsule.name = "SpringCollision_Thigh_%s" % side
		capsule.bone_name = "thigh.%s" % side
		capsule.radius = hip_width * THIGH_RADIUS_RATIO
		capsule.height = maxf(length * 0.8, capsule.radius * 2.0 + 0.001)
		capsule.position = Vector3(0.0, length * 0.4, 0.0)
		skeleton.add_child(capsule)


func _add_spring_sphere(bone_name: String, radius: float, offset: Vector3) -> void:
	if skeleton.find_bone(bone_name) < 0:
		return
	var sphere := SpringBoneCollisionSphere3D.new()
	sphere.name = "SpringCollision_%s" % bone_name
	sphere.bone_name = bone_name
	sphere.radius = radius
	sphere.position = offset
	skeleton.add_child(sphere)


func _add_collider(bone_name: String, height: float, node_name: String) -> JiggleCollider3D:
	if skeleton.find_bone(bone_name) < 0:
		push_warning("CharacterRig: 충돌체를 붙일 본 '%s' 가 없다" % bone_name)
		return null
	var attachment := BoneAttachment3D.new()
	attachment.name = "%sAttachment" % node_name
	skeleton.add_child(attachment)
	# bone_name 은 스켈레톤 자식이 된 [b]뒤에[/b] 넣어야 본 목록에서 찾는다.
	attachment.bone_name = bone_name

	var collider := JiggleCollider3D.new()
	collider.name = node_name
	collider.height = height
	attachment.add_child(collider)
	return collider


func _find_skeleton(node: Node) -> Skeleton3D:
	var found := node as Skeleton3D
	if found != null:
		return found
	for child in node.get_children():
		var result := _find_skeleton(child)
		if result != null:
			return result
	return null
