# 02 · Jiggle Bone (가슴 · 엉덩이)

> 코드: [`jiggle/jiggle_bone_modifier.gd`](../jiggle/jiggle_bone_modifier.gd),
> [`demos/02_jiggle_bone/jiggle_body.gd`](../demos/02_jiggle_bone/jiggle_body.gd)

## 한 줄 요약

**데모 01의 스프링 하나를 본의 회전으로 읽으면 그게 가슴·엉덩이 Jiggle이다.**
새로운 물리는 하나도 없다. 결과를 위치가 아니라 *방향*으로 해석할 뿐이다.

## Godot 4.7에서의 올바른 진입점: `SkeletonModifier3D`

Godot 4.3부터 스켈레톤을 후처리하는 정식 방법은 [`SkeletonModifier3D`](https://docs.godotengine.org/en/stable/classes/class_skeletonmodifier3d.html)다.
`_process()` 에서 `set_bone_pose_rotation()` 을 직접 부르면 애니메이션과 실행 순서가 꼬이지만,
모디파이어는 **애니메이션이 포즈를 다 계산한 뒤**에 호출되는 것이 보장된다.

```gdscript
class_name JiggleBoneModifier3D
extends SkeletonModifier3D

func _process_modification_with_delta(delta: float) -> void:
	...
```

지켜야 할 조건이 두 가지 있다.

- **반드시 `Skeleton3D`의 직속 자식이어야 한다.** 손자로 넣으면 조용히 아무 일도 안 한다.
- 기본 호출 시점은 `MODIFIER_CALLBACK_MODE_PROCESS_IDLE`, 즉 **렌더 프레임마다**다.
  그래서 `delta`가 프레임레이트에 따라 출렁이고, 내부에서 고정 서브스텝으로 쪼개야 한다.

`influence`(0~1)와 `active`를 엔진이 알아서 블렌딩해 주므로 켜고 끄기가 공짜다.

## 알고리즘 4단계

### 1. "흔들림이 없다면 있어야 할" 끝점을 구한다

```gdscript
var parent_global := skeleton.global_transform * skeleton.get_bone_global_pose(_parent_bone)
bone_origin      = parent_global * _rest.origin
target_position  = bone_origin + (parent_global.basis * rest_direction).normalized() * tip_length
```

`tip_length`는 본 원점에서 흔들리는 덩어리 중심까지의 거리 = **스프링의 팔 길이**다.
`rest_direction`은 본이 향하는 로컬 축(`tip_axis`)을 rest 자세로 돌린 것이다.

### 2. 파티클이 그 목표를 쫓게 한다 — 여기서 관성이 공짜로 생긴다

```gdscript
_spring.step(SUBSTEP, target_position)
```

**파티클은 월드 공간에 있고, 목표는 스켈레톤을 따라 움직인다.**
몸이 움직이면 목표가 먼저 가고 파티클이 뒤따라간다. 그 지연이 곧 관성이다.

가속도를 측정해서 힘으로 바꾸는 코드는 **한 줄도 없다.** 이게 이 구현의 핵심이자,
많은 Jiggle 구현이 불필요하게 복잡해지는 지점이기도 하다.

관성의 양은 한 줄로 조절한다.

```gdscript
_spring.position += (target_position - _previous_target) * motion_inherit
```

`motion_inherit = 0`이면 스켈레톤 이동을 전혀 안 물려받아 최대로 흔들리고,
`1`이면 그대로 따라가 흔들림이 완전히 사라진다.
(DynamicBone의 `Inert`, VRM SpringBone의 관성 파라미터와 같은 개념이다.)

### 3. 길이를 유지한다

본은 늘어나지 않는다. 파티클을 본 원점 기준 구면에 투영한다.

```gdscript
_spring.position = bone_origin + normal * tip_length
_spring.velocity -= normal * _spring.velocity.dot(normal)   # 반경 방향 속도 제거
```

속도의 반경 성분을 지우지 않으면 길이가 계속 늘었다 줄었다 하려고 해서 떨린다.
`길이 유지`를 끄면 덩어리가 고무줄처럼 늘어나는 걸 볼 수 있다 — 재미있긴 하지만
실제 리그에서는 스키닝이 깨진다.

### 4. 방향을 본 회전으로 바꾼다

```gdscript
var current := (parent_basis.inverse() * offset).normalized()   # 부모 본 공간으로
var swing := Quaternion(rest_direction, current)                # 최단 회전
swing = _limit_swing(swing, deg_to_rad(max_angle_degrees))
skeleton.set_bone_pose_rotation(_bone, swing * _rest.basis.get_rotation_quaternion())
```

본 포즈는 **항상 부모 기준**이므로, 월드 방향을 부모 본 공간으로 되돌린 뒤 회전을 만든다.
`Quaternion(from, to)` 생성자가 두 벡터 사이의 최단 회전을 준다.

## 반드시 알아야 할 네 가지

### ① 비등방 강성 — 완벽한 구슬과 연부 조직의 차이

축마다 강성을 다르게 주면 "위아래보다 좌우로 잘 흔들리는" 거동이 나온다.

```gdscript
var scale := Vector3(horizontal_ratio, vertical_ratio, horizontal_ratio)
_spring.stiffness = Vector3(k, k, k) * scale
```

이때 **감쇠도 반드시 같이 바꿔야 한다.**

```gdscript
_spring.damping = Vector3(
	2.0 * damping_ratio * sqrt(_spring.stiffness.x),
	2.0 * damping_ratio * sqrt(_spring.stiffness.y),
	2.0 * damping_ratio * sqrt(_spring.stiffness.z),
)
```

ζ = c / (2√k) 이므로, k만 바꾸고 c를 그대로 두면 축마다 감쇠비가 달라져
**한 축만 유난히 오래 흔들린다.** 아주 흔한 버그다.

강성 축은 **부모 본의 회전을 따라가야** 한다. 몸이 돌면 "위아래"도 같이 돌기 때문이다.

```gdscript
_spring.frame = parent_basis.orthonormalized()
```

### ② 클램프는 선택이 아니다

각도 제한이 없으면 큰 자극에서 본이 180° 뒤집히고, 스킨드 메쉬가 안팎으로 뒤집혀 터진다.

```gdscript
static func _limit_swing(rotation: Quaternion, limit: float) -> Quaternion:
	var shortest := rotation if rotation.w >= 0.0 else -rotation   # q와 −q는 같은 회전
	var angle := 2.0 * acos(clampf(shortest.w, -1.0, 1.0))
	if angle <= limit:
		return shortest
	return Quaternion.IDENTITY.slerp(shortest, limit / angle)
```

회전만 자르면 파티클은 여전히 멀리 나가 있어서 한참 동안 최대 각도에 붙어 있는다.
그래서 **파티클 자체도** 같은 각도에 대응하는 현(弦) 길이 안으로 가둔다.

```gdscript
limit_radius = 2.0 * tip_length * sin(deg_to_rad(max_angle_degrees) * 0.5)
_spring.max_distance = limit_radius
```

> 데모에서 **최대 각도를 0(제한 없음)** 으로 두고 프리셋 `터뜨리기`를 눌러 보라.
> 왜 이게 필수인지 1초 만에 알 수 있다.

### ③ 중력 처짐이 자연스러움의 절반이다

`중력`을 0으로 하면 정지 상태에서 rest에 딱 붙어 뻣뻣해진다. 살아 있는 몸처럼 보이지 않는다.
중력은 평형점을 `g/k`만큼 아래로 옮기므로([01번 문서](01_spring_basics.md) 참고),
가만히 있어도 rest보다 살짝 처진 자세가 된다.

실제 중력값 9.8을 그대로 쓰면 과하게 늘어진다. **연출값으로 다루는 게 맞다** (2~5 정도).

### ④ 스키닝 가중치가 절반의 일을 한다

본을 아무리 잘 흔들어도 가중치가 잘못되면 결과는 엉망이다.
흔들리는 부위의 **뿌리에 부드러운 전이 구간**이 없으면 회전할 때 표면이 칼로 자른 듯 꺾인다.

```gdscript
ProcSkin.blend_along_axis(chest, breast_l, breast_origin, Vector3.BACK, -0.03, 0.05)
```

축 방향으로 `smoothstep`을 태워 Chest → Breast로 가중치를 넘긴다.
덩어리 뒤쪽은 몸통에, 앞쪽은 Jiggle 본에 100% 붙고, 그 사이 8cm가 전이 구간이다.

이 프로젝트는 가중치를 **정점 색으로 구워 두었다.** UI에서 `웨이트 보기`를 켜면
빨간 정도가 곧 Jiggle 본 가중치다. 어디가 얼마나 흔들릴지 바로 눈에 보인다.

## 스쿼시 & 스트레치 — 물리는 아니지만 효과는 크다

많이 휘었을수록 축 방향으로 늘리고 옆으로 줄인다(부피 보존).

```gdscript
var stretch := 1.0 + squash * clampf(swing_angle / limit, 0.0, 1.0)
var lateral := 1.0 / sqrt(stretch)
bone_scale[_tip_axis_index()] = stretch
skeleton.set_bone_pose_scale(_bone, bone_scale)
```

물리적 유도가 아니라 애니메이션 연출 기법이다. 0으로 두고 비교해 보면
있고 없고의 차이가 생각보다 크다는 걸 알 수 있다.

## 리그에 붙일 때의 함정

이 데모의 스켈레톤은 **모든 본의 rest basis가 단위행렬**이라 본 로컬축 = 월드축이다.
이해하기 쉬우라고 그렇게 만들었지만, **실제 리그는 절대 그렇지 않다.**

| 함정 | 증상 | 대처 |
| --- | --- | --- |
| 본이 향한 축이 다름 | 엉뚱한 방향으로 흔들림 | `tip_axis`를 리그에 맞게 설정 (`+Y`인 리그가 많다) |
| 좌우 미러링 부호 | 한쪽만 반대로 흔들림 | 미러 본은 축 부호를 뒤집어 확인 |
| 애니메이션이 이 본을 직접 회전 | 회전이 누적되어 폭주 | rest 대신 **이번 프레임의 애니메이션 포즈**에 곱할 것 |
| 스케일이 들어간 본 | 길이가 이상해짐 | `parent_basis.orthonormalized()` 로 스케일 제거 (이 코드는 이미 함) |

마지막 항목이 특히 중요하다. 이 데모는 애니메이션이 없어서 `_rest`를 기준으로 삼지만,
`AnimationPlayer`가 가슴 본을 돌리는 리그라면 다음처럼 바꿔야 한다.

```gdscript
var animated := skeleton.get_bone_pose_rotation(_bone)
skeleton.set_bone_pose_rotation(_bone, swing * animated)
```

## 해볼 것

1. **웨이트 보기**를 켠다 → 빨간 부분만 흔들린다. 전이 구간이 어떻게 생겼는지 본다.
2. **최대 각도 = 0**, 프리셋 `터뜨리기` → 본이 뒤집히며 메쉬가 터진다.
3. **좌우 강성 배율만 0.3** → 옆으로만 출렁인다. 비등방 스프링의 효과.
4. **중력 = 0** → 뻣뻣해진다. 그다음 6으로 올리면 늘어진다.
5. **이동 상속 = 1** → 흔들림이 완전히 사라진다.
6. `S`로 슬로우모션을 켜고 `걷기` 자극을 준다 → 상하 바운스(2배 주기)와
   좌우 흔들림(1배 주기)이 가슴/엉덩이에 다르게 실리는 게 보인다.
