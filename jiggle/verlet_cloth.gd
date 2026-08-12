@tool
class_name JiggleVerletCloth
extends JiggleVerletBody

## 격자 파티클 천. 치마 · 망토 · 깃발에 쓴다.
##
## [JiggleVerletChain] 과 [b]완전히 같은 솔버[/b]다. 제약만 사슬(1줄)에서 격자(2차원)로 바뀐다.
##
## [b]제약 세 종류[/b] — 각각이 무엇을 막는지가 핵심이다.
## [codeblock]
## 구조(structural)  ─│   가로세로 이웃      : 천이 늘어나는 것을 막는다
## 전단(shear)       ╲╱   대각선 이웃        : 정사각형이 마름모로 무너지는 것을 막는다
## 굽힘(bend)        ─ ─  한 칸 건너뛴 이웃  : 종이처럼 접히는 것을 막는다
## [/codeblock]
## 셋 다 [b]똑같은 거리 제약[/b]이다. 누구와 누구를 잇느냐만 다르다.
## 데모에서 하나씩 꺼 보면 각각이 무슨 일을 하고 있었는지 바로 보인다.
##
## 본이 없다는 점도 중요하다. 사슬은 결과를 본 회전으로 읽었지만,
## 천은 [b]파티클 위치가 곧 메쉬 정점[/b]이다. 스키닝 단계가 아예 없다.

var columns := 12
var rows := 10
## 마지막 열이 첫 열과 이어지는지(치마처럼 원통형일 때 true).
var wrap := false

var structural_stiffness := 1.0
var shear_stiffness := 0.7
var bend_stiffness := 0.3
var shear_enabled := true
var bend_enabled := true

## 정점 법선. 메쉬에도 쓰고 바람 계산에도 쓴다.
var normals := PackedVector3Array()

var _structural := PackedInt32Array()
var _structural_rest := PackedFloat32Array()
var _shear := PackedInt32Array()
var _shear_rest := PackedFloat32Array()
var _bend := PackedInt32Array()
var _bend_rest := PackedFloat32Array()
var _indices := PackedInt32Array()
var _uvs := PackedVector2Array()
var _stride := 0


## [param points] 는 (rows+1) × stride 개의 정점을 행 우선으로 나열한 것.
func build(points: PackedVector3Array, grid_columns: int, grid_rows: int, wrapped: bool) -> void:
	columns = grid_columns
	rows = grid_rows
	wrap = wrapped
	_stride = columns if wrap else columns + 1
	setup(points)
	_build_constraints()
	_build_topology()
	update_normals()
	# 천 크기의 몇 배 이상 벗어나면 터진 것으로 본다.
	safety_radius = points[0].distance_to(points[points.size() - 1]) * 3.0 + 1.0


func vertex(row: int, column: int) -> int:
	return row * _stride + column


func structural_pairs() -> PackedInt32Array:
	return _structural


func shear_pairs() -> PackedInt32Array:
	return _shear


func bend_pairs() -> PackedInt32Array:
	return _bend


func constraint_count() -> int:
	var total := _structural_rest.size()
	if shear_enabled:
		total += _shear_rest.size()
	if bend_enabled:
		total += _bend_rest.size()
	return total


## 구조 제약의 평균 길이 오차(m). 반복 횟수를 바꾸면 이 값이 바로 반응한다.
func average_stretch() -> float:
	if _structural_rest.is_empty():
		return 0.0
	var total := 0.0
	for k in _structural_rest.size():
		var a := _structural[k * 2]
		var b := _structural[k * 2 + 1]
		total += absf(positions[a].distance_to(positions[b]) - _structural_rest[k])
	return total / float(_structural_rest.size())


## 바람을 입자별 가속도로 바꾼다.
##
## 핵심은 [b]표면이 바람을 얼마나 정면으로 맞는지[/b](법선과의 내적)에 비례시키는 것이다.
## 이 항이 없으면 천이 통째로 밀리기만 하고 [b]펄럭이지 않는다[/b].
## 펄럭임은 "면이 바람을 맞아 돌아가면 덜 맞게 되고, 그래서 되돌아오는" 되먹임에서 나온다.
func apply_wind(direction: Vector3, strength: float) -> void:
	if strength <= 0.0:
		external_accel = PackedVector3Array()
		return
	if external_accel.size() != positions.size():
		external_accel = PackedVector3Array()
		external_accel.resize(positions.size())
	for i in positions.size():
		external_accel[i] = direction * (strength * absf(normals[i].dot(direction)))


