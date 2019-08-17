import gnunet_nim, gnunet_nim/cadet, message, tui, asyncdispatch, options,
       times, os, parseopt, sequtils

type Client = object
  channel*: ref CadetChannel
  nick*: string

type Chat = ref object
  clients*: seq[Client]

proc newChat*(): Chat =
  Chat(clients: newSeq[Client]())

proc publish*(chat: Chat, message: Message) =
  for c in chat.clients:
    c.channel.sendMessage($message)

proc processClientMessages(channel: ref CadetChannel,
                           chat: Chat) {.async.} =
  while true:
    let (hasData, message) = await channel.messages.read()
    if not hasData:
      break
    let parsed = parse(message)
    if parsed.isSome():
      echo(getTime().toUnix(), ": message from ", channel.peer.peerId(), ": ", message)
      let parsed = parsed.get()
      case parsed.kind
      of Talk:
        proc pred(c: Client): bool = c.channel == channel
        parsed.sender = chat.clients.filter(pred)[0].nick
        chat.publish(parsed)
      of Nick:
        chat.clients.add(Client(channel: channel, nick: parsed.nick))
      else:
        discard
    else:
      echo(getTime().toUnix(), ": invalid message from ", channel.peer.peerId())

proc processServerMessages(channel: ref CadetChannel, tui: Tui) {.async.} =
  while true:
    let (hasData, message) = await channel.messages.read()
    if not hasData:
      shutdownGnunetApplication()
      return
    let parsed = parse(message)
    if parsed.isSome():
      let parsed = parsed.get()
      case parsed.kind
      of Talk:
        let title = parsed.sender &
                    " " &
                    parsed.timestamp.fromUnix().local().format("HH:mm:ss")
        tui.conversationTile.addElement("", title, parsed.content)
        tui.inputTile.present()
      of Join:
        tui.participantsTile.addElement(parsed.who,
                                        parsed.who)
        tui.inputTile.present()
      of Leave:
        tui.participantsTile.deleteElement(parsed.who)
        tui.inputTile.present()
      of Info:
        for p in parsed.participants:
          tui.participantsTile.addElement(p, p)
        tui.inputTile.present()
      else:
        discard

proc processInput(channel: ref CadetChannel, tui: Tui) {.async.} =
  while true:
    let ch = await asyncGetch()
    case ch:
    of '\r': # Return
      if tui.inputTile.focussed:
        let message = Message(kind: Talk,
                              timestamp: getTime().toUnix(),
                              sender: "", # FIXME: get our peerID from Transport API
                              content: tui.inputTile.input)
        channel.sendMessage($message)
        tui.inputTile.reset()
    of '\x03': # Ctrl-C
      break
    of '\t': # Tab
      tui.focusNext()
    of '\x13': # Ctrl-s
      tui.writeInfoBar("select channel not implemented")
    of '\x0e': # Ctrl-n
      tui.writeInfoBar("new channel not implemented")
    of '\x05': # Ctrl-e
      tui.writeInfoBar("edit title not implemented")
    else:
      tui.processInput(ch)
  shutdownGnunetApplication()

proc firstTask(gnunetApp: ref GnunetApplication,
               server: string,
               port: string,
               nick: string) {.async.} =
  let cadet = await gnunetApp.initCadet()
  if server != "":
    let channel = cadet.createChannel(server, port)
    if nick != "":
      channel.sendMessage($Message(kind: Nick,
                                   timestamp: getTime().toUnix(),
                                   nick: nick))
    let tui = initTui()
    await processServerMessages(channel, tui) or processInput(channel, tui)
    tui.clean()
  else:
    var chat = newChat()
    let cadetPort = cadet.openPort(port)
    while true:
      let (hasChannel, channel) = await cadetPort.channels.read()
      if not hasChannel:
        break
      let peerId = channel.peer.peerId()
      chat.publish(Message(kind: Join,
                           timestamp: getTime().toUnix(),
                           who: peerId))
      chat.clients.add(Client(channel: channel, nick: channel.peer.peerId()))
      let participants =
        chat.clients.map(proc(c: Client): string = c.channel.peer.peerId())
      channel.sendMessage($Message(kind: Info,
                                   timestamp: getTime().toUnix(),
                                   participants: participants))
      echo(getTime().toUnix(), ": ", peerId, " joined")
      closureScope:
        let channel = channel
        let peerId = peerId
        proc channelDisconnected(future: Future[void]) =
          chat.publish(Message(kind: Leave,
                               timestamp: getTime().toUnix(),
                               who: peerId))
          chat.clients.keepIf(proc(c: Client): bool = c.channel != channel)
          echo(getTime().toUnix(), ": ", peerId, " left")
        processClientMessages(channel, chat).addCallback(channelDisconnected)

proc main() =
  var home = getEnv("HOME")
  var server, port, nick, configfile: string
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
  asyncCheck firstTask(gnunetApp, server, port, nick)
  
  # Event loop
  while gnunetApp.isAlive():
    poll(gnunetApp.millisecondsUntilTimeout())
    gnunetApp.doWork()
    stdout.flushFile()

  echo "quitting"
  stdout.flushFile()
  stdin.flushFile()

when isMainModule:
  main()
