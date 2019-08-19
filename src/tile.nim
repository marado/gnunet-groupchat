import terminal, unicode, strutils

type Point* = tuple
  x: int
  y: int

proc drawHorizontalLine*(origin: Point, length: int, symbol = "─") =
  if origin.x < terminalWidth() and
     origin.x + length > 0 and
     origin.y < terminalHeight() and
     origin.y >= 0:
    let firstX = max(0, origin.x)
    let lastX = min(terminalWidth() - 1, origin.x + length - 1)
    for x in firstX .. lastX:
      setCursorPos(x, origin.y)
      stdout.write(symbol)

proc drawVerticalLine*(origin: Point, length: int, symbol = "│") =
  if origin.y < terminalHeight() and
     origin.y + length > 0 and
     origin.x < terminalWidth() and
     origin.x >= 0:
    let firstY = max(0, origin.y)
    let lastY = min(terminalHeight() - 1, origin.y + length - 1)
    for y in firstY .. lastY:
      setCursorPos(origin.x, y)
      stdout.write(symbol)

proc truncateLeft*(unicode: string, length: int): string =
  assert(length >= 0)
  let runes = unicode.toRunes()
  if runes.len() > length:
    $runes[(unicode.runeLen() - length) .. ^1]
  else:
    $runes

proc truncateRight*(unicode: string, length: int): string =
  assert(length >= 0)
  let runes = unicode.toRunes()
  if runes.len() > length:
    $runes[0 .. (length - 1)]
  else:
    $runes

proc writeLeftAligned*(origin: Point,
                       length: int,
                       content: string,
                       padding = 1,
                       fgColor = fgDefault,
                       bgColor = bgDefault) =
  setForegroundColor(fgColor)
  setBackgroundColor(bgColor)
  setCursorPos(origin.x, origin.y)
  let truncatedContent = content.truncateRight(length - 2 * padding)
  stdout.write(repeat(' ', padding))
  stdout.write(unicode.alignLeft(truncatedContent, length - 2 * padding))
  stdout.write(repeat(' ', padding))
  resetAttributes()

type Tile* = ref object of RootObj
  help*: string
  focussed*: bool

method topLeft*(this: Tile): Point {.base.} = (0, 0)

method bottomRight*(this: Tile): Point {.base.} = (0, 0)

method focus*(this: Tile) {.base.} = discard

method unfocus*(this: Tile) {.base.} = discard

method processInput*(this: Tile, ch: char) {.base.} = discard

method width*(this: Tile): int {.base.} =
  this.bottomRight().x - this.topLeft().x + 1

method height*(this: Tile): int {.base.} =
  this.bottomRight().y - this.topLeft().y + 1

method present*(this: Tile) {.base.} = discard

method clear*(this: Tile) {.base.} =
  let topLeft = this.topLeft()
  let bottomRight = this.bottomRight()
  for y in topLeft.y .. bottomRight.y:
    drawHorizontalLine((topLeft.x, y), bottomRight.x - topLeft.x + 1, " ")
