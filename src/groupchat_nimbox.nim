import gnunet_nim
import gnunet_nim/cadet
import threadpool, nimbox, asyncdispatch, asyncfile, parseopt, strutils, sequtils, times, os, deques, events

type SharedChannel[T] = ptr Channel[T]

type ChannelValue = object
  stop: bool
  message: string

var nick: string

type Chat = object
  channels: seq[ref CadetChannel]

var nb: NimBox

proc newSharedChannel[T](): SharedChannel[T] =
  result = cast[SharedChannel[T]](allocShared0(sizeof(Channel[T])))
  open(result[])

proc close[T](ch: var SharedChannel[T]) =
  close(ch[])
  deallocShared(ch)
  ch = nil

proc send[T](ch: SharedChannel[T], content: T) =
  ch[].send(content)


proc recv[T](ch: SharedChannel[T]): T =
  result = ch[].recv

proc available[T](ch: SharedChannel[T]): bool =
  result = ch[].peek > 0

proc modsContainsCrtl(mods: seq[Modifier]): bool =
  for modifier in mods:
    if (modifier == Modifier.Ctrl):
      return true
  return false

proc getInputLine(nb: NimBox): ChannelValue  =
  var line, str, clear = ""
  nb.print(0,2, "-------------------------> ")
  nb.cursor = (27, 2)
  nb.present()
  var channelValue: ChannelValue
  channelValue.stop = false
  while true:
    let evt = nb.peekEvent(1000)
    case evt.kind:
      of EventType.Key:
        if evt.sym == Symbol.Enter:
          nb.print(27, 2, clear)
          #future.complete(line)
          #line = ""
          #str = ""
          #clear = ""
          nb.present()
          break
          #i=i+1
        elif  evt.sym != Symbol.Backspace and modsContainsCrtl(evt.mods):
          channelValue.stop = true
          break
        else:
          var ch : char = evt.ch
          if evt.sym == Symbol.Space:
            ch = cast[char](' ')
          if evt.sym == Symbol.Backspace:
               line.delete(line.len(),line.len())
               str.delete(str.len(), str.len())
               nb.print(27, 2, clear)
          else:
            line.add(ch)
            str.add(ch)
          nb.cursor = (27+str.len, 2)
          clear.add(" ")
          nb.print(0,2, "-------------------------> "&str)
          #if i == 10:
              #i = 0
          nb.present()
      else: discard
  #return future
  channelValue.message = line
  return channelValue

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

proc processServerMessages(channel: ref CadetChannel) {.async.} =
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
    #nb.print(0, 2, getDateStr()&" "&getClockStr()&" "&message)
    nb.present()

proc processInput(ev: AsyncEvent, ch: SharedChannel[ChannelValue]) =
  #while true:
  let channelValue = getInputLine(nb)
  ch.send(channelValue)
  ev.trigger()

proc asyncReadFromChannel(ch: SharedChannel[ChannelValue], cb: proc(channelValue: ChannelValue)) =
  var event = newAsyncEvent()
  proc eventCallback(fd: AsyncFd): bool =
    cb(ch.recv())
    true
  addEvent(event, eventCallback)
  spawn processInput(event, ch)

proc readFromChannel(ch: SharedChannel[ChannelValue]): Future[ChannelValue] =
  let future = newFuture[ChannelValue]("readFromChannel")
  proc callback(channelValue: ChannelValue) =
    future.complete(channelValue)
  asyncReadFromChannel(ch, callback)
  return future


proc processInputMessages(channel: ref CadetChannel, ch: SharedChannel[ChannelValue]) {.async.} =
  while true:
    let channelValue = await readFromChannel(ch)
    if (channelValue.stop):
      return
    if nick == "":
      channel.sendMessage(channelValue.message)
    else:
      channel.sendMessage(nick&": "&channelValue.message)

proc firstTask(gnunetApp: ref GnunetApplication,
               server: string,
               port: string) {.async.} =
  let cadet = await gnunetApp.initCadet()
  var chat = new(Chat)
  chat.channels = newSeq[ref CadetChannel]()
  if server != "":
    nb = newNimbox()
    var inputChannel = newSharedChannel[ChannelValue]()
    let channel = cadet.createChannel(server, port)
    await processServerMessages(channel) or processInputMessages(channel, inputChannel)
    close(inputChannel)
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
  var gnunetApp = initGnunetApplication(configfile)
  asyncCheck firstTask(gnunetApp, server, port)
  while hasPendingOperations():
    poll(gnunetApp.millisecondsUntilTimeout())
    gnunetApp.doWork()

  echo "quitting"

main()
GC_fullCollect()
