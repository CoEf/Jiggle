extends SceneTree

## adachi_rigged4 비교 씬 세 개를 만든다.
##
## [codeblock]
## godot --headless --path <프로젝트> --script tools/make_rig4_scenes.gd
## [/codeblock]
##
## [b]만들어지는 것[/b] — 셋 다 시뮬레이터가 [b]씬 안에 실제 노드로[/b] 들어간다.
## 씬을 열면 트리에 그대로 보이고 인스펙터에서 값을 고칠 수 있다.
## [codeblock]
## adachi_rigged4_jiggle.tscn   JiggleChainModifier3D 36개 + JiggleCollider3D 4개
## adachi_rigged4_springbone.tscn   SpringBoneSimulator3D 1개(슬롯 36개) + SpringBoneCollision*
## adachi_rigged4_compare.tscn      위 둘을 좌우로 놓고 자극 하나로 같이 흔든다
## [/codeblock]
##
## [b]⚠ 다시 돌리면 손으로 맞춘 것이 전부 날아간다.[/b] 세 파일을 [b]통째로 덮어쓴다[/b] —
## [code]adachi_rigged4_jiggle.tscn[/code] 은 그 뒤로 에디터에서 손으로 튜닝했다
## (재질 리소스 6개 · 머리 충돌체 치수 · 가슴 모디파이어 2개 · 앞리본 왼쪽 뿌리 이름).
## 이 스크립트는 그중 무엇도 안 쓴다. 리그가 바뀌어 처음부터 다시 만들 때만 돌릴 것.
## 씬의 값은 데모 09([code]RealCharacterDemo[/code] · [code]CharacterRig[/code])에도 옮겨 두었다.
##
## [b]왜 생성 스크립트인가[/b] — 흔들 사슬이 36가닥이다. 손으로 적으면 300줄이 넘고,
## 리그가 바뀔 때마다 전부 다시 적어야 한다. [code]CharacterRig[/code] 가 찾아 준 사슬 목록을 쓴다.
##
## [b]왜 PackedScene.pack() 이 아니라 텍스트를 직접 쓰는가[/b]
##
## 모디파이어는 [Skeleton3D] 의 직속 자식이어야 하는데, 그 스켈레톤은 글b [b]인스턴스 안[/b]에 있다.
## 에디터 밖에서 [method PackedScene.instantiate] 를 부르면 "인스턴스 기준 상태"가 만들어지지
## 않아서(그건 [code]GEN_EDIT_STATE_INSTANCE[/code] 인데 에디터 전용이다),
## [method PackedScene.pack] 이 인스턴스 내부를 [b]전부 바뀐 것으로 보고 통째로 써 버린다.
## 실제로 메쉬·본 데이터까지 박혀서 .tscn 이 [b]1.4MB[/b] 가 됐다.
## 텍스트로 쓰면 글b 는 [code]instance=ExtResource(...)[/code] 한 줄로 남고 8KB 안에 들어간다.

const OUTPUT_DIR := "res://assets/adachi_rigged4"
const MODEL_PATH := "res://assets/adachi_rigged4/adachi_rigged4.glb"
const SCENE_SCRIPT := "res://demos/09_real_character/rig4_scene.gd"
const COMPARE_SCRIPT := "res://demos/09_real_character/rig4_compare.gd"
const COLLIDER_SCRIPT := "res://jiggle/jiggle_collider.gd"
const CHAIN_SCRIPT := "res://jiggle/bone_chain_modifier.gd"

const JIGGLE_SCENE := "adachi_rigged4_jiggle.tscn"
const SPRING_SCENE := "adachi_rigged4_springbone.tscn"
const COMPARE_SCENE := "adachi_rigged4_compare.tscn"

## 글b 안에서 스켈레톤까지의 경로. 씬 파일에 그대로 들어간다.
const SKELETON_PATH := "Character/metarig/Skeleton3D"
## 좌우로 벌려 놓는 거리(m). 치맛자락이 서로 안 닿을 만큼만 띄운다.
const COMPARE_OFFSET := 0.30

