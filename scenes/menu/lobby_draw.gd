extends RefCounted
## Drawing helpers for the versus screen's portrait tiles and slot cards. All placeholder art,
## drawn in code: a round bomber face per colour, a padlock, the Random mark and player tags.

const TAG_SIZE := Vector2(26, 17)
const TAG_FONT := 13


## A round face in `color` with two eyes.
static func face(ci: CanvasItem, center: Vector2, radius: float, color: Color) -> void:
	var outline := Color(1, 1, 1, 0.8) if color.get_luminance() < 0.25 else Color(0, 0, 0, 0.8)
	ci.draw_circle(center, radius, color)
	ci.draw_arc(center, radius, 0.0, TAU, 40, outline, maxf(2.0, radius * 0.07), true)
	ci.draw_circle(center + Vector2(-radius * 0.45, -radius * 0.45), radius * 0.13, Color(1, 1, 1, 0.4))
	var eye := Palette.text_on(color)
	for side: float in [-1.0, 1.0]:
		ellipse(ci, center + Vector2(side * radius * 0.32, radius * 0.02), Vector2(radius * 0.15, radius * 0.3), eye)


static func ellipse(ci: CanvasItem, center: Vector2, radii: Vector2, color: Color) -> void:
	var points := PackedVector2Array()
	for i in 20:
		var angle := TAU * i / 20.0
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	ci.draw_colored_polygon(points, color)


## A locked portrait.
static func padlock(ci: CanvasItem, center: Vector2, radius: float) -> void:
	var grey := Color(0.5, 0.55, 0.65)
	var hole := Color(0.08, 0.1, 0.16)
	ci.draw_arc(center + Vector2(0.0, -radius * 0.15), radius * 0.42, PI, TAU, 20, grey, radius * 0.17, true)
	ci.draw_rect(Rect2(center.x - radius * 0.66, center.y - radius * 0.18, radius * 1.32, radius * 0.98), grey)
	ci.draw_circle(center + Vector2(0.0, radius * 0.2), radius * 0.13, hole)
	ci.draw_rect(Rect2(center.x - radius * 0.05, center.y + radius * 0.22, radius * 0.1, radius * 0.32), hole)


## Random: a ring of every playable colour around a question mark.
static func random_mark(ci: CanvasItem, center: Vector2, radius: float, font: Font) -> void:
	var count := Palette.PLAYER_COLORS.size()
	for i in count:
		var start := TAU * i / count - PI / 2.0
		ci.draw_arc(center, radius * 0.9, start, start + TAU / count, 8, Palette.PLAYER_COLORS[i], radius * 0.22, true)
	var font_size := int(radius * 1.3)
	ci.draw_string(font, Vector2(center.x - radius, center.y + font_size * 0.36), "?",
		HORIZONTAL_ALIGNMENT_CENTER, radius * 2.0, font_size, Color.WHITE)


## A "P1" tag in that player's cursor colour: filled for a claim, outlined for a cursor.
static func tag(ci: CanvasItem, font: Font, pos: Vector2, slot: int, filled: bool) -> void:
	var color: Color = Palette.CURSOR_COLORS[slot]
	var rect := Rect2(pos, TAG_SIZE)
	ci.draw_rect(rect, color if filled else Color(0, 0, 0, 0.8))
	if not filled:
		ci.draw_rect(rect, color, false, 2.0)
	var text_color := Palette.text_on(color) if filled else color
	ci.draw_string(font, pos + Vector2(0.0, TAG_SIZE.y - 4.0), "P%d" % (slot + 1),
		HORIZONTAL_ALIGNMENT_CENTER, TAG_SIZE.x, TAG_FONT, text_color)


## Tags for `slots` in rows of three, from `origin` (left to right, rows going down when
## `step_y` > 0, up when < 0).
static func tag_rows(ci: CanvasItem, font: Font, origin: Vector2, slots: Array, filled: bool, step_y := 1.0) -> void:
	for i in slots.size():
		var offset := Vector2((i % 3) * (TAG_SIZE.x + 3.0), (i / 3) * (TAG_SIZE.y + 2.0) * step_y)
		tag(ci, font, origin + offset, slots[i], filled)


## Cursor highlight: one inset frame per cursor in its colour, plus their tags at `tag_origin`.
## `carried`: cursor slot -> AI slot whose token it carries, drawn filled just below its tag.
static func cursors(ci: CanvasItem, font: Font, rect: Rect2, slots: Array, tag_origin: Vector2, carried := {}) -> void:
	for i in slots.size():
		ci.draw_rect(rect.grow(-1.5 - i * 4.0), Palette.CURSOR_COLORS[slots[i]], false, 3.0)
	tag_rows(ci, font, tag_origin, slots, false)
	for i in slots.size():
		if carried.has(slots[i]):
			var offset := Vector2((i % 3) * (TAG_SIZE.x + 3.0), (i / 3) * (TAG_SIZE.y + 2.0) + TAG_SIZE.y + 2.0)
			tag(ci, font, tag_origin + offset, carried[slots[i]], true)
