# Jiggle 전체 지도

## 이 프로젝트는 무엇인가

Godot 4.7에서 **Cloth / Hair / 가슴·엉덩이 흔들림**이 어떻게 만들어지는지 배우기 위한
인터랙티브 교보재다. 게임이 아니라 "만져 보면서 이해하는 문서"에 가깝다.

외부 3D 에셋을 하나도 쓰지 않는다. 캐릭터도, 메쉬도, 스켈레톤도 전부 코드로 만든다.
"이 오브젝트가 어디서 왔는지"가 인스펙터가 아니라 스크립트 한 곳에 다 보이게 하기 위해서다.

## 실행

```bash
"C:\Godot\Godot_v4.7-stable_win64.exe" --path "C:\Users\Public\Code\_Collection\Jiggle"
```

터지지 않는지만 자동으로 확인하려면:

```bash
"C:\Godot\Godot_v4.7-stable_win64_console.exe" --headless --path "C:\Users\Public\Code\_Collection\Jiggle" --script tools/smoke_test.gd
```

## 조작

| 입력 | 동작 |
| --- | --- |
| 우클릭 드래그 | 카메라 회전 |
| 휠 | 줌 |
| 가운데 버튼 드래그 | 카메라 초점 이동 |
| `Space` | 임펄스 (툭 치기) |
| `R` | 리셋 |
| `P` | 일시정지 |
| `.` | 한 프레임만 진행 |
| `S` | 슬로우모션 (0.15배) |

**슬로우모션과 한 프레임 진행을 적극적으로 쓸 것.** 실시간으로는 "출렁인다" 이상을 볼 수 없지만
0.15배속에서는 파티클이 목표를 지나쳤다가 되돌아오는 과정이 한 동작씩 보인다.

## 하나의 아이디어, 세 가지 적용

> **Jiggle = 목표를 지연·오버슈트하며 따라가는 2차 시스템**

가슴이든 머리카락이든 치마든, 수학은 같다. 달라지는 건 *무엇에* 적용하고
*결과를 무엇으로 읽느냐*뿐이다.

| 대상 | 수학 | 결과를 읽는 방법 |
| --- | --- | --- |
| 가슴 · 엉덩이 | 스프링-댐퍼 파티클 **1개** | 본의 **회전** |
| 머리카락 · 꼬리 | Verlet 파티클 **체인** + 거리 제약 | 본 체인의 **회전** |
| 천 · 치마 | Verlet 파티클 **격자** + 다중 제약 | 메쉬의 **정점** |

## 데모 목록

| # | 데모 | 다루는 것 | 상태 |
| --- | --- | --- | --- |
| 01 | [스프링-댐퍼 기초](01_spring_basics.md) | k, c, 감쇠비 ζ, 적분 방식, 프레임레이트 의존성 | ✅ |
| 02 | [Jiggle Bone](02_jiggle_bone.md) | 위치 스프링 → 본 회전, 비등방 강성, 클램프, 스키닝 | ✅ |
| 03 | [본 체인 Verlet](03_bone_chain.md) | 머리카락·꼬리, 거리 제약, 각도 제한, 충돌 폭주 | ✅ |
| 04 | [천 Verlet](04_cloth.md) | 구조·전단·굽힘 제약, 바람, 매 프레임 메쉬 굽기 | ✅ |
| 05 | [내장 `SpringBoneSimulator3D`](05_builtin_compare.md) | 03과 나란히 비교, 파라미터 대응표 | ✅ |
| 06 | [내장 `SoftBody3D`](05_builtin_compare.md) | 04와 나란히 비교, 압력·질량·외력 | ✅ |
| 07 | [`PhysicalBoneSimulator3D`](05_builtin_compare.md) | 래그돌 기반 흔들림, 조립·튜닝 비용 | ✅ |
| 08 | [정점 셰이더 흔들림](08_shader_jiggle.md) | 본 없이 흔들기와 그 한계 | ✅ |
| 09 | [실제 캐릭터](10_real_character.md) | Rigify 리그(본 183개)에 모디파이어 적용, 본 축 찾기, 실측 검증 | ✅ |

## 코드 지도

