import tile, terminal, strutils, sequtils
when (NimMajor, NimMinor) >= (0, 20):
  import std/wordwrap
else:
  proc wrapWords(s: string, maxLineWidth: int): string = wordWrap(s, maxLineWidth)

export tile

type ListElement* = object
  id: string
  title: string
  content: string

type ListTile* = ref object of Tile
  elements: seq[ListElement]
  focusIndex: int
  focusBottom: int
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

proc bottom(tile: ListTile): int =
  if tile.focussed: tile.focusBottom
  else: max(0, tile.elements.len() - 1)

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
  var nextHeight = tile.elementHeight(tile.elements[tile.bottom()])
  proc hasSpace(): bool =
    consumedHeight + nextHeight - tile.elementSpacing <= tile.height() - 2
  while result < tile.elements.len() and hasSpace():
    consumedHeight = consumedHeight + nextHeight
    result.inc()
    let nextIndex = tile.bottom() - result
    if nextIndex >= 0:
      nextHeight = tile.elementHeight(tile.elements[nextIndex])

proc elementPos(tile: ListTile, index: int): Point =
  assert(index >= 0 and index <= tile.elements.len())
  let firstElemY = tile.topLeft().y + 1
  proc height(i: int): int = tile.elementHeight(tile.elements[i])
  let topIndex = tile.bottom() - tile.elementCount() + 1
  result.x = tile.topLeft().x + 1
  result.y = toSeq(topIndex .. (index - 1)).map(height).foldl(a + b, firstElemY)

proc focusElement(tile: ListTile, index: int) =
  assert(index >= 0 and index <= tile.bottom())
  let pos = tile.elementPos(index)
  writeLeftAligned(pos,
                   tile.width() - 2,
                   tile.elements[index].title,
                   1,
                   fgDefault,
                   bgRed)
 
proc unfocusElement(tile: ListTile, index: int) =
  assert(index >= 0 and index <= tile.bottom())
  let pos = tile.elementPos(index)
  writeLeftAligned(pos,
                   tile.width() - 2,
                   tile.elements[index].title,
                   1,
                   fgCyan,
                   bgDefault)

proc presentElement(tile: ListTile, index: int) =
  assert(index >= 0 and index < tile.elements.len())
  tile.unfocusElement(index)
  let element = tile.elements[index]
  if element.content.len() > 0:
    let lines = element.content.wrapWords(tile.width() - 4).splitLines()
    let pos = tile.elementPos(index)
    for i in 0 .. (tile.elementHeight(element) - tile.elementSpacing - 2):
      writeLeftAligned((pos.x, pos.y + i + 1), tile.width() - 2, lines[i])

method focus*(this: ListTile) =
  this.focussed = true
  this.clear()
  stdout.setForegroundColor(fgRed)
  drawBox(this.topLeft(), this.bottomRight())
  resetAttributes()
  if this.elements.len() > 0:
    let topIndex = this.bottom() - this.elementCount() + 1
    for i in topIndex .. this.bottom():
      this.presentElement(i)
    this.focusElement(this.focusIndex)

method unfocus*(this: ListTile) =
  this.focussed = false
  this.clear()
  drawBox(this.topLeft(), this.bottomRight())
  if this.elements.len() > 0:
    let topIndex = this.bottom() - this.elementCount() + 1
    for i in topIndex .. this.bottom():
      this.presentElement(i)

method present*(tile: ListTile) =
  if tile.focussed:
    tile.focus()
  else:
    tile.unfocus()

proc focusNextElement*(tile: ListTile) =
  assert(tile.focussed)
  if tile.elements.len() == 0:
    return
  tile.unfocusElement(tile.focusIndex)
  if tile.focusIndex < tile.focusBottom:
    tile.focusIndex.inc()
  elif tile.focusIndex < tile.elements.len() - 1:
    tile.focusIndex.inc()
    tile.focusBottom.inc()
    tile.present()
  tile.focusElement(tile.focusIndex)

proc focusPrevElement*(tile: ListTile) =
  assert(tile.focussed)
  if tile.elements.len() == 0:
    return
  tile.unfocusElement(tile.focusIndex)
  let elementCount = tile.elementCount()
  if tile.focusIndex > tile.focusBottom - elementCount + 1:
    tile.focusIndex.dec()
  elif tile.focusBottom >= elementCount:
    tile.focusBottom.dec()
    tile.focusIndex = tile.focusBottom - elementCount + 1
    tile.present()
  tile.focusElement(tile.focusIndex)

proc addElement*(tile: ListTile, id: string, title: string, content = "") =
  tile.elements.add(ListElement(id: id, title: title, content: content))
  if tile.focussed:
    tile.focusBottom = max(tile.elementCount() - 1, tile.focusBottom)
  else:
    tile.focusBottom = tile.elements.len() - 1
    tile.focusIndex = tile.focusBottom - tile.elementCount() + 1
  tile.present()

proc deleteElement*(tile: ListTile, id: string) =
  for i in 0 .. tile.elements.len() - 1:
    if tile.elements[i].id == id:
      tile.elements.delete(i)
      tile.focusBottom = min(tile.elements.len() - 1, tile.focusBottom)
      tile.focusBottom = max(0, tile.focusBottom)
      tile.focusIndex = min(tile.elements.len() - 1, tile.focusIndex)
      tile.focusIndex = max(0, tile.focusIndex)
      tile.present()
      break

method processInput*(this: ListTile, ch: char) =
  case ch
  of 'j': this.focusNextElement()
  of 'k': this.focusPrevElement()
  of 'd': this.deleteElement("x")
  else: discard
