@tool
class_name JiggleSpring
extends RefCounted

## 스프링-댐퍼 적분기. 이 프로젝트의 모든 Jiggle이 쓰는 최소 단위.
##
## [b]운동 방정식[/b] (축마다 독립적으로 적용):
## [codeblock]
## a = k * (target - x) - c * v + g
## [/codeblock]
## - [code]k[/code] (stiffness) : 복원력 계수. 클수록 단단하고 빠르게 제자리로 돌아온다.
## - [code]c[/code] (damping)   : 감쇠 계수. 클수록 빨리 멈춘다.
## - [code]g[/code] (gravity)   : 상수 가속도. 평형점을 [code]g/k[/code] 만큼 옮기는 것과 정확히 같다.
##
## [b]거동은 감쇠비 하나로 결정된다:[/b] [code]zeta = c / (2 * sqrt(k))[/code]
## [codeblock]
## zeta < 1  부족감쇠  지나쳤다 되돌아오며 출렁인다. 대부분의 Jiggle이 여기.
## zeta = 1  임계감쇠  오버슈트 없이 가장 빠르게 안착. UI 애니메이션용.
## zeta > 1  과감쇠    느리게 스며들 듯 도착. 흔들리지 않는다.
## [/codeblock]
##
## 사람이 다루기 좋은 단위는 k/c 가 아니라 [b]주파수(Hz)와 감쇠비[/b]다.
## [method params_from_frequency] 로 변환해서 쓰는 것을 권장한다.

## 적분 방식. 같은 방정식이라도 어떻게 이산화하느냐에 따라 결과가 완전히 달라진다.
enum Integrator {
	EXPLICIT_EULER, ## 명시적 오일러 — 교육용. dt가 커지면 에너지가 늘어나 발산한다.
	SEMI_IMPLICIT, ## 반암시적(심플렉틱) 오일러 — 게임에서 쓰는 사실상의 표준.
	ANALYTIC, ## 해석적 감쇠 스프링 — 닫힌 해. dt가 아무리 커도 절대 발산하지 않는다.
}

const EPSILON := 0.00001

## 현재 파티클 위치(월드 또는 임의의 기준 공간).
var position := Vector3.ZERO
## 현재 속도.
var velocity := Vector3.ZERO
## 축별 복원력 계수. 세 성분이 다르면 비등방(anisotropic) 스프링이 된다.
var stiffness := Vector3(160.0, 160.0, 160.0)
## 축별 감쇠 계수.
var damping := Vector3(12.0, 12.0, 12.0)
## 상수 가속도(중력 등). 평형점을 옮기는 효과를 낸다.
var gravity := Vector3.ZERO
## 강성/감쇠를 적용할 좌표축. 비등방일 때만 의미가 있다.
## 본에 붙일 때는 보통 부모 본의 회전을 넣는다.
var frame := Basis.IDENTITY
var integrator: Integrator = Integrator.SEMI_IMPLICIT
## 목표점에서 벗어날 수 있는 최대 거리. 0이면 무제한.
## 폭주·터짐을 막는 마지막 안전장치다.
var max_distance := 0.0

# _solve_*() 가 읽고 쓰는 작업용 상태. 매 스텝 할당을 피하려고 멤버로 둔다.
# _x = 평형점 기준 상대 변위, _v = 속도. 둘 다 frame 로컬 좌표계.
var _x := Vector3.ZERO
var _v := Vector3.ZERO


## 주파수(Hz)와 감쇠비로부터 (stiffness, damping) 을 만든다.
## 사람이 감을 잡기 쉬운 유일한 입력 방식이므로 데모는 전부 이걸 쓴다.
## - [param frequency_hz] : 1초에 몇 번 출렁이는가. 2.0 정도가 살집 있는 느낌.
## - [param zeta] : 감쇠비. 0.1~0.3 이 전형적인 Jiggle.
static func params_from_frequency(frequency_hz: float, zeta: float) -> Vector2:
	var omega := TAU * maxf(frequency_hz, 0.001)
	return Vector2(omega * omega, 2.0 * zeta * omega)


## 감쇠비 계산. 슬라이더 옆에 실시간으로 띄워주면 이해가 빠르다.
static func damping_ratio(k: float, c: float) -> float:
	if k <= EPSILON:
		return INF
	return c / (2.0 * sqrt(k))


## 주파수·감쇠비를 세 축 모두에 한 번에 적용한다.
func configure(frequency_hz: float, zeta: float) -> void:
	var kc := params_from_frequency(frequency_hz, zeta)
	stiffness = Vector3.ONE * kc.x
	damping = Vector3.ONE * kc.y


func reset_to(at: Vector3) -> void:
	position = at
	velocity = Vector3.ZERO


func add_impulse(delta_velocity: Vector3) -> void:
	velocity += delta_velocity


