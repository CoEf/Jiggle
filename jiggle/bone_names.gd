@tool
class_name JiggleBoneNames
extends RefCounted

## 인스펙터에 [b]본 이름 드롭다운[/b]을 만들기 위한 도우미.
##
## [SkeletonModifier3D] 하위 클래스에서 [method Object._validate_property] 로 이렇게 쓴다.
## [codeblock]
## func _validate_property(property: Dictionary) -> void:
##     if property.name != "bone_name":
##         return
##     var hint := JiggleBoneNames.enum_hint(get_skeleton())
##     if hint.is_empty():
##         return
##     property.hint = PROPERTY_HINT_ENUM
##     property.hint_string = hint
## [/codeblock]
##
## [b]왜 굳이 이렇게 하는가[/b] — 본 이름을 손으로 적게 두면 오타 한 글자에
## [code]find_bone()[/code] 이 −1을 돌려주고, 모디파이어는 아무 말 없이 조용히 아무것도
## 안 한다. 원인을 찾는 데 시간이 가장 많이 드는 종류의 실수다.


## [param modifier] 가 붙은 [Skeleton3D]. [b][method SkeletonModifier3D.get_skeleton] 대신 쓴다.[/b]
##
## 엔진의 [code]get_skeleton()[/code] 은 캐시를 미뤄서 갱신하기 때문에
## [b]노드를 붙인 그 순간에는 null 을 돌려준다[/b](실측: [code]add_child()[/code] 직후 null,
## 한 프레임 뒤부터 정상). 시뮬레이션은 다음 프레임부터 돌면 되니 상관없지만,
## [b]인스펙터는 지금 당장 그려야 한다.[/b]
##
## 이걸 안 쓰면 이렇게 된다 — 스켈레톤에 노드를 떨어뜨리고 본 이름을 고르려는데
## 드롭다운이 안 나오고, 이름 규칙을 적었는데 찾아낸 목록이 비어 있고,
## 잘못 놓았는데 경고도 안 뜬다. [b]전부 "조용히 아무 일도 안 일어난다"로 보인다[/b] —
## 이 드롭다운이 없애려는 바로 그 경험이다.
static func skeleton_of(modifier: SkeletonModifier3D) -> Skeleton3D:
	if modifier == null:
		return null
	var skeleton := modifier.get_skeleton()
	if skeleton != null:
		return skeleton
	# 모디파이어는 어차피 Skeleton3D 의 직속 자식이어야 하므로 부모가 곧 답이다.
	return modifier.get_parent() as Skeleton3D


## 스켈레톤의 모든 본 이름을 [constant @GlobalScope.PROPERTY_HINT_ENUM] 용 문자열로 만든다.
##
## 스켈레톤이 없거나 본이 없으면 빈 문자열을 돌려준다. 이때 호출한 쪽은 힌트를
## [b]건드리지 말아야 한다[/b] — 선택지가 하나도 없는 드롭다운을 만들어 두면 그 속성을
## 인스펙터에서 고칠 방법 자체가 사라지기 때문이다. 그냥 문자열 입력칸으로 두는 편이 낫다.
static func enum_hint(skeleton: Skeleton3D) -> String:
	if skeleton == null:
		return ""
	var count := skeleton.get_bone_count()
	if count <= 0:
		return ""
	var names := PackedStringArray()
	for bone in count:
		names.append(skeleton.get_bone_name(bone))
	return ",".join(names)
