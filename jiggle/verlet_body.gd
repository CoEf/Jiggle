@tool
class_name JiggleVerletBody
extends RefCounted

## Verlet 시뮬레이션의 공통 뼈대. 사슬([JiggleVerletChain])과 천([JiggleVerletCloth])이 함께 쓴다.
##
## [b]사슬과 천은 같은 솔버다.[/b] 적분·충돌·안전장치가 전부 동일하고,
## 오직 [method _solve_constraints] 안에서 [b]무엇을 제약하는가[/b]만 다르다.
## [codeblock]
## 사슬 : 이웃한 두 입자의 거리 + 꺾이는 각도
## 천   : 격자의 가로세로(구조) + 대각선(전단) + 한 칸 건너(굽힘)
## [/codeblock]
##
## Verlet의 핵심은 [b]속도를 저장하지 않는다[/b]는 것이다. 이전 위치로부터 유추한다.
## [codeblock]
## v ≈ (p - p_prev) / dt
## p_next = p + (p - p_prev) * (1 - drag) + a * dt²
## [/codeblock]
## 위치를 강제로 옮기면 속도도 자동으로 그에 맞게 바뀐다.
## 그래서 "길이를 맞춰라", "벽을 뚫지 마라" 같은 제약을 위치만 고쳐서 공짜로 해결할 수 있다.
##
## 대신 [b]고정 timestep이 필수[/b]다. dt가 프레임마다 흔들리면 속도 유추가 깨진다.

const EPSILON := 0.000001

## 충돌한 입자의 속도를 어떻게 처리할지. 이 선택 하나로 결과가 완전히 달라진다.
enum CollisionResponse {
	NAIVE, ## 위치만 밀어낸다. Verlet이 그 이동을 속도로 착각해 [b]폭주한다[/b].
	KEEP_VELOCITY, ## 이전 위치도 같이 민다. 폭주는 없지만 파고드는 속도가 남아 [b]표면에서 튄다[/b].
	STABLE, ## 파고드는 법선 속도를 없애고 접선 속도만 마찰로 깎는다. 접촉이 안정된다.
}

## 현재 위치.
var positions := PackedVector3Array()
## 직전 스텝의 위치. 이것이 곧 속도 정보다.
var previous := PackedVector3Array()
## 이번 프레임의 rest 위치(월드). 복원력이 여기로 끌어당긴다.
var rest_positions := PackedVector3Array()
## 역질량. 0이면 고정점(kinematic)이라 어떤 제약도 이 입자를 못 움직인다.
var inverse_mass := PackedFloat32Array()
## 이번 스텝에 닿은 면의 법선 누적. 0이면 아무 데도 안 닿았다는 뜻.
## 데모가 이걸 읽어 "지금 어느 입자가 충돌 중인지"를 화면에 표시한다.
var contact_normals := PackedVector3Array()
## 입자별 추가 가속도(바람 등). 비어 있으면 무시한다.
var external_accel := PackedVector3Array()
## 모든 입자에 똑같이 걸리는 외력. 내장 [SpringBoneSimulator3D] 의 같은 이름 속성과 대응한다.
var external_force := Vector3.ZERO

var gravity := Vector3.DOWN * 9.0
## 매 스텝 속도에서 깎아내는 비율. 공기 저항 겸 안정화 장치.
var drag := 0.03
## rest 자세로 되돌리려는 스프링 강성. 0이면 중력에 완전히 내맡긴다.
var restore_stiffness := 0.0
## 제약 반복 횟수. 늘릴수록 뻣뻣하고 정확해진다.
var iterations := 6

# --- 입자별 가중치 ------------------------------------------------------------
#
# 사슬 하나가 통째로 한 값을 쓰면 [b]뿌리와 끝이 똑같이 뻣뻣하다.[/b] 머리카락에서 가장 흔히
# 원하는 "끝으로 갈수록 부드럽게"가 그래서 안 나온다. 아래 배열이 그 자리를 메운다.
#
# [b]비어 있으면 전부 1.0[/b] — 즉 아무것도 안 넣으면 지금까지와 완전히 같다.
# 크기가 입자 수와 다르면 무시한다. 잘못 채워진 배열이 조용히 절반만 먹는 것보다,
# 통째로 무시되어 "곡선이 아예 안 먹네"가 되는 편이 원인을 찾기 쉽다.
#
# 곡선 자체는 노드/리소스 쪽 일이다([JiggleChainSettings]). 솔버는 이미 뽑아 놓은 배수만 쓴다.

