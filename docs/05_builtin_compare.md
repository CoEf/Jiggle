# 05 · 06 · 07 — 엔진 내장 기능과의 비교

> 코드: [`demos/05_builtin_springbone/`](../demos/05_builtin_springbone/spring_bone_compare_demo.gd),
> [`demos/06_builtin_softbody/`](../demos/06_builtin_softbody/soft_body_compare_demo.gd),
> [`demos/07_physical_bones/`](../demos/07_physical_bones/physical_bone_compare_demo.gd)

세 데모 모두 **같은 리그를 두 개 놓고 같은 자극을 준다.** 왼쪽이 앞 단계에서 만든 자작 구현,
오른쪽이 Godot 내장 기능이다. 차이가 곧 구현의 차이다.

## 먼저 알아야 할 함정 — 모디파이어 결과는 밖에서 안 읽힌다

이 단계에서 가장 오래 붙잡힌 문제다.

```gdscript
# 이렇게 읽으면 항상 rest 값이 나온다
skeleton.get_bone_global_pose(bone)
```

[SkeletonModifier3D]가 [method Skeleton3D.set_bone_pose_rotation] 로 쓴 결과는
**스키닝에는 반영되지만, 바깥에서 읽으면 모디파이어가 돌기 전 값이 나온다.**
스켈레톤이 모디파이어 처리를 끝낸 뒤 로컬 포즈를 원래대로 되돌리기 때문이다.

이것 때문에 "내장 `SpringBoneSimulator3D`가 동작하지 않는다"고 한참을 오해했다.
실제로는 잘 돌고 있었다. 최소 재현 케이스로 확인한 결과:

| 읽는 방법 | 결과 |
| --- | --- |
| `skeleton.get_bone_global_pose(tip)` | `(0.4, 1.5, 0)` — rest 그대로 |
| 뒤에 붙인 [SkeletonModifier3D] 안에서 같은 호출 | `(0.081, 1.180, 0)` — **실제 결과** |
| `BoneAttachment3D.global_position` | `(0.081, 1.180, 0)` — 동일 |

그래서 이 프로젝트는 [`JigglePoseReader3D`](../jiggle/pose_reader_modifier.gd) 를 만들어
시뮬레이터 **뒤에** 붙여 결과를 받아 온다. 자식 순서가 곧 실행 순서다.

> 자작 모디파이어가 멀쩡히 도는데도 밖에서 읽으면 rest가 나온다는 것도 같이 확인했다
> (`last_usec = 28`, 파티클은 실제로 낙하 중, 그런데 `get_bone_global_pose`는 rest).
> **모디파이어의 결과는 모디파이어 안에서 읽어라.**

---

## 05 · 내장 `SpringBoneSimulator3D`

Godot 4.4부터 들어온 VRM SpringBone 계열 구현이다. 데모 03의 머리카락 리그를 그대로 두 개 쓴다.

### 파라미터 대응표

| 자작 | 내장 | 비고 |
| --- | --- | --- |
| 복원 진동수 (Hz) | `stiffness` (0~1) | **단위가 없다.** 물리량으로 환산 불가 |
| 공기저항 (스텝당) | `drag` (0~1) | 역시 단위 없음 |
| `gravity` (m/s²) | `gravity` + `gravity_direction` | **단위가 다르다 — 아래 참고** |
| `particle_radius` | `radius` | 충돌 두께 |
| `external_force` | `external_force` | 이름까지 같다 |
| 제약 반복 횟수 | — | 내장은 길이가 항상 고정 |
| 각도 제한 | — | 내장에는 개념이 없다 |
| — | 감쇠 커브 | 뿌리→끝으로 값을 변화시킬 수 있다 |
| — | 회전축 제한 | 특정 축으로만 흔들리게 |
| `JiggleVerletBody.Collider` (데이터) | `SpringBoneCollision3D` (씬 노드) | 이쪽은 `JiggleCollider3D` 로 감싸 똑같이 배치 가능 |

같은 숫자를 넣어도 두 결과가 정확히 겹치지는 않는다. **내장 파라미터에 단위가 없기 때문이다.**
이건 결함이 아니라 설계 선택이다 — 아티스트가 슬라이더를 만지며 맞추라는 뜻이다.

### 코드에서 설정할 때

```gdscript
simulator.set_setting_count(strand_count)
simulator.set_root_bone_name(index, "H0_0")
simulator.set_end_bone_name(index, "H0_5")
simulator.set_extend_end_bone(index, true)          # 마지막 본에 자식이 없을 때 필수
simulator.set_end_bone_direction(index, SkeletonModifier3D.BONE_DIRECTION_FROM_PARENT)
simulator.set_end_bone_length(index, 0.04)
simulator.set_stiffness(index, 0.5)
```