```
main.gd / main.tscn              데모 허브 (목록 · 시간 제어 · 파라미터 · 그래프)
jiggle/                          ★ 흔들림 코드 본체 — 데모는 전부 이걸 쓴다
  jiggle_spring.gd               ★ 스프링-댐퍼 적분기. 덩어리 하나를 흔든다
  verlet_body.gd                 ★ Verlet 솔버. 적분·충돌·안전장치 (사슬·천 공용)
  verlet_chain.gd                  └ 사슬 제약 (거리 + 각도)
  verlet_cloth.gd                  └ 격자 제약 (구조 + 전단 + 굽힘) + 메쉬 굽기
  jiggle_bone_modifier.gd        ★ JiggleBoneModifier3D  (본 하나 — 가슴 · 엉덩이)
  chain_strand.gd                ★ JiggleChainStrand     (사슬 한 가닥 — 노드 아님)
  bone_chain_modifier.gd         ★ JiggleChainModifier3D (가닥 하나를 노드 하나로)
  chain_group_modifier.gd        ★ JiggleChainGroup3D    (여러 가닥을 이름 규칙으로)
  chain_settings.gd              ★ JiggleChainSettings   (사슬 재질값을 .tres 하나로)
  jiggle_collider.gd             JiggleCollider3D  씬에서 눈으로 배치하는 캡슐 충돌체
  pose_reader_modifier.gd        JigglePoseReader3D 모디파이어 결과를 밖에서 읽기(중요)
  bone_names.gd                  인스펙터 본 이름 드롭다운 도우미
  icons/*.svg                    인스펙터·씬 트리에 뜨는 클래스 아이콘
common/                          데모 전용 장치 — 흔들림 자체와는 무관하다
  jiggle_demo.gd                 데모 공통 뼈대 (고정 timestep 서브스텝 포함)
  jiggle_debug_draw.gd           ImmediateMesh 디버그 라인
  proc_skin.gd                   프로시저럴 스킨드 메쉬 생성
  param_panel.gd                 @export → 슬라이더 자동 생성
  jiggle_plot.gd                 변위-시간 그래프
  stimulus.gd                    자극(점프 · 걷기 · 급정거 …)
  orbit_camera.gd                궤도 카메라
demos/
  01_spring_basics/spring_basics_demo.gd
  02_jiggle_bone/
	jiggle_bone_demo.gd          씬 구성 + 파라미터
	jiggle_body.gd               코드로 만드는 스켈레톤 + 스킨드 메쉬
  03_bone_chain/
	bone_chain_demo.gd           씬 구성 + 파라미터
	hair_rig.gd                  머리 + 머리카락 다발 리그, 충돌체
  04_cloth/
	cloth_demo.gd                씬 구성 + 파라미터 + 양면 셰이더
	cloth_mannequin.gd           하반신 마네킹, 걷는 다리 충돌체
  05_builtin_springbone/         자작 사슬 vs 내장 SpringBoneSimulator3D
  06_builtin_softbody/           자작 천 vs 내장 SoftBody3D
  07_physical_bones/             자작 사슬 vs PhysicalBone3D 래그돌
  08_shader_jiggle/              본 기반 vs 정점 셰이더 (본 0개)
  09_real_character/             실제 Rigify 캐릭터에 적용 (유일한 외부 에셋 사용처)
	character_rig.gd             모델 로드 · 이름 규칙으로 사슬 탐색 · 본 추종 충돌체
	real_character_demo.gd       그룹별 파라미터 · 자극 · 그래프
assets/adachi_rigged4/           Rigify 계열 캐릭터, 본 183개
  adachi_rigged4_jiggle.tscn       모디파이어 36개 (씬 노드로 들어 있다)
  adachi_rigged4_springbone.tscn   내장 SpringBoneSimulator3D
  adachi_rigged4_compare.tscn      둘을 좌우로 나란히 — 자극 하나로 같이 흔든다
tools/
  smoke_test.gd                  헤드리스 회귀 검사 (데모 258 조합)
  character_test.gd              헤드리스 실측 검사 (실제 리그, 조건별 비교표)
  material_sweep.gd              재질감 파라미터 실측 (어느 손잡이가 무엇을 바꾸는가)
  inspect_rig.gd                 외부 리그의 본 축·이름·사슬 후보 찍어보기
  make_rig4_scenes.gd            실제 캐릭터 비교 씬 3개 생성
  capture_shots.gd               블로그용 스크린샷 · 시연 영상 캡처
```

