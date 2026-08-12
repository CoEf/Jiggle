class_name JigglePlot
extends Control

## 변위-시간 그래프 오버레이.
##
## 3D 화면만 봐서는 "지금 오버슈트가 몇 %인지", "몇 초 만에 멈추는지"를 감으로만
## 알 수 있다. 이 그래프는 그 감을 숫자와 곡선으로 바꿔준다.
## 부족감쇠/임계감쇠/과감쇠의 차이는 3D보다 여기서 훨씬 선명하게 보인다.

const CAPACITY := 420
const MARGIN := 8.0

## 그래프 위쪽에 표시할 부가 정보(감쇠비 등).
var info_text := ""

var _order: PackedStringArray = PackedStringArray()
var _values: Dictionary[String, PackedFloat32Array] = {}
var _colors: Dictionary[String, Color] = {}
var _scale := 0.1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func configure(series: Array[Dictionary]) -> void:
	_order = PackedStringArray()
	_values.clear()
	_colors.clear()
	_scale = 0.1
	for entry in series:
		var id: String = entry.get("id", "")
		if id.is_empty():
			continue
		_order.append(id)
		_values[id] = PackedFloat32Array()
		_colors[id] = entry.get("color", Color.WHITE)
	queue_redraw()


func push(id: String, value: float) -> void:
	if not _values.has(id):
		return
	var series := _values[id]
	series.append(value)
	if series.size() > CAPACITY:
		series.remove_at(0)
	_values[id] = series


## 한 프레임분 샘플을 한 번에 밀어넣는다. 데모는 이 함수만 부르면 된다.
func push_frame(samples: Dictionary) -> void:
	for id: String in samples:
		push(id, samples[id])
	queue_redraw()


func clear_samples() -> void:
	for id: String in _values:
		_values[id] = PackedFloat32Array()
	_scale = 0.1
	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var font_size := 12
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Color(0.05, 0.06, 0.08, 0.72))
	draw_rect(rect, Color(1.0, 1.0, 1.0, 0.10), false, 1.0)

	var plot_top := MARGIN + 16.0
	var plot_height := size.y - plot_top - MARGIN
	var plot_width := size.x - MARGIN * 2.0
	if plot_height <= 4.0 or plot_width <= 4.0:
		return
	var mid := plot_top + plot_height * 0.5

	# 0 기준선. 곡선이 이 선을 몇 번 가로지르는지가 곧 진동 횟수다.
	draw_line(
		Vector2(MARGIN, mid), Vector2(size.x - MARGIN, mid), Color(1.0, 1.0, 1.0, 0.22), 1.0
	)

	# 스케일은 관측된 최대 진폭을 천천히 따라간다. 즉시 맞추면 그래프가 요동친다.
	var peak := 0.0
	for id in _order:
		for value in _values[id]:
			peak = maxf(peak, absf(value))
	_scale = maxf(_scale * 0.97, maxf(peak * 1.15, 0.02))

	for id in _order:
		var series := _values[id]
		if series.size() < 2:
			continue
		var points := PackedVector2Array()
		var count := series.size()
		for i in count:
			var x := MARGIN + plot_width * (float(i) / float(CAPACITY - 1))
			var y := mid - (series[i] / _scale) * (plot_height * 0.5)
			points.append(Vector2(x, clampf(y, plot_top, plot_top + plot_height)))
		draw_polyline(points, _colors[id], 1.6, true)

	var header := info_text
	if header.is_empty():
		header = "변위 (목표 대비)   ±%.3f" % _scale
	draw_string(
		font,
		Vector2(MARGIN + 2.0, MARGIN + 12.0),
		header,
		HORIZONTAL_ALIGNMENT_LEFT,
		-1,
		font_size,
		Color(0.85, 0.88, 0.95, 0.9)
	)
