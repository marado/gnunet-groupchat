import gnunet_nim, gnunet_nim/cadet, message, tui, asyncdispatch, options,
       times, os, parseopt, terminal, threadpool, sequtils

type Chat* = ref object
  channels*: seq[ref CadetChannel]

proc newChat*(): Chat =
  Chat(channels: newSeq[ref CadetChannel]())

proc publish*(chat: Chat, message: Message) =
  for c in chat.channels:
    c.sendMessage($message)

proc processClientMessages(channel: ref CadetChannel,
                           chat: Chat) {.async.} =
  while true:
    let (hasData, message) = await channel.messages.read()
    if not hasData:
      break
    let parsed = parse(message)
    if parsed.isSome():
      let parsed = parsed.get()
      if parsed.kind == Talk and parsed.sender == channel.peer.peerId():
        chat.publish(parsed)

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
                    parsed.timestamp.fromUnix().local().getClockStr()
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

proc processInput(channel: ref CadetChannel, tui: Tui) {.async.} =
  while true:
    let ch = await asyncGetch()
    case ch:
    of '\r': # Return
      if tui.inputTile.focussed:
        let message = Message(kind: Talk,
                              timestamp: getTime().toUnix(),
                              sender: channel.peer.peerId(),
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
               port: string) {.async.} =
  let cadet = await gnunetApp.initCadet()
  if server != "":
    let channel = cadet.createChannel(server, port)
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
      chat.channels.add(channel)
      let participants =
        chat.channels.map(proc(c: ref CadetChannel): string = c.peer.peerId())
      channel.sendMessage($Message(kind: Info,
                                   timestamp: getTime().toUnix(),
                                   participants: participants))
      closureScope:
        let channel = channel
        let peerId = peerId
        proc channelDisconnected(future: Future[void]) =
          chat.publish(Message(kind: Leave,
                               timestamp: getTime().toUnix(),
                               who: peerId))
          chat.channels.delete(chat.channels.find(channel))
        processClientMessages(channel, chat).addCallback(channelDisconnected)

proc main() =
  var home = getEnv ("HOME")
  var server, port, configfile: string
  var optParser = initOptParser()

  for kind, key, value in optParser.getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "config", "c": configfile = value
      of "server", "s": server = value
      of "port", "p": port = value
    else:
      assert(false)

  # Check for existing config
  if not (fileExists (configfile)):
    if fileExists (home & "/.config/gnunet.conf"):
      configfile = home & "/.config/gnunet.conf"
    elif fileExists ("/etc/gnunet.conf"):
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
