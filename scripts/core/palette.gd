class_name Palette
extends RefCounted
## Player colors offered in the lobby (one portrait each). Slot N defaults to color N.

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

## Versus screen cursor and tag colour per player number (P1..P6), apart from the bomber colours.
const CURSOR_COLORS := [
	Color(0.95, 0.27, 0.25),  # P1 red
	Color(0.27, 0.56, 1.00),  # P2 blue
	Color(1.00, 0.84, 0.20),  # P3 yellow
	Color(0.33, 0.88, 0.40),  # P4 green
	Color(0.76, 0.45, 1.00),  # P5 purple
	Color(1.00, 0.58, 0.18),  # P6 orange
]


## Readable text color on top of a player color.
static func text_on(color: Color) -> Color:
	return Color.BLACK if color.get_luminance() > 0.5 else Color.WHITE