> **혼란 주의:** `get_joint_stiffness(i, j)` 는 `individual_config` 가 꺼져 있으면
> 설정값이 아니라 **낡은 기본값(1.0)** 을 돌려준다. 실제 시뮬레이션은 설정값을 제대로 쓴다.
> 두 방식(설정값만 / `individual_config=true` + 조인트별)의 결과가 완전히 같은 것을 확인했다.

### ⚠ `gravity` 에 9.8을 넣으면 흔들림이 통째로 사라진다

이 프로젝트에서 실제로 낸 버그다. "이름이 gravity니까 m/s²겠지" 하고 9.0을 넣었더니
**머리카락이 아래로 못 박혀 부드러운 jiggle이 전혀 안 나왔다.** 바람(`external_force`)에는
반응하는데 몸이 움직여도 안 흔들리는, 아주 헷갈리는 증상이었다.

내장 `gravity` 는 VRM SpringBone 계열의 **무단위 "중력 세기"** 라서 스프링 항과 같은 축척으로
더해진다. 9.0을 넣으면 중력 항이 다른 모든 항을 20배 가까이 압도해 버린다.

같은 리그·같은 자극(좌우 이동)에서 끝 마디의 진폭을 실측한 값:

| 내장 `gravity` | 진폭 | 비고 |
| --- | --- | --- |
| 9.0 | **0.0065 m** | 사실상 정지 |
| 1.0 | 0.0787 m | 자작(9.0 m/s²)의 0.077 m 와 일치 |
| 0.3 | 0.180 m | |
| 0.0 | 0.277 m | 중력 없이 관성만 |

그래서 이 데모는 `gravity * (1.0 / 9.0)` 으로 환산해 넣는다.

**부수 효과:** 중력을 정상화하기 전에는 `stiffness` 를 0.02 ↔ 0.90 으로 바꿔도 결과가
전혀 안 변했다(지연 0.2917 vs 0.2915). 중력 항에 완전히 묻혀 있었기 때문이다.
정상화한 뒤에는 제대로 듣는다 — 진폭 0.05 → 0.0986 m, 0.90 → 0.0672 m.

> **교훈:** 내장 파라미터는 이름이 같아도 단위가 같지 않다.
> 값을 넣기 전에 **극단값 두 개를 넣어 보고 결과가 실제로 달라지는지** 확인하라.
> 아무 변화가 없으면 그 파라미터는 다른 항에 묻혀 있는 것이다.

---

## 06 · 내장 `SoftBody3D`

Jolt에서도 정상 동작한다(직접 확인). 같은 격자 메쉬를 두 장 만들어 한쪽은 [JiggleVerletCloth],
한쪽은 [SoftBody3D] 에 넘기고, **공을 하나씩** 통과시킨다.

### 파라미터 대응표

| 자작 | 내장 |
| --- | --- |
| `iterations` | `simulation_precision` |
| 구조 제약 강도 | `linear_stiffness` |
| 공기저항 | `damping_coefficient` / `drag_coefficient` |
| 전단·굽힘 제약 개별 토글 | — (내부 고정) |
| 임의 외력(바람) | — **API가 없다** |
| 정점을 직접 읽고 쓰기 | `get_point_transform` 만 (읽기) |
| — | `total_mass` (자작 Verlet에는 질량 개념이 없다) |
| — | `pressure_coefficient` (풍선처럼 부풀리기) |
| — | 물리 월드의 강체와 실제 상호작용 |

### 실무에서 갈리는 지점

- **고정점**: 자작은 매 프레임 원하는 좌표를 대입하면 끝. 내장은 임의의 노드에 붙이려면
  [PhysicsBody3D] 가 필요하다(`set_point_pinned(i, true, path)`).
- **중력**: 내장은 프로젝트 물리 중력을 쓴다. 천만 따로 중력을 주는 것이 안 된다.
- **충돌체**: 자작은 그냥 데이터 구조, 내장은 물리 노드([StaticBody3D] 등)여야 한다.
- **예산**: 자작은 `_process`, 내장은 물리 서버. 두 숫자는 **서로 다른 예산**에서 나온다.

캐릭터에 붙는 옷은 대부분 자작 쪽이 편하다. 반대로 바닥에 떨어져 구르는 천, 다른 물체에
걸리는 깃발처럼 **물리 월드와 진짜로 엮여야 하는 것**은 내장이 압도적으로 유리하다.

---

## 07 · `PhysicalBoneSimulator3D` (래그돌)

본 하나가 곧 [RigidBody3D] 인 진짜 강체 물리다. 같은 꼬리를 두 개 매달아 비교한다.

### 조립 비용의 차이

```gdscript
# 자작: 이게 전부
var modifier := JiggleChainModifier3D.new()
modifier.root_bone_name = "T0"
modifier.end_bone_name = "T4"
skeleton.add_child(modifier)
```