## Jiggle 쪽 설정. 데모 09에서 실측으로 고른 값이다.
const JIGGLE_PARAMS := {
	"hair": {
		"iterations": 6,
		"shape_stiffness": 0.10,
		"shape_elasticity": 0.0,
		"restore_frequency": 0.9,
		"drag": 0.25,
		"angle_limit_degrees": 35.0,
		"particle_radius": 0.012,
	},
	"skirt": {
		"iterations": 8,
		"shape_stiffness": 0.70,
		"shape_elasticity": 0.0,
		"restore_frequency": 0.7,
		"drag": 0.15,
		"angle_limit_degrees": 30.0,
		"particle_radius": 0.012,
	},
}

## 내장 쪽 대응값. [b]같은 이름이라고 같은 단위가 아니다[/b] — 아래는 환산한 값이다.
## stiffness = 복원 Hz / 3.5,  drag = Jiggle drag / 0.25,  gravity = m/s² × (1/9)
const SPRING_PARAMS := {
	"hair": {"stiffness": 0.26, "drag": 1.0, "gravity": 1.0, "radius": 0.012},
	"skirt": {"stiffness": 0.20, "drag": 0.60, "gravity": 1.0, "radius": 0.012},
}


## [b]작업은 Runner 의 _ready() 에서 한다.[/b] [method SceneTree._initialize] 시점에는
## 노드를 붙여도 아직 트리 안이 아니라서 [member Node3D.global_transform] 이
## [b]에러 하나 내고 항등행렬을 돌려준다[/b] — 이 모델은 월드 스케일이 0.5라
## 충돌체 반지름이 조용히 2배가 된다.
func _initialize() -> void:
	print("=== adachi_rigged4 비교 씬 생성 ===")
	var runner := Runner.new()
	runner.maker = self
	root.add_child(runner)


class Runner:
	extends Node

	var maker: SceneTree = null

	func _ready() -> void:
		# 리그 탐색은 CharacterRig 에 이미 있다. 여기서 다시 짜면 두 곳이 어긋난다.
		var probe := CharacterRig.new()
		add_child(probe)
		if not probe.build():
			printerr("모델을 못 불러왔다: %s" % CharacterRig.MODEL)
			get_tree().quit(1)
			return
		var ok: bool = maker.call("_emit_all", probe)
		probe.queue_free()
		get_tree().quit(0 if ok else 1)


func _emit_all(probe: CharacterRig) -> bool:
	var groups := _chain_groups(probe)
	var colliders := _collider_specs(probe)
	print("사슬 %d 가닥 · 충돌체 %d 개 · 골반 너비 %.4f m" % [
		groups.size(), colliders.size(), probe.hip_width
	])
	for spec: Dictionary in colliders:
		print("  %-18s 본 %-10s 반지름 %.4f 높이 %.4f" % [
			spec["name"], spec["bone"], spec["radius"], spec["height"]
		])
	return (
		_write(JIGGLE_SCENE, _jiggle_text(groups, colliders))
		and _write(SPRING_SCENE, _spring_text(groups, colliders))
		and _write(COMPARE_SCENE, _compare_text())
	)


## 사슬 목록을 그룹 이름과 함께 한 줄로 편다. 두 씬이 [b]같은 순서, 같은 집합[/b]을 받아야 한다.
func _chain_groups(rig: CharacterRig) -> Array[Dictionary]:
	var groups: Array[Dictionary] = []
	for chain: Dictionary in rig.hair_chains:
		groups.append({"group": "hair", "chain": chain})
	for chain: Dictionary in rig.skirt_chains:
		groups.append({"group": "skirt", "chain": chain})
	# 리본은 천에 가깝지만 얇아서 머리카락 설정을 쓴다.
	for chain: Dictionary in rig.ribbon_chains:
		groups.append({"group": "hair", "chain": chain})
	return groups


## 이미 만들어진 충돌체에서 치수를 읽어 온다. 숫자를 다시 계산하면 두 곳이 어긋난다.
func _collider_specs(rig: CharacterRig) -> Array[Dictionary]:
	var specs: Array[Dictionary] = []
	for collider in rig.all_colliders():
		var attachment := collider.get_parent() as BoneAttachment3D
		if attachment == null:
			continue
		specs.append({
			"bone": attachment.bone_name,
			"name": collider.name,
			"radius": collider.radius,
			"height": collider.height,
			"offset": collider.position,
		})
	return specs


