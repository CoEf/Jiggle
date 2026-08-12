class_name Stimulus
extends RefCounted

## 캐릭터/기준점에 가하는 "자극".
##
## Jiggle은 [b]가만히 있으면 절대 관찰할 수 없다[/b]. 흔들림은 기준점이 움직일 때
## 관성 때문에 파티클이 뒤처지면서 생기기 때문이다. 그래서 모든 데모는
## 이 클래스로 기준점을 흔들어 준다.
##
## 매 프레임 [method step] 을 부르면 [member offset] 과 [member euler] 가 갱신된다.

enum Kind {
	IDLE, ## 정지. 중력 처짐(sag)만 확인할 때.
	BOUNCE, ## 제자리 점프 반복. 수직 자극.
	SIDE_STEP, ## 좌우 이동 반복. 수평 자극.
	TWIST, ## 몸통 좌우 회전. 회전 자극.
	WALK, ## 걷기 루프. 위 세 가지를 실제 보행 위상으로 합성한 것.
	SHOCK, ## 한 방향으로 급정거. 큰 관성을 한 번에 주고 싶을 때.
}

var kind: Kind = Kind.WALK
var speed := 1.0
var amount := 1.0

## 결과: 기준점에 더할 위치 오프셋.
var offset := Vector3.ZERO
## 결과: 기준점에 더할 회전(라디안 오일러).
var euler := Vector3.ZERO
## 현재 자극 위상(초 × speed). 데모가 다리 스윙 같은 부수 동작을 여기에 맞춘다.
var cycle := 0.0

var _time := 0.0
# 임펄스는 그 자체를 작은 스프링으로 모델링한다. 사각파를 그대로 넣으면
# 무한대 가속도가 되어 시뮬레이션이 터지기 때문이다.
var _impulse := 0.0
var _impulse_velocity := 0.0


## 스페이스 등으로 "툭" 한 번 치는 자극. 어떤 kind 에서든 항상 동작한다.
func trigger_impulse(strength: float = 1.0) -> void:
	_impulse_velocity += 3.2 * strength * amount


func reset() -> void:
	_time = 0.0
	_impulse = 0.0
	_impulse_velocity = 0.0
	offset = Vector3.ZERO
	euler = Vector3.ZERO


func step(delta: float) -> void:
	_time += delta * speed
	cycle = _time

	# 감쇠 스프링으로 임펄스를 부드럽게 0으로 되돌린다.
	var accel := -200.0 * _impulse - 16.0 * _impulse_velocity
	_impulse_velocity += accel * delta
	_impulse += _impulse_velocity * delta

	offset = Vector3(0.0, _impulse * 0.22, 0.0)
	euler = Vector3.ZERO

	match kind:
		Kind.BOUNCE:
			# absf(sin) 이라 착지 순간 방향이 꺾인다 — 실제 점프처럼 날카로운 자극이 된다.
			offset.y += absf(sin(_time * PI)) * 0.30 * amount
		Kind.SIDE_STEP:
			offset.x += sin(_time * PI) * 0.40 * amount
		Kind.TWIST:
			euler.y = sin(_time * PI) * 1.0 * amount
		Kind.WALK:
			# 보행 위상: 상하 바운스는 보폭의 2배 주기, 좌우 흔들림·골반 회전은 1배 주기.
			offset.y += absf(sin(_time * TAU)) * 0.075 * amount
			offset.x += sin(_time * PI) * 0.05 * amount
			euler.y = sin(_time * PI) * 0.16 * amount
			euler.z = sin(_time * PI + PI * 0.5) * 0.06 * amount
		Kind.SHOCK:
			# 톱니파: 천천히 밀렸다가 순간적으로 되돌아온다 = 급정거.
			var phase := fmod(_time * 0.5, 1.0)
			offset.z += (phase * phase * 0.7 - 0.35) * amount
		Kind.IDLE:
			pass