## 한 스텝 진행하고 새 위치를 돌려준다.
## - [param target] : 흔들림이 없다면 있어야 할 위치.
## - [param extra_accel] : 스프링과 무관한 외력(바람 등). 속도에 직접 더해진다.
func step(delta: float, target: Vector3, extra_accel: Vector3 = Vector3.ZERO) -> Vector3:
	if delta <= 0.0:
		return position

	# 강성이 축마다 다를 수 있으므로, 모든 계산을 frame 로컬 좌표계에서 한다.
	var inv := frame.inverse()
	_x = inv * (position - target)
	_v = inv * (velocity + extra_accel * delta)

	# 중력은 "평형점을 g/k 만큼 옮기는 것"과 수학적으로 동일하다.
	# 평형점 기준 상대 좌표로 바꿔두면 아래 적분기들이 중력을 몰라도 된다.
	var equilibrium := _equilibrium_offset(inv * gravity)
	_x -= equilibrium

	match integrator:
		Integrator.EXPLICIT_EULER:
			_solve_explicit(delta)
		Integrator.ANALYTIC:
			_solve_analytic(delta)
		_:
			_solve_semi_implicit(delta)

	_x += equilibrium
	position = target + frame * _x
	velocity = frame * _v

	if max_distance > 0.0:
		_clamp_within(target, max_distance)
	return position


## 목표점 주변 구(球) 안으로 강제로 되돌린다.
func _clamp_within(center: Vector3, radius: float) -> void:
	var offset := position - center
	var distance := offset.length()
	if distance <= radius or distance < EPSILON:
		return
	var normal := offset / distance
	position = center + normal * radius
	# 경계를 계속 밀어내는 속도 성분을 지우지 않으면 벽에 붙어 떨린다.
	var outward := velocity.dot(normal)
	if outward > 0.0:
		velocity -= normal * outward


## 상수 가속도 g 가 만드는 평형점 이동량 g/k.
func _equilibrium_offset(accel: Vector3) -> Vector3:
	return Vector3(
		accel.x / stiffness.x if stiffness.x > EPSILON else 0.0,
		accel.y / stiffness.y if stiffness.y > EPSILON else 0.0,
		accel.z / stiffness.z if stiffness.z > EPSILON else 0.0,
	)


## 위치를 [b]옛[/b] 속도로 먼저 갱신한다. 매 스텝 에너지가 조금씩 늘어나
## dt 가 크거나 k 가 크면 눈에 띄게 발산한다. 왜 쓰면 안 되는지 보려고 넣었다.
func _solve_explicit(delta: float) -> void:
	var accel := -_x * stiffness - _v * damping
	_x += _v * delta
	_v += accel * delta


## 속도를 먼저 갱신하고 그 [b]새[/b] 속도로 위치를 옮긴다.
## 한 줄 차이지만 에너지가 보존되는 쪽으로 기울어 훨씬 안정적이다.
func _solve_semi_implicit(delta: float) -> void:
	var accel := -_x * stiffness - _v * damping
	_v += accel * delta
	_x += _v * delta


## 미분방정식의 닫힌 해를 그대로 평가한다. dt 를 아무리 키워도 발산하지 않고,
## 프레임레이트가 바뀌어도 결과가 동일하다. 대신 축별로 따로 풀어야 한다.
func _solve_analytic(delta: float) -> void:
	for axis in 3:
		var k: float = stiffness[axis]
		var c: float = damping[axis]
		var x0: float = _x[axis]
		var v0: float = _v[axis]

		if k <= EPSILON:
			# 스프링이 없으면 감쇠만 남은 자유 운동.
			var decay := exp(-c * delta)
			_x[axis] = x0 + v0 * (1.0 - decay) / maxf(c, EPSILON)
			_v[axis] = v0 * decay
			continue

		var omega := sqrt(k)
		var zeta := c / (2.0 * omega)

		if zeta < 1.0 - EPSILON:
			# 부족감쇠: 지수적으로 줄어드는 진동
			var wd := omega * sqrt(1.0 - zeta * zeta)
			var envelope := exp(-zeta * omega * delta)
			var a1 := x0
			var a2 := (v0 + zeta * omega * x0) / wd
			var cs := cos(wd * delta)
			var sn := sin(wd * delta)
			_x[axis] = envelope * (a1 * cs + a2 * sn)
			_v[axis] = envelope * (
				(-zeta * omega * a1 + wd * a2) * cs - (zeta * omega * a2 + wd * a1) * sn
			)
		elif zeta > 1.0 + EPSILON:
			# 과감쇠: 서로 다른 두 지수의 합
			var root := omega * sqrt(zeta * zeta - 1.0)
			var z1 := -zeta * omega - root
			var z2 := -zeta * omega + root
			var e1 := exp(z1 * delta)
			var e2 := exp(z2 * delta)
			var b1 := (v0 - x0 * z2) / (z1 - z2)
			var b2 := x0 - b1
			_x[axis] = b1 * e1 + b2 * e2
			_v[axis] = b1 * z1 * e1 + b2 * z2 * e2
		else:
			# 임계감쇠: 지수 하나에 1차항이 붙는다
			var envelope := exp(-omega * delta)
			var d1 := x0
			var d2 := v0 + omega * x0
			_x[axis] = (d1 + d2 * delta) * envelope
			_v[axis] = (d2 - omega * (d1 + d2 * delta)) * envelope