# --- 씬 텍스트 ---------------------------------------------------------------


func _jiggle_text(groups: Array[Dictionary], colliders: Array[Dictionary]) -> String:
	var out := PackedStringArray()
	out.append("[gd_scene load_steps=5 format=3]\n")
	out.append('[ext_resource type="PackedScene" path="%s" id="1_model"]' % MODEL_PATH)
	out.append('[ext_resource type="Script" path="%s" id="2_scene"]' % SCENE_SCRIPT)
	out.append('[ext_resource type="Script" path="%s" id="3_collider"]' % COLLIDER_SCRIPT)
	out.append('[ext_resource type="Script" path="%s" id="4_chain"]\n' % CHAIN_SCRIPT)

	out.append('[node name="Rig4Jiggle" type="Node3D"]')
	out.append('script = ExtResource("2_scene")')
	out.append('title = "JiggleChainModifier3D"\n')
	out.append('[node name="Character" parent="." instance=ExtResource("1_model")]\n')

	var paths := PackedStringArray()
	for spec: Dictionary in colliders:
		var attachment := "%sAttachment" % spec["name"]
		paths.append('NodePath("../%s/%s")' % [attachment, spec["name"]])
		out.append('[node name="%s" type="BoneAttachment3D" parent="%s"]' % [
			attachment, SKELETON_PATH
		])
		out.append('bone_name = "%s"\n' % spec["bone"])
		out.append('[node name="%s" type="Node3D" parent="%s/%s"]' % [
			spec["name"], SKELETON_PATH, attachment
		])
		out.append(_transform_line(spec["offset"]))
		out.append('script = ExtResource("3_collider")')
		out.append("radius = %s" % _number(spec["radius"]))
		out.append("height = %s\n" % _number(spec["height"]))

	var collider_list := "Array[NodePath]([%s])" % ", ".join(paths)
	for entry: Dictionary in groups:
		var chain: Dictionary = entry["chain"]
		var params: Dictionary = JIGGLE_PARAMS[entry["group"]]
		out.append('[node name="Jiggle_%s" type="SkeletonModifier3D" parent="%s"]' % [
			String(chain["root"]).replace(".", "_"), SKELETON_PATH
		])
		out.append('script = ExtResource("4_chain")')
		out.append('root_bone_name = "%s"' % chain["root"])
		out.append('end_bone_name = "%s"' % chain["end"])
		out.append("tip_axis = Vector3(0, 1, 0)")
		out.append("tip_length = %s" % _number(chain["tip_length"]))
		for key: String in params:
			out.append("%s = %s" % [key, _number(params[key])])
		out.append("collider_paths = %s\n" % collider_list)

	out.append('[editable path="Character"]')
	return "\n".join(out)


