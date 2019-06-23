import gnunet_nim
import gnunet_nim/cadet
import logging

import asyncdispatch, asyncfile, parseopt, strutils, sequtils, times, os

type Chat = object
  channels: seq[ref CadetChannel]

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
  while true:
    let (hasData, message) = await channel.messages.read()
    if not hasData:
      shutdownGnunetApplication()
      return
    echo getDateStr()," ",getClockStr()," ",message

proc processInput(inputFile: AsyncFile, channel: ref CadetChannel) {.async.} =
  let input = await inputFile.readline()
  channel.sendMessage(input)

proc firstTask(gnunetApp: ref GnunetApplication,
               server: string,
               port: string) {.async.} =
  let cadet = await gnunetApp.initCadet()
  var inputFile = openAsync("/dev/stdin", fmRead)
  debug("First Task!")
  var chat = new(Chat)
  chat.channels = newSeq[ref CadetChannel]()
  if server != "":
    debug("Opening stdin")
    debug("Opened")
    let channel = cadet.createChannel(server, port)
    debug("Awaiting IO")
    var messagesFuture = channel.messages.read()
    var inputFuture = inputFile.readline()
    while true:
      var hasData = false
      var message = ""
      debug("Awaiting events")
      await messagesFuture or inputFuture
      if inputFuture.finished():
        debug("Got input")
        channel.sendMessage(inputFuture.read())
        inputFuture = inputFile.readline()
      elif messagesFuture.finished():
        debug("Got message")
        (hasData, message) = messagesFuture.read()
        if hasData:
          chat.publish(message = message, sender = channel)
        messagesFuture = channel.messages.read()
      else:
        debug("Fin")
        break
      debug("While true")
    inputFile.close()
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
  var consoleLog = newConsoleLogger()
  addHandler(consoleLog)
  for kind, key, value in optParser.getopt():
    case kind
    of cmdLongOption, cmdShortOption:
      case key
      of "config", "c": configfile = value
      of "server", "s": server = value
      of "port", "p": port = value
    else:
      assert(false)
  if configfile == "":
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
  while hasPendingOperations():
    debug("Processing OPs")
    poll(gnunetApp.millisecondsUntilTimeout())
    debug("polled, start working")
    gnunetApp.doWork()
    debug("done")
  echo "Quitting."

main()
GC_fullCollect()