## 입자별 [member drag] 배수.
var drag_weights := PackedFloat32Array()
## 입자별 [member restore_stiffness] 배수.
var restore_weights := PackedFloat32Array()
## 입자별 [member particle_radius] 배수.
var radius_weights := PackedFloat32Array()

var colliders: Array[Collider] = []
## 파티클 자체의 두께. 충돌 시 이만큼 여유를 둔다.
var particle_radius := 0.008
var collision_response: CollisionResponse = CollisionResponse.STABLE
## 표면을 스칠 때 접선 속도를 얼마나 깎을지(1/60초 기준). 0이면 얼음처럼 미끄러진다.
## [constant CollisionResponse.STABLE] 일 때만 의미가 있다.
var collision_friction := 0.2
## rest 위치에서 이만큼 벗어나면 터진 것으로 보고 되돌린다.
var safety_radius := 10.0
## 안전장치가 실제로 되돌린 횟수. [b]0이 아니면 무언가 잘못되고 있다는 뜻이다.[/b]
##
## 이 값을 밖으로 뺀 이유 — 안전장치는 조용히 일한다. 터진 사슬을 rest 로 돌려놓으므로
## 화면에서는 "사슬이 순간적으로 딱 굳었다 풀리는" 정도로만 보이고, 변위를 재도
## 이미 복구된 뒤라 0이 나온다. [b]증상이 지표에 안 잡히는 종류의 실패다.[/b]
## 세는 것만으로 순간이동·과속 문제가 눈에 보이게 된다.
var safety_resets := 0


func setup(points: PackedVector3Array) -> void:
	safety_resets = 0
	positions = points.duplicate()
	previous = points.duplicate()
	rest_positions = points.duplicate()
	inverse_mass = PackedFloat32Array()
	inverse_mass.resize(points.size())
	inverse_mass.fill(1.0)
	contact_normals = PackedVector3Array()
	contact_normals.resize(points.size())


func reset_to(points: PackedVector3Array) -> void:
	if points.size() != positions.size():
		setup(points)
		return
	positions = points.duplicate()
	previous = points.duplicate()
	rest_positions = points.duplicate()


## 매 프레임 갱신되는 rest 위치. 몸이 움직이면 rest도 따라 움직인다.
func set_rest(points: PackedVector3Array) -> void:
	rest_positions = points


## 이 입자를 고정점으로 만든다(시뮬레이션이 못 건드림).
func pin(index: int) -> void:
	inverse_mass[index] = 0.0


## 고정점을 지정한 위치로 옮긴다. 속도가 생기지 않게 이전 위치도 같이 옮긴다.
func move_pinned(index: int, position: Vector3) -> void:
	positions[index] = position
	previous[index] = position


## [b]기준 좌표계가 움직인 만큼 파티클을 같이 데려간다.[/b]
##
## 파티클은 월드 공간에 있다. 그것만으로 관성이 공짜로 생기는 것이 이 솔버의 핵심이지만
## ([JiggleBoneModifier3D] 주석 참고), [b]대가는 몸이 순간이동하면 사슬만 제자리에 남는다[/b]는
## 것이다. 그러면 rest 에서 수 미터 떨어져 [method _enforce_safety] 가 통째로 되돌린다.
##
## [param motion] 은 기준 좌표계의 [b]이번 프레임 변화량[/b](= 지금 × 직전의 역).
## [param factor] 가 1이면 완전히 따라가 관성이 0이 되고, 0이면 지금까지처럼 전부 뒤처진다.
##
## [b]previous 도 같은 양만큼 옮긴다.[/b] 좌표계가 바뀐 것이지 힘이 걸린 것이 아니므로
## 속도가 생기면 안 된다. 3-⑬ 에서 배운 것과 같은 이야기다 —
## Verlet에서 위치를 옮기는 코드를 쓸 때마다 previous 를 어떻게 할지 같이 정해야 한다.
func carry(motion: Transform3D, factor: float) -> void:
	if positions.is_empty() or factor <= 0.0:
		return
	for i in positions.size():
		var offset := (motion * positions[i] - positions[i]) * factor
		positions[i] += offset
		previous[i] += offset


