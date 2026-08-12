# Jiggle — Godot 4.7 흔들림 물리 학습 프로젝트

3D에서 **Cloth · Hair · 가슴/엉덩이 흔들림**이 어떻게 만들어지는지 배우기 위한
인터랙티브 교보재. 데모 01~08은 외부 에셋 없이 형상까지 전부 코드로 만들고,
데모 09만 실제 캐릭터가 필요해서 직접 만든 Rigify 리그
([`assets/adachi_rigged4/`](assets/adachi_rigged4/))를 쓴다.

## 실행

Godot 4.7 이상이 필요하다.

```bash
git clone https://github.com/CoEf/Jiggle.git
```

```bash
godot --path Jiggle
```

`godot` 이 PATH에 없다면 실행 파일 경로를 그대로 쓰면 된다
(Windows 예: `Godot_v4.7-stable_win64.exe --path Jiggle`).

## 흔들림 코드

전부 [`jiggle/`](jiggle/) 안에 있다. 데모는 이 코드를 **쓰기만** 한다.

| 노드 | 쓰는 곳 |
| --- | --- |
| `JiggleBoneModifier3D` | 본 **하나** — 가슴 · 엉덩이 |
| `JiggleChainModifier3D` | 본 **사슬** — 머리카락 · 꼬리 · 끈 |
| `JiggleChainGroup3D` | 이름 규칙으로 여러 가닥을 한 노드에서 |
| `JiggleCollider3D` | 씬에서 눈으로 배치하는 캡슐 충돌체 |
| `JigglePoseReader3D` | 모디파이어 **결과**를 밖에서 읽는 장치 |

## 검증 (헤드리스)

모든 데모를 프리셋 × 자극 조합으로 돌려 보고 발산·NaN이 없는지 확인한다.

```bash
godot --headless --path . --script tools/smoke_test.gd
```

이건 "안 터졌는가"만 본다. 실제 캐릭터에서 **흔들림이 정말 나오는지**는 따로 잰다.

```bash
godot --headless --path . --script tools/character_test.gd
```

Windows에서는 출력을 보려면 콘솔 빌드(`..._console.exe`)로 실행해야 한다.

## 문서

| 문서 | 내용 |
| --- | --- |
| **[docs/HANDOFF.md](docs/HANDOFF.md)** | **이어서 작업한다면 여기부터.** 구조 · 함정 전체 목록 · 다음 할 일 |
| [docs/00_overview.md](docs/00_overview.md) | 전체 지도 · 조작법 · "내 상황엔 뭘 써야 하나" 결정 트리 |
| [docs/01_spring_basics.md](docs/01_spring_basics.md) | 스프링-댐퍼, 감쇠비 ζ, 적분 방식, 프레임레이트 의존성 |
| [docs/02_jiggle_bone.md](docs/02_jiggle_bone.md) | `SkeletonModifier3D`, 위치 스프링 → 본 회전, 비등방 강성, 스키닝 |
| [docs/03_bone_chain.md](docs/03_bone_chain.md) | Verlet 적분, 거리·각도 제약, 충돌 폭주, 튜브 스키닝 |
| [docs/04_cloth.md](docs/04_cloth.md) | 구조·전단·굽힘 제약, 법선 비례 바람, 매 프레임 메쉬 굽기 |
| [docs/05_builtin_compare.md](docs/05_builtin_compare.md) | 내장 SpringBone·SoftBody·래그돌과의 대응표와 함정 |
| [docs/08_shader_jiggle.md](docs/08_shader_jiggle.md) | 본 없이 흔들기(정점 셰이더)와 그 한계 |
| [docs/10_real_character.md](docs/10_real_character.md) | 실제 Rigify 캐릭터에 붙이기 — 본 축 찾기, 실측표, 측정 함정 |

## 진행 상황

- ✅ **Phase 0** 공통 인프라 (허브 UI · 디버그 드로잉 · 파라미터 자동 UI · 그래프 · 자극)
- ✅ **Phase 1** 데모 01 — 스프링-댐퍼 기초
- ✅ **Phase 2** 데모 02 — Jiggle Bone (가슴 · 엉덩이)
- ✅ **Phase 3** 데모 03 — 본 체인 Verlet (머리카락 · 꼬리)
- ✅ **Phase 4** 데모 04 — 천 Verlet (치마 · 커튼)
- ✅ **Phase 5** 데모 05~07 — 엔진 내장 기능(`SpringBoneSimulator3D` · `SoftBody3D` ·
  `PhysicalBoneSimulator3D`)과 나란히 비교
- ✅ **Phase 6** 데모 08 — 정점 셰이더 흔들림, 프리셋 저장/불러오기, 문서 정리
- ✅ **Phase 7** 솔버를 `jiggle/` 로 분리 — 본 이름 드롭다운 ·
  `JiggleCollider3D` · 애니메이션 리그 대응
- ✅ **Phase 8** 데모 09 — 실제 Rigify 캐릭터(본 183개)에 적용,
  머리카락·치마·리본 36개 모디파이어 · 실측 검사
- ✅ **Phase 9** 내장 `SpringBoneSimulator3D` 와 같은 캐릭터로 나란히 비교
  ([`assets/adachi_rigged4/`](assets/adachi_rigged4/) 의 두 씬)

계획한 8개 데모가 모두 끝났고, 솔버는 `jiggle/` 로 분리해
실제 캐릭터에 붙여 동작을 실측까지 확인했습니다.
슬라이더로 찾은 설정은 오른쪽 패널의 **내 설정 → 저장** 으로 `user://presets.json` 에 남길 수 있습니다.

## 핵심 파일

이 세 개만 읽으면 나머지는 전부 그것을 보여 주기 위한 장치다.

- [`jiggle/jiggle_spring.gd`](jiggle/jiggle_spring.gd) — 스프링-댐퍼 적분기 (가슴·엉덩이)
- [`jiggle/verlet_body.gd`](jiggle/verlet_body.gd) — Verlet 솔버 (사슬·천 공용)
- [`jiggle/jiggle_bone_modifier.gd`](jiggle/jiggle_bone_modifier.gd) — 커스텀 `SkeletonModifier3D`

## 글

이 프로젝트를 소재로 쓴 글은 [devlog](https://coef.github.io/blog/character/jiggle-tour-1-spring-damper/)에 있다.
데모를 화면 그대로 따라가는 투어 시리즈와, 수식을 유도하는 이론 시리즈,
구현하며 겪은 함정을 정리한 실전 시리즈로 나뉜다.

## 라이선스

[MIT](LICENSE).

`assets/adachi_rigged4/` 의 모델·텍스처도 직접 만든 것이라 같은 조건으로 쓸 수 있다.

