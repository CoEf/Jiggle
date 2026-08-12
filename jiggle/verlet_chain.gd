@tool
class_name JiggleVerletChain
extends JiggleVerletBody

## 파티클 [b]사슬[/b]. 머리카락 · 꼬리 · 끈처럼 한 줄로 이어진 것에 쓴다.
##
## 적분 · 충돌 · 안전장치는 전부 [JiggleVerletBody] 가 한다.
## 여기서 더하는 것은 [b]사슬에만 있는 제약[/b] 두 가지뿐이다.
## [codeblock]
## 거리 제약  이웃한 두 입자의 간격을 rest 길이로 유지
## 각도 제한  이웃한 두 마디가 꺾일 수 있는 각도를 제한
## [/codeblock]

## 각 구간의 목표 길이.
var rest_lengths := PackedFloat32Array()
## 거리 제약을 한 번에 얼마나 강하게 적용할지(0~1).
var constraint_stiffness := 1.0
## [b]rest 모양으로 되돌아가려는 강성[/b](0~1). 0이면 완전히 흐물흐물하다.
##
## 거리 제약은 [b]길이[/b]만 지키고 [member angle_limit] 은 [b]한계각[/b]만 막는다.
## 그 사이에서 사슬이 어떤 모양이 되든 상관하지 않으므로, 중력만 걸어 두면
## 무엇이든 축 늘어진 밧줄처럼 된다. 치마 · 리본 · 굵은 머리채처럼
## [b]두께가 있어 원래 형태를 어느 정도 유지하는 재질[/b]에는 이것이 필요하다.
##
## [member restore_stiffness] 와는 다르다.
## [codeblock]
## restore_stiffness  절대 위치를 rest 로 끌어당긴다 (사슬 전체를 제자리로)
## shape_stiffness    앞 마디 기준 상대 방향을 rest 로 되돌린다 (굽힘에 저항)
## [/codeblock]
## 그래서 이쪽은 사슬이 통째로 흔들리는 것은 막지 않고 [b]꺾이는 것만[/b] 막는다.
var shape_stiffness := 0.0
## 모양을 되돌리는 힘이 [b]얼마나 탄성적인가[/b](0~1).
##
## Verlet은 속도를 저장하지 않고 [code]p - p_prev[/code] 로 유추한다. 그래서 제약이 입자를
## 옮기면 그 이동이 [b]그대로 속도가 된다.[/b] 모양 보정도 예외가 아니다.
## [codeblock]
## 1.0  보정량이 전부 속도가 된다   → 되돌아오다 반대편으로 넘어간다 = 스프링·고무
## 0.0  previous 도 같이 옮긴다     → 속도가 안 생긴다 = 탄성 없이 모양만 복구
## [/codeblock]
##
## 현실의 천 · 가죽 · 두꺼운 리본은 [b]모양은 유지하지만 튀지는 않는다.[/b]
## 그런 재질은 0에 가깝게 둔다. 스프링 강판 같은 것만 1에 가깝다.
##
## [b]이것은 [enum JiggleVerletBody.CollisionResponse] 와 정확히 같은 이야기다.[/b]
## 위치만 옮기고 previous 를 안 건드리면 Verlet이 없던 속도를 만들어 낸다.
## 충돌에서 폭주를 일으켰던 바로 그 성질이, 여기서는 "고무처럼 튄다"로 나타난다.
var shape_elasticity := 0.0
## 이웃 구간과 벌어질 수 있는 최대 각도(라디안). 0이면 제한 없음.
var angle_limit := 0.0
## 첫 구간의 각도 기준 방향(월드). 보통 rest 자세의 방향을 넣는다.
var root_direction := Vector3.DOWN

## 구간별 [member shape_stiffness] 배수. 비어 있으면 전부 1.0.
##
## 입자별이 아니라 [b]구간별[/b]이다(구간 수 = 입자 수 − 1). 모양 제약은 이웃한 두 마디
## 사이의 관계이지 입자 하나의 성질이 아니기 때문이다.
## 치마에서 "허리는 형태를 지키고 밑단은 흐물거리게"가 이걸로 나온다.
var shape_weights := PackedFloat32Array()

var _pairs := PackedInt32Array()
# 반복 1회분으로 나눠 둔 모양 강성. step() 에서 미리 계산한다.
var _shape_per_iteration := 0.0
# 구간별로 따로 나눠 둔 것. shape_weights 가 있을 때만 채운다.
var _shape_steps := PackedFloat32Array()
var _shape_elasticity := 0.0


func setup(points: PackedVector3Array) -> void:
	super(points)
	rest_lengths = PackedFloat32Array()
	_pairs = PackedInt32Array()
	var total := 0.0
	for i in points.size() - 1:
		var length := points[i].distance_to(points[i + 1])
		rest_lengths.append(length)
		_pairs.append(i)
		_pairs.append(i + 1)
		total += length
	# 0번은 스켈레톤이 위치를 정한다. 시뮬레이션이 건드리면 안 된다.
	if not inverse_mass.is_empty():
		inverse_mass[0] = 0.0
	safety_radius = total * 2.0 + 1.0


## 루트를 스켈레톤이 정한 위치로 강제한다.
func pin_root(position: Vector3) -> void:
	if positions.is_empty():
		return
	move_pinned(0, position)