func step(delta: float) -> void:
	if positions.size() < 2:
		return
	_integrate(delta)
	for i in contact_normals.size():
		contact_normals[i] = Vector3.ZERO
	for iteration in iterations:
		_solve_constraints()
		_solve_collision()
	# 속도 보정은 반복 안이 아니라 [b]스텝당 한 번[/b]만 해야 한다.
	# 반복마다 마찰을 걸면 반복 횟수를 올릴 때마다 천이 더 끈끈해진다.
	if collision_response == CollisionResponse.STABLE:
		_resolve_contact_velocity(delta)
	_enforce_safety()


## 하위 클래스가 채우는 부분. 반복 루프 안에서 매번 호출된다.
func _solve_constraints() -> void:
	pass


func _integrate(delta: float) -> void:
	var dt2 := delta * delta
	var has_external := external_accel.size() == positions.size()
	var has_drag_weights := drag_weights.size() == positions.size()
	var has_restore_weights := restore_weights.size() == positions.size()
	for i in positions.size():
		if inverse_mass[i] <= 0.0:
			previous[i] = positions[i]
			continue
		var accel := gravity + external_force
		var restore := restore_stiffness
		if has_restore_weights:
			restore *= restore_weights[i]
		if restore > 0.0:
			# 데모 01의 스프링을 그대로 파티클에 얹은 것이다.
			# 이게 없으면 한 번 흐트러진 뒤 영영 제자리로 돌아오지 않는다.
			accel += (rest_positions[i] - positions[i]) * restore
		if has_external:
			accel += external_accel[i]
		# 배수를 곱한 뒤 반드시 자른다. drag 0.4 에 배수 3 이면 (1 - 1.2) 가 되어
		# 속도의 [b]부호가 뒤집힌다[/b] — 감쇠가 아니라 매 스텝 진동하는 장치가 된다.
		var particle_drag := drag
		if has_drag_weights:
			particle_drag = clampf(drag * drag_weights[i], 0.0, 1.0)
		var velocity := (positions[i] - previous[i]) * (1.0 - particle_drag)
		previous[i] = positions[i]
		positions[i] += velocity + accel * dt2


## 거리 제약(Jakobsen/PBD): 두 입자를 목표 길이가 되도록 서로 당기거나 민다.
## 역질량 비율로 나눠 주면 고정점은 안 움직이고 자유 입자만 움직인다.
##
## [b]하나를 고치면 옆 제약이 다시 어긋난다.[/b] 그래서 여러 번 반복한다.
## 반복 횟수가 곧 뻣뻣함이다.
func _solve_pairs(
	pairs: PackedInt32Array, rest_lengths: PackedFloat32Array, stiffness: float
) -> void:
	if stiffness <= 0.0:
		return
	for k in rest_lengths.size():
		var a := pairs[k * 2]
		var b := pairs[k * 2 + 1]
		var weight_a := inverse_mass[a]
		var weight_b := inverse_mass[b]
		var total := weight_a + weight_b
		if total <= 0.0:
			continue
		var offset := positions[b] - positions[a]
		var distance := offset.length()
		if distance < EPSILON:
			continue
		var correction := offset * ((distance - rest_lengths[k]) / distance) * stiffness
		positions[a] += correction * (weight_a / total)
		positions[b] -= correction * (weight_b / total)


