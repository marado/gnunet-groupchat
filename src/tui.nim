import inputtile, listtile, terminal, asyncdispatch, threadpool
export inputtile, listtile

# ConversationTile
type ConversationTile* = ref object of ListTile

method topLeft*(this: ConversationTile): Point =
  (0, 1)

method bottomRight*(this: ConversationTile): Point =
  (terminalWidth() - 25, terminalHeight() - 3)

proc newConversationTile*(): ConversationTile =
  result = ConversationTile(help: "next element: j | previous element: k | " &
                                  "switch area: Tab | quit: C-c",
                            elementSpacing: 1)
  result.present()

# ParticipantsTile
type ParticipantsTile* = ref object of ListTile

method topLeft*(this: ParticipantsTile): Point =
  (terminalWidth() - 24, 1)

method bottomRight*(this: ParticipantsTile): Point =
  (terminalWidth() - 1, terminalHeight() - 3)

proc newParticipantsTile*(): ParticipantsTile =
  result = ParticipantsTile(help: "next element: j | previous element: k | " &
                                  "switch area: Tab | quit: C-c")
  result.present()

# Tui
type Tui* = ref object
  inputTile*: InputTile
  conversationTile*: ConversationTile
  participantsTile*: ParticipantsTile
  tiles: seq[Tile]
  focusIndex: int

proc writeTitleBar*(tui: Tui, title: string) =
  writeLeftAligned((0, 0),
                   terminalWidth(),
                   title,
                   1,
                   fgDefault,
                   bgBlue)
  tui.tiles[tui.focusIndex].focus()

proc writeInfoBar*(tui: Tui, info: string) =
  writeLeftAligned((0, terminalHeight() - 2),
                   terminalWidth(),
                   info,
                   1,
                   fgDefault,
                   bgBlue)
  tui.tiles[tui.focusIndex].focus()

proc focusNext*(tui: Tui) =
  tui.tiles[tui.focusIndex].unfocus()
  tui.focusIndex = (tui.focusIndex + 1) mod tui.tiles.len()
  tui.writeInfoBar(tui.tiles[tui.focusIndex].help)
  tui.tiles[tui.focusIndex].focus()

proc processInput*(tui: Tui, ch: char) =
  tui.tiles[tui.focusIndex].processInput(ch)

proc initTui*(): Tui =
  let inputTile = newInputTile()
  let conversationTile = newConversationTile()
  let participantsTile = newParticipantsTile()
  result = Tui(inputTile: inputTile,
               conversationTile: conversationTile,
               participantsTile: participantsTile,
               tiles: @[inputTile, conversationTile, participantsTile],
               focusIndex: 0)
  result.writeTitleBar("Untitled channel")
  result.writeInfoBar(inputTile.help)

proc clean*(tui: Tui) =
  showCursor()

# asyncGetch
proc asyncGetch*(): Future[char] =
  let event = newAsyncEvent()
  let future = newFuture[char]("asyncGetch")
  proc getchBackground(event: AsyncEvent): char =
    result = getch()
    event.trigger()
  let flowVar = spawn getchBackground(event)
  proc callback(fd: AsyncFD): bool =
    future.complete(^flowVar)
    event.close()
    true
  addEvent(event, callback)
  return future