```gdscript
# 래그돌: 본마다 이만큼
var physical := PhysicalBone3D.new()
physical.name = bone_name
simulator.add_child(physical)
physical.set("bone_name", bone_name)          # ← 이거 빠뜨리면 조용히 폭발
physical.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
physical.body_offset = Transform3D(Basis.IDENTITY, Vector3(0, -length * 0.5, 0))
physical.set("joint_constraints/swing_span", 30.0)
physical.set("joint_constraints/bias", 0.9)
var shape := CollisionShape3D.new()           # 충돌 셰이프도 본마다 필요
...
```

### 여기서 실제로 걸린 함정 두 가지

**① `bone_name` 은 노드 이름으로 결정되지 않는다.**
`PhysicalBone3D` 의 `bone_name` 은 클래스에 선언된 속성이 아니라 스켈레톤의 본 목록으로
만들어지는 **동적 속성**이다. `add_child` 뒤에 `set("bone_name", ...)` 로 넣어야 한다.
빠뜨리면 `get_bone_id()` 가 −1이 되고, 강체들이 아무 본에도 안 붙은 채 관절만 걸려
**y = 44m 까지 날아갔다.**

**② 사슬의 뿌리 본에도 물리 본이 필요하다.**
없으면 부모를 거슬러 올라가다 −1에서 끊겨 엔진이 에러를 쏟는다.
대신 `physical_bones_start_simulation(["T0", ...])` 로 시뮬레이션 대상에서 빼면
애니메이션을 그대로 따라가는 고정점이 된다.

**③ `body_offset` 을 "마디 가운데"로 두면 사슬이 쪼그라든다.**
"강체 중심은 마디의 중앙에 와야지" 하고 `(0, −L/2, 0)` 을 넣었더니
**조인트까지 같이 내려가 마디마다 반 칸씩 겹쳐 붙었다.** 정지 상태 사슬 길이 실측:

| `body_offset` | 사슬 길이 (기대 0.550 m) | |
| --- | --- | --- |
| `(0, −L/2, 0)` | 0.442 m | **80% — 쪼그라듦** |
| `Transform3D.IDENTITY` | 0.578 m | 105% — 정상 |
| `(0, +L/2, 0)` | 0.820 m | 149% — 늘어남 |

`IDENTITY` 로 두는 것이 맞다.

**④ Jolt은 콘 조인트의 `bias` / `relaxation` 을 무시한다.**
설정하면 엔진이 경고를 낸다. 물리 엔진을 바꾸면 조인트 파라미터의 일부가 조용히
사라진다는 뜻이다. 자작 구현에는 이런 엔진 의존성이 아예 없다.

### 튜닝 감각의 차이

자작은 "진동수 몇 Hz, 감쇠비 얼마"로 바로 말할 수 있다.
래그돌은 **질량 · 각속도 감쇠 · 콘 각도 · 조인트 bias** 가 서로 얽혀 있어서
하나만 바꿔도 나머지가 전부 달라진다. 게다가 "리셋"이 없어서
되돌리려면 시뮬레이션을 껐다 켜야 한다.

### 결론

> 래그돌이 이기는 경우는 **물리 월드와 진짜로 상호작용해야 할 때**뿐이다.
> (죽은 몸이 계단을 굴러 내려가는 것, 무기가 몸에 걸리는 것)
>
> 가슴 · 머리카락 같은 **보이기용 흔들림**에 래그돌을 쓰는 것은 거의 항상 과하다.
> 비용은 물리 프레임 예산에서 나가고, 통제는 훨씬 어렵다.

---

## 셋을 겪고 나서 — 무엇을 쓸 것인가

| 상황 | 추천 |
| --- | --- |
| 가슴 · 엉덩이 (본 1~2개) | **자작 스프링** (데모 02). 가장 싸고 가장 통제하기 쉽다 |
| 머리카락 · 꼬리, 빨리 끝내야 함 | **내장 `SpringBoneSimulator3D`**. 코드 없이 에디터에서 끝난다 |
| 머리카락 · 꼬리, 세밀한 통제 필요 | **자작 Verlet 사슬** (데모 03). 각도 제한·반복 횟수를 직접 만진다 |
| 캐릭터에 붙는 옷 | **자작 Verlet 천** (데모 04). 고정점을 본에 붙이기가 쉽다 |
| 바닥에 떨어지고 걸리는 천 | **내장 `SoftBody3D`**. 물리 월드와 엮이는 것은 이쪽이 압도적 |
| 죽은 몸, 물리 상호작용 | **`PhysicalBoneSimulator3D`** |

내장 기능을 쓸 수 있으면 쓰는 게 맞다. 다만 **자작 구현을 한 번 해 보고 나면
내장 파라미터가 무슨 뜻인지 알게 되고, 안 될 때 무엇을 의심해야 하는지도 알게 된다.**
그게 이 프로젝트 전체의 목적이다.