func _spring_text(groups: Array[Dictionary], colliders: Array[Dictionary]) -> String:
	var out := PackedStringArray()
	out.append("[gd_scene load_steps=3 format=3]\n")
	out.append('[ext_resource type="PackedScene" path="%s" id="1_model"]' % MODEL_PATH)
	out.append('[ext_resource type="Script" path="%s" id="2_scene"]\n' % SCENE_SCRIPT)

	out.append('[node name="Rig4SpringBone" type="Node3D"]')
	out.append('script = ExtResource("2_scene")')
	out.append('title = "내장 SpringBoneSimulator3D"\n')
	out.append('[node name="Character" parent="." instance=ExtResource("1_model")]\n')

	# 내장 충돌체는 본에 [b]직접[/b] 붙는다. BoneAttachment3D 가 필요 없다.
	for spec: Dictionary in colliders:
		var is_capsule: bool = float(spec["height"]) > 0.001
		var type := "SpringBoneCollisionCapsule3D" if is_capsule else "SpringBoneCollisionSphere3D"
		out.append('[node name="Spring%s" type="%s" parent="%s"]' % [
			spec["name"], type, SKELETON_PATH
		])
		out.append(_transform_line(spec["offset"]))
		out.append('bone_name = "%s"' % spec["bone"])
		out.append("radius = %s" % _number(spec["radius"]))
		if is_capsule:
			# 캡슐 높이는 지름보다 작을 수 없다.
			var height := maxf(float(spec["height"]), float(spec["radius"]) * 2.0 + 0.001)
			out.append("height = %s" % _number(height))
		out.append("")

	# 이쪽은 "사슬 하나 = 노드 하나"였지만, 내장은 시뮬레이터 하나가 설정 슬롯을 갖는다.
	out.append('[node name="SpringBoneSimulator3D" type="SpringBoneSimulator3D" parent="%s"]'
		% SKELETON_PATH)
	out.append("setting_count = %d" % groups.size())
	for index in groups.size():
		var chain: Dictionary = groups[index]["chain"]
		var params: Dictionary = SPRING_PARAMS[groups[index]["group"]]
		out.append('settings/%d/root_bone_name = "%s"' % [index, chain["root"]])
		out.append('settings/%d/end_bone_name = "%s"' % [index, chain["end"]])
		# 마지막 본에는 자식이 없다. 끝점을 만들어 달라고 알려 줘야 한다.
		out.append("settings/%d/extend_end_bone = true" % index)
		out.append("settings/%d/end_bone/direction = 6" % index)
		out.append("settings/%d/end_bone/length = %s" % [index, _number(chain["tip_length"])])
		out.append("settings/%d/radius/value = %s" % [index, _number(params["radius"])])
		out.append("settings/%d/stiffness/value = %s" % [index, _number(params["stiffness"])])
		out.append("settings/%d/drag/value = %s" % [index, _number(params["drag"])])
		# 내장 gravity 는 m/s² 가 아니다. 9.8을 그대로 넣으면 흔들림이 사라진다.
		out.append("settings/%d/gravity/value = %s" % [index, _number(params["gravity"])])
		out.append("settings/%d/gravity/direction = Vector3(0, -1, 0)" % index)
		out.append("settings/%d/enable_all_child_collisions = true" % index)
	out.append("")
	out.append('[editable path="Character"]')
	return "\n".join(out)


func _compare_text() -> String:
	var out := PackedStringArray()
	out.append("[gd_scene load_steps=4 format=3]\n")
	out.append('[ext_resource type="PackedScene" path="%s/%s" id="1_jiggle"]' % [
		OUTPUT_DIR, JIGGLE_SCENE
	])
	out.append('[ext_resource type="PackedScene" path="%s/%s" id="2_spring"]' % [
		OUTPUT_DIR, SPRING_SCENE
	])
	out.append('[ext_resource type="Script" path="%s" id="3_compare"]\n' % COMPARE_SCRIPT)

	out.append('[node name="Rig4Compare" type="Node3D"]')
	out.append('script = ExtResource("3_compare")\n')

	# 각자 자극을 돌리면 위상이 어긋난다. 밖에서만 움직이게 한다.
	out.append('[node name="Jiggle" parent="." instance=ExtResource("1_jiggle")]')
	out.append(_transform_line(Vector3(-COMPARE_OFFSET, 0.0, 0.0)))
	out.append("external_drive = true\n")
	out.append('[node name="SpringBone" parent="." instance=ExtResource("2_spring")]')
	out.append(_transform_line(Vector3(COMPARE_OFFSET, 0.0, 0.0)))
	out.append("external_drive = true")
	return "\n".join(out)


# --- 도우미 ------------------------------------------------------------------


func _transform_line(offset: Vector3) -> String:
	return "transform = Transform3D(1, 0, 0, 0, 1, 0, 0, 0, 1, %s, %s, %s)" % [
		_number(offset.x), _number(offset.y), _number(offset.z)
	]


## .tscn 은 [code]1[/code] 과 [code]1.0[/code] 을 int/float 로 구분한다.
## int 로 써야 할 값(iterations)과 float 을 섞으면 로드할 때 타입이 안 맞는다.
func _number(value: Variant) -> String:
	if value is int:
		return str(value)
	return "%.6f" % float(value)


func _write(file_name: String, text: String) -> bool:
	var path := "%s/%s" % [OUTPUT_DIR, file_name]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		printerr("저장 실패(%s): %d" % [path, FileAccess.get_open_error()])
		return false
	file.store_string(text + "\n")
	file.close()
	print("  만들었다: %s" % path)
	return true