## 충돌: 파고든 입자를 표면 위로 밀어낸다.
##
## [b]여기가 Verlet 충돌 사고의 90%가 나오는 곳이다.[/b] 세 단계로 나눠 볼 수 있다.
##
## [b]① 위치만 밀어낸다([constant CollisionResponse.NAIVE])[/b]
## Verlet은 그 이동을 "속도"로 착각한다([code]v ≈ p - p_prev[/code]).
## 표면에 눌린 입자는 매 스텝 밀려나며 매번 새 속도를 얻고, 결국 무한대로 날아간다.
##
## [b]② 이전 위치도 같이 민다([constant CollisionResponse.KEEP_VELOCITY])[/b]
## 속도가 정확히 보존되므로 폭주는 사라진다. 하지만 [b]파고들던 속도가 그대로 남아[/b]
## 다음 스텝에 또 파고들고 또 밀려난다. 표면에 닿는 부위만 눈에 띄게 튄다.
##
## [b]③ 접촉을 안정화한다([constant CollisionResponse.STABLE])[/b]
## 밀어낸 뒤 [b]면으로 파고드는 법선 속도를 제거[/b]한다([method _resolve_contact_velocity]).
func _solve_collision() -> void:
	if colliders.is_empty():
		return
	var has_radius_weights := radius_weights.size() == positions.size()
	for i in positions.size():
		if inverse_mass[i] <= 0.0:
			continue
		var radius := particle_radius
		if has_radius_weights:
			radius = maxf(particle_radius * radius_weights[i], 0.0)
		for collider in colliders:
			var closest := collider.closest_point(positions[i])
			var offset := positions[i] - closest
			var distance := offset.length()
			var minimum := collider.radius + radius
			if distance >= minimum:
				continue
			var normal := Vector3.UP
			if distance >= EPSILON:
				normal = offset / distance
			var target := closest + normal * minimum
			if collision_response == CollisionResponse.KEEP_VELOCITY:
				# 반복마다 이전 위치를 같이 옮긴다.
				# 제약이 도로 끌어당기면 그 왕복이 전부 previous 에 누적되어
				# 있지도 않은 속도가 만들어진다. 이게 표면에서 튀는 두 번째 원인이다.
				previous[i] += target - positions[i]
			positions[i] = target
			contact_normals[i] += normal


## 닿은 입자의 속도를 접촉 조건에 맞게 고친다. [b]스텝당 딱 한 번만[/b] 호출한다.
##
## 법선 성분을 통째로 버리고 접선 성분만 남긴다(완전 비탄성 접촉).
## - 파고들던 속도가 사라지므로 다음 스텝에 또 파고들지 않는다 → 튀지 않는다.
## - 밀어내기가 만든 바깥쪽 속도도 같이 사라지므로 에너지가 늘어날 수 없다 → 폭주하지 않는다.
##
## 접선 성분은 밀어내기의 영향을 받지 않는다(밀어내기는 순수히 법선 방향이므로).
## 즉 여기 남는 속도는 [b]충돌 전의 진짜 접선 속도[/b]다.
func _resolve_contact_velocity(delta: float) -> void:
	# 마찰은 1/60초 기준으로 정의하고 실제 dt에 맞춰 환산한다.
	# 이렇게 안 하면 서브스텝 주기를 바꿀 때마다 미끄러짐이 달라진다.
	var retain := pow(1.0 - clampf(collision_friction, 0.0, 1.0), delta * 60.0)
	for i in positions.size():
		var normal := contact_normals[i]
		if normal.length_squared() < EPSILON:
			continue
		normal = normal.normalized()
		var velocity := positions[i] - previous[i]
		var tangent := velocity - normal * velocity.dot(normal)
		previous[i] = positions[i] - tangent * retain


## 마지막 안전장치. 어떤 이유로든 터졌다면 조용히 rest 자세로 되돌린다.
##
## 시뮬레이션은 언제든 폭주할 수 있다는 전제로 짜야 한다.
## 한 번 무한대가 나오면 그 프레임부터 메쉬 전체가 사라지고, 원인을 찾기도 어려워진다.
func _enforce_safety() -> void:
	for i in positions.size():
		var length := (positions[i] - rest_positions[i]).length()
		if is_finite(length) and length <= safety_radius:
			continue
		safety_resets += 1
		reset_to(rest_positions)
		return


## 캡슐 충돌체. 두 점이 같으면 그냥 구가 된다 — 코드 경로가 하나로 줄어든다.
##
## 씬에서 눈으로 배치하고 싶으면 [JiggleCollider3D] 노드를 쓴다.
class Collider:
	extends RefCounted

	var point_a := Vector3.ZERO
	var point_b := Vector3.ZERO
	var radius := 0.1

	func _init(from: Vector3 = Vector3.ZERO, to: Vector3 = Vector3.ZERO, size: float = 0.1) -> void:
		point_a = from
		point_b = to
		radius = size

	## 선분 위에서 [param position] 에 가장 가까운 점.
	func closest_point(position: Vector3) -> Vector3:
		var axis := point_b - point_a
		var length_squared := axis.length_squared()
		if length_squared < 0.000001:
			return point_a
		var t := clampf((position - point_a).dot(axis) / length_squared, 0.0, 1.0)
		return point_a + axis * t
