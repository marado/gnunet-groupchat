import tile, terminal, strutils, sequtils
when (NimMajor, NimMinor) >= (0, 20):
  import std/wordwrap
else:
  proc wrapWords(s: string, maxLineWidth: int): string = wordWrap(s, maxLineWidth)

export tile

# ListTile
type ListElement* = object
  id: string
  title: string
  content: string

type ListTile* = ref object of Tile
  elements: seq[ListElement]
  displayBottomIndex: int
  focusIndex: int
  elementSpacing*: int

proc drawBox*(topLeft: Point, bottomRight: Point) =
  drawHorizontalLine(topLeft, bottomRight.x - topLeft.x)
  drawHorizontalLine((topLeft.x, bottomRight.y), bottomRight.x - topLeft.x)
  drawVerticalLine(topLeft, bottomRight.y - topLeft.y)
  drawVerticalLine((bottomRight.x, topLeft.y), bottomRight.y - topLeft.y)
  setCursorPos(topLeft.x, topLeft.y)
  stdout.write("┌")
  setCursorPos(bottomRight.x, topLeft.y)
  stdout.write("┐")
  setCursorPos(topLeft.x, bottomRight.y)
  stdout.write("└")
  setCursorPos(bottomRight.x, bottomRight.y)
  stdout.write("┘")

proc elementHeight(tile: ListTile, element: ListElement): int =
  result = 1 + tile.elementSpacing
  if element.content.len() > 0:
    let contentHeight = element.content.wrapWords(tile.width() - 4).countLines()
    result.inc(min(contentHeight, tile.height() - 2))

proc elementCount*(tile: ListTile): int =
  result = 0
  if tile.elements.len() == 0:
    return
  var consumedHeight = 0
  var nextHeight = tile.elementHeight(tile.elements[tile.displayBottomIndex])
  proc hasSpace(): bool =
    consumedHeight + nextHeight - tile.elementSpacing <= tile.height() - 2
  while result < tile.elements.len() and hasSpace():
    consumedHeight = consumedHeight + nextHeight
    result.inc()
    let nextIndex = tile.displayBottomIndex - result
    if nextIndex >= 0:
      nextHeight = tile.elementHeight(tile.elements[nextIndex])

proc element*(tile: ListTile, index: int): ListElement =
  let realIndex = tile.displayBottomIndex - tile.elementCount() + 1 + index
  tile.elements[realIndex]

proc elementPos(tile: ListTile, index: int): Point =
  assert(index >= 0 and index <= tile.elementCount())
  let firstElemY = tile.topLeft().y + 1
  proc height(i: int): int = tile.elementHeight(tile.element(i))
  result.x = tile.topLeft().x + 1
  result.y = toSeq(0 .. (index - 1)).map(height).foldl(a + b, firstElemY)

proc focusElement(tile: ListTile, index: int) =
  assert(index >= 0 and index < tile.elementCount())
  let pos = tile.elementPos(index)
  writeLeftAligned(pos,
                   tile.width() - 2,
                   tile.element(index).title,
                   1,
                   fgDefault,
                   bgRed)
 
proc unfocusElement(tile: ListTile, index: int) =
  assert(index >= 0 and index < tile.elementCount())
  let pos = tile.elementPos(index)
  writeLeftAligned(pos,
                   tile.width() - 2,
                   tile.element(index).title,
                   1,
                   fgCyan,
                   bgDefault)

proc presentElement(tile: ListTile, index: int) =
  tile.unfocusElement(index)
  let element = tile.element(index)
  if element.content.len() > 0:
    let lines = element.content.wrapWords(tile.width() - 4).splitLines()
    let pos = tile.elementPos(index)
    for i in 0 .. (tile.elementHeight(element) - tile.elementSpacing - 2):
      writeLeftAligned((pos.x, pos.y + i + 1), tile.width() - 2, lines[i])

method focus*(this: ListTile) =
  this.focussed = true
  stdout.setForegroundColor(fgRed)
  drawBox(this.topLeft(), this.bottomRight())
  resetAttributes()
  if this.elementCount() > 0:
    this.focusElement(this.focusIndex)

method unfocus*(this: ListTile) =
  this.focussed = false
  drawBox(this.topLeft(), this.bottomRight())
  if this.elementCount() > 0:
    this.unfocusElement(this.focusIndex)

method present*(tile: ListTile) =
  tile.clear()
  for i in 0 .. (tile.elementCount() - 1):
    tile.presentElement(i)
  if tile.focussed:
    tile.focus()
  else:
    tile.unfocus()

proc focusNextElement*(tile: ListTile) =
  let elementCount = tile.elementCount()
  if elementCount == 0:
    return
  tile.unfocusElement(tile.focusIndex)
  if tile.focusIndex < elementCount - 1:
    tile.focusIndex.inc()
  elif tile.displayBottomIndex < tile.elements.len() - 1:
    tile.displayBottomIndex.inc()
    tile.focusIndex = tile.elementCount() - 1
    tile.present()
  tile.focusElement(tile.focusIndex)

proc focusPrevElement*(tile: ListTile) =
  let elementCount = tile.elementCount()
  if elementCount == 0:
    return
  tile.unfocusElement(tile.focusIndex)
  if tile.focusIndex > 0:
    tile.focusIndex.dec()
  elif tile.displayBottomIndex >= elementCount:
    tile.displayBottomIndex.dec()
    tile.focusIndex = 0
    tile.present()
  tile.focusElement(tile.focusIndex)

method processInput*(this: ListTile, ch: char) =
  case ch
  of 'j': this.focusNextElement()
  of 'k': this.focusPrevElement()
  else: discard

proc addElement*(tile: ListTile, id: string, title: string, content = "") =
  tile.elements.add(ListElement(id: id, title: title, content: content))
  tile.displayBottomIndex = tile.elements.len() - 1
  tile.present()

proc deleteElement*(tile: ListTile, id: string) =
  for i in 0 .. tile.elements.len() - 1:
    if tile.elements[i].id == id:
      tile.elements.delete(i)
      tile.displayBottomIndex = min(tile.elements.len() - 1, tile.displayBottomIndex)
      tile.displayBottomIndex = max(0, tile.displayBottomIndex)
      tile.focusIndex = min(tile.elementCount() - 1, tile.focusIndex)
      tile.focusIndex = max(0, tile.focusIndex)
      tile.present()
      break


