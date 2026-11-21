extends RefCounted
## Base for test files: extend this and write test_* methods that call check / check_eq.

var failures: Array[String] = []


func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s: expected %s, got %s" % [message, expected, actual])


## Builds a Grid from ASCII rows: '#' hard, '+' soft, anything else empty.
func grid_from_rows(rows: Array) -> Grid:
	var grid := Grid.new(rows[0].length(), rows.size())
	for y in rows.size():
		for x in rows[y].length():
			if rows[y][x] == "#":
				grid.set_cell(Vector2i(x, y), Grid.Cell.HARD)
			elif rows[y][x] == "+":
				grid.set_cell(Vector2i(x, y), Grid.Cell.SOFT)
	return grid
