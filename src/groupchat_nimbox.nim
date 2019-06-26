import gnunet_nim
import gnunet_nim/cadet
import
  nimbox, threadpool, asyncdispatch, asyncfile, parseopt, strutils, sequtils,
  times, os, deques, events, options

var nick: string

type Chat = object
  channels: seq[ref CadetChannel]

proc modsContainsCrtl(mods: seq[Modifier]): bool =
  for modifier in mods:
    if (modifier == Modifier.Ctrl):
      return true
  return false

proc processInput(nb: NimBox): Option[string] =
  var line, str, clear = ""
  while true:
    let event = nb.pollEvent()
    if event.kind != EventType.Key:
      continue
    if event.sym == Symbol.Enter:
      nb.print(27, 2, clear)
      nb.present()
      return some(line)
    elif event.sym != Symbol.Backspace and modsContainsCrtl(event.mods):
      return none(string)
    else:
      var ch : char = event.ch
      if event.sym == Symbol.Space:
        ch = cast[char](' ')
      if event.sym == Symbol.Backspace:
           line.delete(line.len(),line.len())
           str.delete(str.len(), str.len())
           nb.print(27, 2, clear)
      else:
        line.add(ch)
        str.add(ch)
      nb.cursor = (27+str.len, 2)
      clear.add(" ")
      nb.print(0,2, "-------------------------> "&str)
      nb.present()

proc asyncReadline(nb: NimBox): Future[string] =
  let readlineEvent = newAsyncEvent()
  let quitEvent = newAsyncEvent()
  let future = newFuture[string]("asyncPeekEvent")
  proc readlineBackground(nb: NimBox,
                          readlineEvent: AsyncEvent,
                          quitEvent: AsyncEvent): string =
    let line = processInput(nb)
    if line.isSome():
      result = line.get()
      readlineEvent.trigger()
    else:
      quitEvent.trigger()
  let flowVar = spawn readlineBackground(nb, readlineEvent, quitEvent)
  proc readlineCallback(fd: AsyncFD): bool =
    future.complete(^flowVar)
    true
  proc quitCallback(fd: AsyncFD): bool =
    future.fail(new(IOError))
    true
  addEvent(readlineEvent, readlineCallback)
  addEvent(quitEvent, quitCallback)
  return future

proc publish(chat: ref Chat, message: string, sender: ref CadetChannel = nil) =
  let message =
    if sender.isNil(): message.strip(leading = false)
    else: "[" & sender.peer.peerId() & "] " & message.strip(leading = false)
  echo getDatestr(), " ", getClockStr(), " ", message
  for c in chat.channels:
    c.sendMessage(message)

proc processClientMessages(channel: ref CadetChannel,
                           chat: ref Chat) {.async.} =
  while true:
    let (hasData, message) = await channel.messages.read()
    if not hasData:
      break
    chat.publish(message = message, sender = channel)

proc processServerMessages(nb: NimBox, channel: ref CadetChannel) {.async.} =
  var messages = initDeque[string]()
  while true:
    let (hasData, message) = await channel.messages.read()
    if not hasData:
      shutdownGnunetApplication()
      return
    nb.clear()
    nb.print(0,2, "-------------------------> ")
    messages.addFirst(getDateStr()&" "&getClockStr()&" "&message)
    for i, value in messages.pairs():
      nb.print(0, i+4, value)
    nb.present()

proc processInput(nb: NimBox, channel: ref CadetChannel) {.async.} =
  while true:
    try:
      let input = await asyncReadline(nb)
      channel.sendMessage(input)
    except IOError:
      break

proc firstTask(gnunetApp: ref GnunetApplication,
               server: string,
               port: string) {.async.} =
  let cadet = await gnunetApp.initCadet()
  var chat = new(Chat)
  chat.channels = newSeq[ref CadetChannel]()
  if server != "":
    let nb = newNimbox()
    let channel = cadet.createChannel(server, port)
    await processServerMessages(nb, channel) or processInput(nb, channel)
    nb.shutdown()
    echo "quitting"
    quit 0
    #inputFile.close()
  else:
    let cadetPort = cadet.openPort(port)
    while true:
      let (hasChannel, channel) = await cadetPort.channels.read()
      if not hasChannel:
        break
      let peerId = channel.peer.peerId()
      chat.publish(message = peerId & " joined\n")
      let listParticipants =
        chat.channels.map(proc(c: ref CadetChannel): string = c.peer.peerId)
      channel.sendMessage("Welcome " & peerId & "! participants: " & $listParticipants)
      chat.channels.add(channel)
      closureScope:
        let channel = channel
        let peerId = peerId
        proc channelDisconnected(future: Future[void]) =
          chat.channels.delete(chat.channels.find(channel))
          chat.publish(message = peerId & " left\n")
        processClientMessages(channel, chat).addCallback(channelDisconnected)

proc main() =
  var server, port, configfile: string
  var home = getEnv("HOME")
  var optParser = initOptParser()
  for kind, key, value in optParser.getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "config", "c": configfile = value
      of "server", "s": server = value
      of "port", "p": port = value
      of "nick", "n": nick = value
    else:
      assert(false)

  # Check for existing config
  if not (fileExists(configfile)):
    if fileExists(home & "/.config/gnunet.conf"):
      configfile = home & "/.config/gnunet.conf"
    elif fileExists("/etc/gnunet.conf"):
      configfile = "/etc/gnunet.conf"
    else:
      echo "I need a config file to use."
      echo "  Add -c=<gnunet.conf>"
      return

  if port == "":
    echo "I need a shared secret port to use."
    echo "  Add -p=<sharedsecret>"
    return

  if server == "":
    echo "Entering server mode."

  var gnunetApp = initGnunetApplication(configfile)
  asyncCheck firstTask(gnunetApp, server, port)
  while gnunetApp.isAlive():
    poll(gnunetApp.millisecondsUntilTimeout())
    gnunetApp.doWork()

  echo "quitting"

main()
GC_fullCollect()