## 총 길이 오차(m). 제약 반복 횟수를 바꾸면 이 값이 어떻게 변하는지 보면
## "반복 횟수 = 뻣뻣함"이라는 말이 무슨 뜻인지 바로 알 수 있다.
func length_error() -> float:
	var total := 0.0
	for i in rest_lengths.size():
		total += absf(positions[i].distance_to(positions[i + 1]) - rest_lengths[i])
	return total


## 반복 횟수를 바꿔도 [b]한 스텝의 총 효과가 같도록[/b] 모양 강성을 미리 나눠 둔다.
##
## 이 프로젝트에서 충돌 마찰로 이미 한 번 당한 함정이다. 반복 루프 안에서 같은 비율을
## 매번 곱하면 반복 횟수를 올릴 때마다 소리 없이 점점 뻣뻣해진다.
## 반복 횟수는 [b]제약을 얼마나 정확히 푸는가[/b]여야지 [b]재질이 얼마나 단단한가[/b]가 되면 안 된다.
## [b]배수를 곱한 뒤에 나눈다. 순서가 반대면 안 된다.[/b]
## [code]pow[/code] 는 선형이 아니므로 나눠 둔 값에 배수를 곱하면 구간마다 다른 뻣뻣함이 나온다.
func step(delta: float) -> void:
	var total := clampf(shape_stiffness, 0.0, 1.0)
	var inverse_iterations := 1.0 / float(maxi(iterations, 1))
	_shape_per_iteration = 1.0 - pow(1.0 - total, inverse_iterations)
	if shape_weights.size() == rest_lengths.size() and not rest_lengths.is_empty():
		_shape_steps.resize(rest_lengths.size())
		for i in rest_lengths.size():
			var weighted := clampf(total * shape_weights[i], 0.0, 1.0)
			_shape_steps[i] = 1.0 - pow(1.0 - weighted, inverse_iterations)
	else:
		_shape_steps.clear()
	_shape_elasticity = clampf(shape_elasticity, 0.0, 1.0)
	super(delta)


func _solve_constraints() -> void:
	_solve_pairs(_pairs, rest_lengths, constraint_stiffness)
	if _shape_per_iteration > 0.0:
		_solve_shape()
	if angle_limit > 0.0:
		_solve_angle()


## rest 모양으로 되돌린다.
##
## 각 마디를 [b]앞 마디가 실제로 돌아간 만큼[/b] 따라 돌린 자리로 끌어당긴다.
## [codeblock]
## 앞 마디의 rest 방향 → 현재 방향  의 회전을 구한다
## 그 회전을 이번 마디의 rest 방향에 먹인다
## 그 방향으로 rest 길이만큼 간 자리가 "모양을 지켰다면 있었을 위치"다
## [/codeblock]
## 절대 방향이 아니라 [b]앞 마디 기준 상대 방향[/b]을 되돌리는 것이 핵심이다.
## 절대 방향으로 하면 사슬이 통째로 굳어 흔들리지 않는다.
##
## 목표 위치가 항상 [code]positions[i][/code] 에서 정확히 rest 길이만큼 떨어져 있으므로
## 거리 제약과 싸우지 않는다.
func _solve_shape() -> void:
	if rest_positions.size() != positions.size():
		return
	var weighted := _shape_steps.size() == rest_lengths.size()
	for i in rest_lengths.size():
		if inverse_mass[i + 1] <= 0.0:
			continue
		var per_iteration := _shape_steps[i] if weighted else _shape_per_iteration
		if per_iteration <= 0.0:
			continue
		var rest_direction := rest_positions[i + 1] - rest_positions[i]
		var length := rest_direction.length()
		if length < EPSILON:
			continue
		rest_direction /= length

		var swing := Quaternion.IDENTITY
		if i > 0:
			var previous_rest := rest_positions[i] - rest_positions[i - 1]
			var previous_current := positions[i] - positions[i - 1]
			if previous_rest.length_squared() > EPSILON and previous_current.length_squared() > EPSILON:
				previous_rest = previous_rest.normalized()
				previous_current = previous_current.normalized()
				# 정확히 반대 방향이면 회전축이 정해지지 않는다. 그냥 건너뛴다.
				if previous_rest.dot(previous_current) > -0.9999:
					swing = Quaternion(previous_rest, previous_current)

		var target := positions[i] + (swing * rest_direction) * rest_lengths[i]
		var correction := (target - positions[i + 1]) * per_iteration
		positions[i + 1] += correction
		# 이 이동을 Verlet은 "속도"로 읽는다. previous 를 같이 옮긴 만큼 그 속도가 사라진다.
		# 안 옮기면(탄성 1) 되돌리는 힘이 전부 운동에너지가 되어 반대편으로 넘어간다 = 스프링.
		previous[i + 1] += correction * (1.0 - _shape_elasticity)


## 각도 제한: 이웃한 두 구간이 꺾일 수 있는 각도를 제한한다.
## 이게 없으면 머리카락이 자기 자신 위로 접혀 스킨드 메쉬가 뒤집힌다.
func _solve_angle() -> void:
	for i in rest_lengths.size():
		var reference := root_direction
		if i > 0:
			reference = (positions[i] - positions[i - 1]).normalized()
		if reference.length_squared() < 0.5:
			continue
		var offset := positions[i + 1] - positions[i]
		var length := offset.length()
		if length < EPSILON:
			continue
		var direction := offset / length
		var angle := reference.angle_to(direction)
		if angle <= angle_limit:
			continue
		var axis := reference.cross(direction)
		if axis.length_squared() < EPSILON:
			continue
		positions[i + 1] = positions[i] + reference.rotated(axis.normalized(), angle_limit) * length
