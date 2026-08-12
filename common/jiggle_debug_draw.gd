class_name JiggleDebugDraw
extends MeshInstance3D

## ImmediateMesh 로 매 프레임 다시 그리는 3D 디버그 라인.
##
## 사용 순서:
## [codeblock]
## debug.begin()
## debug.line(a, b, Color.RED)
## debug.sphere(center, 0.1, Color.CYAN)
## debug.end()
## [/codeblock]
##
## Jiggle 학습에서 디버그 드로잉은 장식이 아니라 본체다.
## "어디로 가려 했는데(목표) 지금 어디에 있고(실제) 어느 쪽으로 움직이는가(속도)"를
## 동시에 보지 못하면 파라미터가 무슨 일을 하는지 영영 알 수 없다.

# 색은 취향이 아니라 판독성 문제다. 기즈모는 살색 몸(0.84, 0.66, 0.58) ·
# 하늘색 고스트 · 거의 검은 바닥 위에 동시에 겹쳐 그려지므로,
# 그 셋 중 무엇과도 색상이 겹치지 않는 다섯 가지를 골라야 한다.
# 반투명하게 두면 뒤에 깔린 살색과 섞여 색이 뭉개지므로 알파도 최대한 올린다.
const COLOR_TARGET := Color(0.15, 1.0, 0.45, 1.0) ## 목표(흔들림 없는 위치) — 형광 초록
const COLOR_ACTUAL := Color(1.0, 0.93, 0.15, 1.0) ## 실제 위치(파티클) — 형광 노랑
const COLOR_VELOCITY := Color(1.0, 0.35, 0.9, 1.0) ## 속도 벡터 — 형광 자홍
const COLOR_LINK := Color(1.0, 1.0, 1.0, 0.85) ## 목표-실제 연결선 — 흰색
const COLOR_LIMIT := Color(1.0, 0.28, 0.32, 0.85) ## 제한 범위 — 빨강

var _immediate := ImmediateMesh.new()
var _material := StandardMaterial3D.new()
var _surface_open := false


func _init() -> void:
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.vertex_color_use_as_albedo = true
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.no_depth_test = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh = _immediate
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 라인만 있는 메쉬는 AABB가 0에 가까워 화면 밖으로 판정되어 통째로 사라진다.
	custom_aabb = AABB(Vector3(-500.0, -500.0, -500.0), Vector3(1000.0, 1000.0, 1000.0))


func begin() -> void:
	end()
	_immediate.clear_surfaces()


func end() -> void:
	if not _surface_open:
		return
	_surface_open = false
	_immediate.surface_end()


func line(from: Vector3, to: Vector3, color: Color = Color.WHITE) -> void:
	_open_surface()
	_immediate.surface_set_color(color)
	_immediate.surface_add_vertex(from)
	_immediate.surface_set_color(color)
	_immediate.surface_add_vertex(to)


## 화살촉이 달린 벡터. 속도·가속도·힘을 보여줄 때 쓴다.
func arrow(from: Vector3, direction: Vector3, color: Color = Color.WHITE) -> void:
	var length := direction.length()
	if length < 0.0001:
		return
	var to := from + direction
	line(from, to, color)

	var forward := direction / length
	var side := forward.cross(Vector3.UP)
	if side.length_squared() < 0.001:
		side = forward.cross(Vector3.RIGHT)
	var head := minf(length * 0.25, 0.08)
	side = side.normalized() * head * 0.5
	var base := to - forward * head
	line(to, base + side, color)
	line(to, base - side, color)


## 세 개의 원으로 그린 와이어 구.
func sphere(center: Vector3, radius: float, color: Color = Color.WHITE, segments: int = 20) -> void:
	circle(center, radius, Vector3.RIGHT, Vector3.UP, color, segments)
	circle(center, radius, Vector3.UP, Vector3.BACK, color, segments)
	circle(center, radius, Vector3.RIGHT, Vector3.BACK, color, segments)


## 와이어 캡슐. 두 점이 같으면 구가 된다.
func capsule(from: Vector3, to: Vector3, radius: float, color: Color = Color.WHITE) -> void:
	sphere(from, radius, color, 16)
	if from.distance_squared_to(to) < 0.000001:
		return
	sphere(to, radius, color, 16)
	var axis := (to - from).normalized()
	var right := axis.cross(Vector3.UP)
	if right.length_squared() < 0.001:
		right = axis.cross(Vector3.RIGHT)
	right = right.normalized()
	var forward := axis.cross(right).normalized()
	for i in 4:
		var angle := TAU * float(i) / 4.0
		var offset := (right * cos(angle) + forward * sin(angle)) * radius
		line(from + offset, to + offset, color)


func circle(
	center: Vector3,
	radius: float,
	axis_u: Vector3,
	axis_v: Vector3,
	color: Color = Color.WHITE,
	segments: int = 20,
) -> void:
	var previous := center + axis_u * radius
	for i in range(1, segments + 1):
		var angle := TAU * float(i) / float(segments)
		var point := center + axis_u * (cos(angle) * radius) + axis_v * (sin(angle) * radius)
		line(previous, point, color)
		previous = point


## 작은 십자 표식. 점 하나를 표시할 때.
func cross_mark(at: Vector3, size: float = 0.04, color: Color = Color.WHITE) -> void:
	line(at - Vector3.RIGHT * size, at + Vector3.RIGHT * size, color)
	line(at - Vector3.UP * size, at + Vector3.UP * size, color)
	line(at - Vector3.BACK * size, at + Vector3.BACK * size, color)


func polyline(points: PackedVector3Array, color: Color = Color.WHITE) -> void:
	for i in range(points.size() - 1):
		line(points[i], points[i + 1], color)


## "목표 vs 실제" 한 세트를 통째로 그린다. 데모마다 반복되는 코드라 묶어 두었다.
func spring_gizmo(
	target: Vector3,
	actual: Vector3,
	velocity: Vector3,
	radius: float,
	limit_radius: float = 0.0,
) -> void:
	if limit_radius > 0.0:
		sphere(target, limit_radius, COLOR_LIMIT, 24)
	sphere(target, radius, COLOR_TARGET, 16)
	line(target, actual, COLOR_LINK)
	# 파티클이 이 데모의 주인공인데 십자 하나로는 살 속에 파묻혀 안 보인다.
	# 십자를 목표 구와 비슷한 크기까지 키우고, 작은 구를 덧그려 덩어리로 보이게 한다.
	# (십자만 있으면 축 방향에서 볼 때 선 하나가 점으로 찌그러져 사라진다.)
	cross_mark(actual, radius * 0.9, COLOR_ACTUAL)
	sphere(actual, radius * 0.4, COLOR_ACTUAL, 8)
	arrow(actual, velocity * 0.12, COLOR_VELOCITY)


func _open_surface() -> void:
	if _surface_open:
		return
	# 정점을 하나도 넣지 않은 채 surface_end() 를 부르면 에러가 나므로,
	# 실제로 그릴 게 생겼을 때만 서피스를 연다.
	_immediate.surface_begin(Mesh.PRIMITIVE_LINES, _material)
	_surface_open = true
