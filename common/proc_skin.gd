class_name ProcSkin
extends RefCounted

## 프로시저럴 [b]스킨드[/b] 메쉬 생성기. 외부 3D 에셋 없이 코드만으로
## "본을 따라 변형되는 표면"을 만든다.
##
## Jiggle 학습에서 스키닝을 건너뛰면 안 되는 이유:
## 본을 아무리 잘 흔들어도 [b]가중치(weight)가 잘못되면 결과는 엉망[/b]이다.
## 흔들리는 부위의 뿌리에 부드러운 가중치 전이 구간이 없으면 표면이 접히고 끊긴다.
## 그래서 여기서는 가중치를 정점 색으로도 구워 넣어 눈으로 확인할 수 있게 했다.
##
## 사용법:
## [codeblock]
## var st := ProcSkin.begin()
## ProcSkin.add_ellipsoid(st, center, radius, weight_fn, color_fn)
## var mesh := ProcSkin.finish(st, material)
## [/codeblock]
## [param weight_fn] 은 [code]func(pos: Vector3) -> Dictionary[/code] 로
## [code]{ 본_인덱스: 가중치 }[/code] 를 돌려주면 된다(합이 1이 아니어도 정규화된다).

## 정점 하나가 영향을 받을 수 있는 최대 본 개수. 하드웨어 스키닝의 표준값.
const MAX_INFLUENCES := 4


static func begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	# 스킨 슬롯 개수는 반드시 begin() 앞에서 정해야 한다. 뒤에서 부르면 무시된다.
	st.set_skin_weight_count(SurfaceTool.SKIN_4_WEIGHTS)
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


static func finish(st: SurfaceTool, material: Material = null) -> ArrayMesh:
	if material != null:
		st.set_material(material)
	return st.commit()


## 모든 정점을 본 하나에 100% 붙인다(움직이지 않는 부위용).
static func single_bone(index: int) -> Callable:
	return func(_position: Vector3) -> Dictionary:
		return {index: 1.0}


## [param axis] 방향으로 [param bone_a] → [param bone_b] 가중치를 부드럽게 전이시킨다.
##
## Jiggle 본의 뿌리에는 반드시 이런 전이 구간이 필요하다. 전이 없이 딱 잘라
## 나누면 본이 회전할 때 그 경계에서 표면이 칼로 자른 듯 꺾인다.
static func blend_along_axis(
	bone_a: int, bone_b: int, origin: Vector3, axis: Vector3, start: float, end: float
) -> Callable:
	var direction := axis.normalized()
	return func(position: Vector3) -> Dictionary:
		var t := smoothstep(start, end, (position - origin).dot(direction))
		return {bone_a: 1.0 - t, bone_b: t}


## 타원체(구를 축별로 늘린 것). 가슴·엉덩이·머리 같은 덩어리에 쓴다.
static func add_ellipsoid(
	st: SurfaceTool,
	center: Vector3,
	radius: Vector3,
	weight_fn: Callable,
	color_fn: Callable = Callable(),
	rings: int = 16,
	segments: int = 24,
) -> void:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var weights: Array[Dictionary] = []
	for ring in rings + 1:
		var phi := PI * float(ring) / float(rings)
		for segment in segments + 1:
			var theta := TAU * float(segment) / float(segments)
			var unit := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var point := center + unit * radius
			positions.append(point)
			# 타원체의 법선은 단위구 법선과 다르다. 반지름으로 나눠 줘야 한다.
			normals.append(
				Vector3(unit.x / radius.x, unit.y / radius.y, unit.z / radius.z).normalized()
			)
			weights.append(weight_fn.call(point))
	_emit_grid(st, positions, normals, weights, rings + 1, segments + 1, color_fn)


## 캡슐(양 끝이 반구인 원기둥). 몸통·팔·다리에 쓴다.
static func add_capsule(
	st: SurfaceTool,
	from: Vector3,
	to: Vector3,
	radius: float,
	weight_fn: Callable,
	color_fn: Callable = Callable(),
	cap_rings: int = 6,
	segments: int = 20,
) -> void:
	var axis := to - from
	var length := axis.length()
	if length < 0.0001:
		return
	var up := axis / length
	var right := up.cross(Vector3.BACK)
	if right.length_squared() < 0.001:
		right = up.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward := right.cross(up).normalized()
	var frame := Basis(right, up, forward)

	# 위 반구 → (경계 중복) → 아래 반구 순으로 링을 쌓는다.
	# 경계에서 중심이 to 에서 from 으로 갈아타면서 그 사이가 원기둥 옆면이 된다.
	var phis := PackedFloat32Array()
	for i in cap_rings + 1:
		phis.append(PI * 0.5 * float(i) / float(cap_rings))
	for i in cap_rings + 1:
		phis.append(PI * 0.5 + PI * 0.5 * float(i) / float(cap_rings))

	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var weights: Array[Dictionary] = []
	for ring in phis.size():
		var phi := phis[ring]
		var center := to if ring <= cap_rings else from
		for segment in segments + 1:
			var theta := TAU * float(segment) / float(segments)
			var unit := Vector3(sin(phi) * cos(theta), cos(phi), sin(phi) * sin(theta))
			var normal := frame * unit
			var point := center + normal * radius
			positions.append(point)
			normals.append(normal)
			weights.append(weight_fn.call(point))
	_emit_grid(st, positions, normals, weights, phis.size(), segments + 1, color_fn)