굵은 별표 파일만 이해하면 나머지는 전부 그것을 보여 주기 위한 장치다.
`jiggle/` 과 `common/` 의 경계가 곧 **"흔들림 자체"와 "보여 주기 위한 장치"** 의 경계다.

## 내 상황엔 뭘 써야 하나

```
거기에 무언가를 붙일 일이 있는가? (장신구 · 머리카락 · 옷 · 충돌)
├─ 없다 + 개수가 아주 많다 (군중 · 풀 · 배경)
│   └─ 정점 셰이더                    → 데모 08. 본 0개, 사실상 공짜.
└─ 있다 → 본이 필요하다
	│
	흔들리는 게 본 몇 개인가?
	├─ 1~2개 (가슴 · 엉덩이 · 배)
	│   └─ 스프링-댐퍼 1개 + 본 회전    → 데모 02. 가장 싸고 가장 튜닝하기 쉽다.
	├─ 사슬 형태 (머리카락 · 꼬리 · 끈)
	│   ├─ 직접 제어하고 싶다           → Verlet 체인 (데모 03)
	│   └─ 빨리 끝내고 싶다             → 내장 SpringBoneSimulator3D (데모 05)
	├─ 면 형태 (치마 · 망토 · 깃발)
	│   ├─ 캐릭터에 붙는 옷             → Verlet 격자 (데모 04)
	│   └─ 물리 월드와 진짜로 엮임       → 내장 SoftBody3D (데모 06)
	└─ 죽은 몸 · 물리 상호작용          → PhysicalBoneSimulator3D (데모 07)
```

가슴·엉덩이에 `SoftBody3D`나 `PhysicalBone3D`를 쓰는 것은 거의 항상 과하다.
비용은 수십 배인데 결과는 스프링 하나보다 통제하기 어렵다.

## 파라미터를 직접 저장하기

슬라이더를 만져 마음에 드는 느낌을 찾았다면 오른쪽 패널 맨 아래
**내 설정 → 저장** 을 누르면 된다. 데모별로 따로 보관되고 **불러오기** 로 되돌릴 수 있다.

저장 위치는 `user://presets.json`
(Windows 기준 `%APPDATA%\Godot\app_userdata\Jiggle\presets.json`).
사람이 읽을 수 있는 JSON이라 직접 열어 고쳐도 된다.

## 어떤 순서로 읽으면 좋은가

1. `jiggle/jiggle_spring.gd` 를 열고 주석을 읽는다 — 30줄이 전부다.
2. 데모 01을 실행하고 슬라이더를 만진다. **적분 방식을 명시적 오일러로 바꾸고 Hz를 15로 내려 본다.**
3. `jiggle/jiggle_bone_modifier.gd` 의 `_process_modification_with_delta()` 를 읽는다.
   4단계 주석이 곧 알고리즘 전부다.
4. 데모 02에서 **웨이트 보기**를 켜고, **최대 각도를 0**으로 내려 본다.
5. `jiggle/verlet_body.gd` 를 읽는다. 스프링과 무엇이 다른지가 맨 위 주석에 있다.
6. 데모 03에서 **제약 반복 횟수**를 1과 12 사이로 왕복시키고, **충돌 응답 방식**을 ①로 바꿔 본다.
7. `jiggle/verlet_cloth.gd` 를 읽는다. 같은 솔버에 제약만 격자로 늘린 것임을 확인한다.
8. 데모 04에서 **전단**과 **굽힘**을 하나씩 꺼 본다. 각각이 무슨 일을 하고 있었는지 보인다.
9. 데모 05~07에서 내장 기능과 나란히 비교한다. [단위 함정](05_builtin_compare.md)을 먼저 읽어 둘 것.
10. 데모 08에서 **마커 두 개**를 본다. 셰이더가 무엇을 못 하는지 한눈에 보인다.
