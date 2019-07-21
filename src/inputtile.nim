import tile, terminal, unicode
export tile

type InputTile* = ref object of Tile
  input*: string

method topLeft*(this: InputTile): Point =
  (0, terminalHeight() - 1)

method bottomRight*(this: InputTile): Point =
  (terminalWidth() - 1, terminalHeight() - 1)

method focus*(this: InputTile) =
  this.focussed = true
  setCursorPos(this.topLeft().x + this.input.runeLen(), this.topLeft().y)
  showCursor()

method unfocus*(this: InputTile) =
  this.focussed = false
  hideCursor()

method present*(this: InputTile) =
  let displayedInput = this.input.truncateLeft(this.width() - 1)
  writeLeftAligned(this.topLeft(), this.width(), displayedInput, 0)
  if this.focussed:
    this.focus()
  else:
    this.unfocus()

method processInput*(this: InputTile, ch: char) =
  case ch
  of '\x08', '\x7f': # Backspace
    let length = this.input.runeLen()
    if length > 0:
      this.input = this.input.truncateRight(length - 1)
  of ' ' .. '\x7e', '\x80' .. high(char):
    this.input.add(ch)
  else:
    discard
  this.present()

proc newInputTile*(): InputTile =
  InputTile(help: "new channel: C-n | select channel: C-s | " &
                  "edit title: C-e | switch area: Tab | quit: C-c")

proc reset*(tile: var InputTile) =
  tile.input.reset()
  tile.present()