## 본 체인을 감싸는 튜브. 머리카락 다발 · 꼬리 · 밧줄에 쓴다.
##
## [param joints] 는 본 원점 n+1개(마지막은 끝점), [param bones] 는 본 인덱스 n개다.
## 가중치는 [b]구간 중앙에서 그 본 100%, 관절에서 이웃과 50:50[/b] 이 되도록 섞는다.
## 이 전이가 없으면 관절마다 표면이 각지게 꺾인다.
static func add_tube(
	st: SurfaceTool,
	joints: PackedVector3Array,
	bones: PackedInt32Array,
	parent_bone: int,
	radii: PackedFloat32Array,
	color_fn: Callable = Callable(),
	rings_per_segment: int = 3,
	sides: int = 8,
) -> void:
	var bone_count := bones.size()
	if bone_count < 1 or joints.size() != bone_count + 1:
		return

	var centers := PackedVector3Array()
	var tangents := PackedVector3Array()
	var ring_radii := PackedFloat32Array()
	var ring_weights: Array[Dictionary] = []
	for segment in bone_count:
		var tangent := (joints[segment + 1] - joints[segment]).normalized()
		# 마지막 구간만 끝 링까지 포함해서 튜브를 닫는다.
		var ring_count := rings_per_segment + (1 if segment == bone_count - 1 else 0)
		for ring in ring_count:
			var u := float(ring) / float(rings_per_segment)
			centers.append(joints[segment].lerp(joints[segment + 1], u))
			tangents.append(tangent)
			ring_radii.append(lerpf(radii[segment], radii[segment + 1], u))
			ring_weights.append(_tube_weights(bones, parent_bone, segment, u))

	# 평행 이송(parallel transport): 이전 링의 기준 벡터를 새 접선에 수직으로 투영해
	# 링마다 프레임을 이어 간다. 매번 새로 만들면 튜브가 제멋대로 꼬인다.
	var reference := _perpendicular(tangents[0])
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var weights: Array[Dictionary] = []
	for ring in centers.size():
		var tangent := tangents[ring]
		var right := reference - tangent * reference.dot(tangent)
		if right.length_squared() < 0.000001:
			right = _perpendicular(tangent)
		right = right.normalized()
		reference = right
		var forward := tangent.cross(right).normalized()
		for side in sides + 1:
			var theta := TAU * float(side) / float(sides)
			var normal := right * cos(theta) + forward * sin(theta)
			positions.append(centers[ring] + normal * ring_radii[ring])
			normals.append(normal)
			weights.append(ring_weights[ring])
	_emit_grid(st, positions, normals, weights, centers.size(), sides + 1, color_fn)


static func _perpendicular(direction: Vector3) -> Vector3:
	var candidate := direction.cross(Vector3.UP)
	if candidate.length_squared() < 0.001:
		candidate = direction.cross(Vector3.RIGHT)
	return candidate.normalized()


## 구간 [param segment] 안의 위치 [param u](0~1)에서의 본 가중치.
static func _tube_weights(
	bones: PackedInt32Array, parent_bone: int, segment: int, u: float
) -> Dictionary:
	var current := bones[segment]
	if u < 0.5:
		var previous_bone := bones[segment - 1] if segment > 0 else parent_bone
		if previous_bone < 0:
			return {current: 1.0}
		var weight_current := 0.5 + u
		return {previous_bone: 1.0 - weight_current, current: weight_current}
	if segment + 1 >= bones.size():
		return {current: 1.0}
	var next_bone := bones[segment + 1]
	var weight_here := 1.5 - u
	return {current: weight_here, next_bone: 1.0 - weight_here}


## (링 × 세그먼트) 격자를 삼각형으로 이어 붙인다.
## Godot은 [b]시계 방향[/b] 감기를 앞면으로 취급한다.
static func _emit_grid(
	st: SurfaceTool,
	positions: PackedVector3Array,
	normals: PackedVector3Array,
	weights: Array[Dictionary],
	rows: int,
	columns: int,
	color_fn: Callable,
) -> void:
	for row in rows - 1:
		for column in columns - 1:
			var i00 := row * columns + column
			var i01 := i00 + 1
			var i10 := i00 + columns
			var i11 := i10 + 1
			_emit_vertex(st, positions, normals, weights, i00, color_fn)
			_emit_vertex(st, positions, normals, weights, i10, color_fn)
			_emit_vertex(st, positions, normals, weights, i11, color_fn)
			_emit_vertex(st, positions, normals, weights, i00, color_fn)
			_emit_vertex(st, positions, normals, weights, i11, color_fn)
			_emit_vertex(st, positions, normals, weights, i01, color_fn)


static func _emit_vertex(
	st: SurfaceTool,
	positions: PackedVector3Array,
	normals: PackedVector3Array,
	weights: Array[Dictionary],
	index: int,
	color_fn: Callable,
) -> void:
	var influences := weights[index]
	st.set_normal(normals[index])
	st.set_color(color_fn.call(influences) if color_fn.is_valid() else Color.WHITE)
	_set_influences(st, influences)
	st.add_vertex(positions[index])


## [code]{본: 가중치}[/code] 를 하드웨어 스키닝이 요구하는 4칸 배열로 정규화한다.
static func _set_influences(st: SurfaceTool, weights: Dictionary) -> void:
	var bones := PackedInt32Array([0, 0, 0, 0])
	var values := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var slot := 0
	var total := 0.0
	for bone: int in weights:
		if slot >= MAX_INFLUENCES:
			break
		var value: float = weights[bone]
		if value <= 0.0001:
			continue
		bones[slot] = bone
		values[slot] = value
		total += value
		slot += 1
	if total <= 0.0:
		values[0] = 1.0
	else:
		for i in MAX_INFLUENCES:
			values[i] /= total
	st.set_bones(bones)
	st.set_weights(values)
