class_name Palette
extends RefCounted
## Player colors offered in the lobby. Slot N defaults to color N.

const PLAYER_COLORS := [
	Color(0.96, 0.96, 0.96),  # White
	Color(0.17, 0.17, 0.19),  # Black
	Color(0.88, 0.20, 0.17),  # Red
	Color(0.18, 0.44, 0.88),  # Blue
	Color(0.25, 0.72, 0.30),  # Green
	Color(0.98, 0.82, 0.18),  # Yellow
	Color(0.95, 0.45, 0.75),  # Pink
	Color(0.20, 0.80, 0.82),  # Aqua
]

const PLAYER_COLOR_NAMES := ["White", "Black", "Red", "Blue", "Green", "Yellow", "Pink", "Aqua"]


## Readable text color on top of a player color.
static func text_on(color: Color) -> Color:
	return Color.BLACK if color.get_luminance() > 0.5 else Color.WHITE