func update_normals() -> void:
	if normals.size() != positions.size():
		normals = PackedVector3Array()
		normals.resize(positions.size())
	normals.fill(Vector3.ZERO)
	for triangle in _indices.size() / 3:
		var a := _indices[triangle * 3]
		var b := _indices[triangle * 3 + 1]
		var c := _indices[triangle * 3 + 2]
		# 면적에 비례한 가중치가 자동으로 붙으므로 따로 정규화하지 않는다.
		var face := (positions[b] - positions[a]).cross(positions[c] - positions[a])
		normals[a] += face
		normals[b] += face
		normals[c] += face
	for i in normals.size():
		var normal := normals[i]
		normals[i] = normal.normalized() if normal.length_squared() > EPSILON else Vector3.UP


## [method ArrayMesh.add_surface_from_arrays] 에 그대로 넘길 배열.
func mesh_arrays() -> Array:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = positions
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = _uvs
	arrays[Mesh.ARRAY_INDEX] = _indices
	return arrays


func _solve_constraints() -> void:
	_solve_pairs(_structural, _structural_rest, structural_stiffness)
	if shear_enabled:
		_solve_pairs(_shear, _shear_rest, shear_stiffness)
	if bend_enabled:
		_solve_pairs(_bend, _bend_rest, bend_stiffness)


func _build_constraints() -> void:
	_structural = PackedInt32Array()
	_structural_rest = PackedFloat32Array()
	_shear = PackedInt32Array()
	_shear_rest = PackedFloat32Array()
	_bend = PackedInt32Array()
	_bend_rest = PackedFloat32Array()
	for row in rows + 1:
		for column in _stride:
			var here := vertex(row, column)
			_add_pair(_structural, _structural_rest, here, _neighbour(row, column, 0, 1))
			_add_pair(_structural, _structural_rest, here, _neighbour(row, column, 1, 0))
			_add_pair(_shear, _shear_rest, here, _neighbour(row, column, 1, 1))
			_add_pair(_shear, _shear_rest, here, _neighbour(row, column, 1, -1))
			_add_pair(_bend, _bend_rest, here, _neighbour(row, column, 0, 2))
			_add_pair(_bend, _bend_rest, here, _neighbour(row, column, 2, 0))


func _add_pair(
	pairs: PackedInt32Array, rest_lengths: PackedFloat32Array, a: int, b: int
) -> void:
	if b < 0 or b == a:
		return
	pairs.append(a)
	pairs.append(b)
	rest_lengths.append(positions[a].distance_to(positions[b]))


## 격자 이웃. 범위를 벗어나면 -1, 원통형이면 열이 감긴다.
func _neighbour(row: int, column: int, row_step: int, column_step: int) -> int:
	var next_row := row + row_step
	if next_row < 0 or next_row > rows:
		return -1
	var next_column := column + column_step
	if wrap:
		next_column = posmod(next_column, columns)
	elif next_column < 0 or next_column > columns:
		return -1
	return next_row * _stride + next_column


func _build_topology() -> void:
	_indices = PackedInt32Array()
	_uvs = PackedVector2Array()
	_uvs.resize(positions.size())
	for row in rows + 1:
		for column in _stride:
			_uvs[vertex(row, column)] = Vector2(
				float(column) / float(columns), float(row) / float(rows)
			)
	for row in rows:
		for column in columns:
			var i00 := _neighbour(row, column, 0, 0)
			var i01 := _neighbour(row, column, 0, 1)
			var i10 := _neighbour(row, column, 1, 0)
			var i11 := _neighbour(row, column, 1, 1)
			if i01 < 0 or i10 < 0 or i11 < 0:
				continue
			# Godot은 시계 방향 감기를 앞면으로 취급한다.
			_indices.append_array(PackedInt32Array([i00, i10, i11, i00, i11, i01]))
