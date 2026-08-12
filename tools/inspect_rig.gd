extends SceneTree

## 외부 리그(.glb 등)의 스켈레톤을 뜯어보는 도구.
##
## [codeblock]
## godot --headless --path <프로젝트> --script tools/inspect_rig.gd
## [/codeblock]
##
## 모디파이어를 실제 캐릭터에 붙일 때 [b]가장 먼저 알아야 하는 것[/b]을 찍는다.
## [codeblock]
## 본 이름 · 부모 · rest 위치 · 자식 개수
## 본 로컬축 중 어느 쪽이 "자식 방향"인가   ← tip_axis 를 정하는 근거
## 사슬 후보(자식이 하나뿐인 본이 이어지는 구간)
## [/codeblock]
##
## 리그마다 본 축이 제각각이라 [b]추측하면 반드시 틀린다.[/b] 찍어 보고 정한다.

const MODEL := "res://assets/adachi_rigged4/adachi_rigged4.glb"


func _initialize() -> void:
	var packed: PackedScene = load(MODEL)
	if packed == null:
		printerr("불러오기 실패: %s" % MODEL)
		quit(1)
		return
	var root := packed.instantiate()
	var skeleton := _find_skeleton(root)
	if skeleton == null:
		printerr("Skeleton3D 를 못 찾았다")
		root.free()
		quit(1)
		return

	print("=== %s ===" % MODEL)
	print("씬 트리")
	_print_tree(root, 0)

	var count := skeleton.get_bone_count()
	print("\n본 %d 개  (스켈레톤 노드: %s)" % [count, skeleton.name])

	# 자식 목록을 먼저 모아 둔다. 사슬 판정에 쓴다.
	var children: Array[PackedInt32Array] = []
	children.resize(count)
	for i in count:
		children[i] = PackedInt32Array()
	for bone in count:
		var parent := skeleton.get_bone_parent(bone)
		if parent >= 0:
			children[parent].append(bone)

	print("\n%-4s %-30s %-30s %-26s %s" % ["idx", "이름", "부모", "rest 위치(부모 기준)", "자식"])
	for bone in count:
		var parent := skeleton.get_bone_parent(bone)
		var rest := skeleton.get_bone_rest(bone)
		print("%-4d %-30s %-30s %-26s %d" % [
			bone,
			skeleton.get_bone_name(bone),
			skeleton.get_bone_name(parent) if parent >= 0 else "-",
			"(%.4f, %.4f, %.4f)" % [rest.origin.x, rest.origin.y, rest.origin.z],
			children[bone].size(),
		])

	_report_axis(skeleton, children, count)
	_report_chains(skeleton, children, count)

	root.free()
	quit(0)


## [b]본이 향한 축[/b]을 통계로 알아낸다.
##
## 자식이 하나인 본에 대해 "자식의 rest 위치"를 정규화하면 그게 곧 이 본이 뻗은 방향이다.
## 그 방향이 어느 로컬축에 가장 가까운지 세어 보면 리그 전체의 관례를 알 수 있다.
## Mixamo·VRM은 대개 +Y 지만, [b]확인하지 않고 가정하면 안 된다.[/b]
func _report_axis(
	skeleton: Skeleton3D, children: Array[PackedInt32Array], count: int
) -> void:
	var axes := {"+X": 0, "-X": 0, "+Y": 0, "-Y": 0, "+Z": 0, "-Z": 0}
	for bone in count:
		if children[bone].size() != 1:
			continue
		var direction := skeleton.get_bone_rest(children[bone][0]).origin
		if direction.length() < 0.00001:
			continue
		direction = direction.normalized()
		var best := "+X"
		var best_dot := -2.0
		for name: String in axes.keys():
			var axis := _axis_vector(name)
			var dot := direction.dot(axis)
			if dot > best_dot:
				best_dot = dot
				best = name
		axes[best] += 1
	print("\n본이 뻗은 방향 (자식 rest 위치 기준, 자식 1개인 본만)")
	for name: String in axes.keys():
		if axes[name] > 0:
			print("  %s : %d 개" % [name, axes[name]])


## 사슬 후보를 찾는다. "자식이 하나뿐인 본"이 3개 이상 이어지면 흔들 만한 사슬이다.
func _report_chains(
	skeleton: Skeleton3D, children: Array[PackedInt32Array], count: int
) -> void:
	print("\n사슬 후보 (자식 1개인 본이 3마디 이상 이어지는 구간)")
	var visited := {}
	for bone in count:
		if visited.has(bone):
			continue
		var parent := skeleton.get_bone_parent(bone)
		# 사슬의 시작 = 부모가 갈래이거나 없는 지점
		if parent >= 0 and children[parent].size() == 1:
			continue
		var chain := PackedInt32Array()
		var cursor := bone
		while cursor >= 0:
			chain.append(cursor)
			visited[cursor] = true
			if children[cursor].size() != 1:
				break
			cursor = children[cursor][0]
		if chain.size() < 3:
			continue
		var total := 0.0
		for i in range(1, chain.size()):
			total += skeleton.get_bone_rest(chain[i]).origin.length()
		print("  %-28s → %-28s  %d 마디, 길이 %.3f m" % [
			skeleton.get_bone_name(chain[0]),
			skeleton.get_bone_name(chain[chain.size() - 1]),
			chain.size(),
			total,
		])


static func _axis_vector(name: String) -> Vector3:
	match name:
		"+X":
			return Vector3.RIGHT
		"-X":
			return Vector3.LEFT
		"+Y":
			return Vector3.UP
		"-Y":
			return Vector3.DOWN
		"+Z":
			return Vector3.BACK
		_:
			return Vector3.FORWARD


func _find_skeleton(node: Node) -> Skeleton3D:
	var skeleton := node as Skeleton3D
	if skeleton != null:
		return skeleton
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _print_tree(node: Node, depth: int) -> void:
	print("%s%s (%s)" % ["  ".repeat(depth), node.name, node.get_class()])
	if depth > 3:
		return
	for child in node.get_children():
		_print_tree(child, depth + 1)
