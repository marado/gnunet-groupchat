##     This file is part of GNUnet.
##     Copyright (C) 2001 - 2019 GNUnet e.V.
##
##     GNUnet is free software: you can redistribute it and/or modify it
##     under the terms of the GNU Affero General Public License as published
##     by the Free Software Foundation, either version 3 of the License,
##     or (at your option) any later version.
##
##     GNUnet is distributed in the hope that it will be useful, but
##     WITHOUT ANY WARRANTY; without even the implied warranty of
##     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
##     Affero General Public License for more details.
##
##     You should have received a copy of the GNU Affero General Public License
##     along with this program.  If not, see <http://www.gnu.org/licenses/>.
##
##     SPDX-License-Identifier: AGPL3.0-or-later

##  @author lurchi
##  @file groupchat.nim
##  @brief groupchat server and client 


import gnunet_nim
import gnunet_nim/cadet
import tui
import message
import os
import parseopt
import tables
import asyncdispatch
import options
import times
import sequtils
import strutils

type Client = object
  ## Handle for client using cadet 
  channel*: ref CadetChannel
  nick*: string

type Chat = ref object
  ## Handle for chat 
  clients*: Table[string, Client]

proc newChat*(): Chat =
  ## Create a new chat. 
  Chat(clients: initTable[string, Client]())

proc publish*(chat: Chat, message: Message) =
  ## Publish a message in a chat.
  for c in chat.clients.values():
    if c.nick != "":
      c.channel.sendMessage($message)

proc processClientMessages(channel: ref CadetChannel,
                           chat: Chat) {.async.} =
  # Small event loop for incomming messages
  while true:
    let (hasData, message) = await channel.messages.read()
    if not hasData:
      break
    let parsed = parse(message)
    if parsed.isSome():
      echo(getTime().toUnix(), ": message from ", channel.peer.peerId(), ": ", message)
      let parsed = parsed.get()
      let peerId = channel.peer.peerId()
      case parsed.kind
      of Talk:
        let client = chat.clients[peerId]
        if client.nick != "":
          parsed.sender = client.nick
          chat.publish(parsed)
      of Join:
        var client = chat.clients[peerId]
        if client.nick == "":
          if parsed.who != "":
            client.nick = parsed.who
          else:
            client.nick = peerId
          chat.publish(Message(kind: Join,
                               timestamp: getTime().toUnix(),
                               who: client.nick))
          chat.clients[peerId] = client
          let clients = toSeq(chat.clients.values())
          let participants = clients.map(proc(c: Client): string = c.nick)
          channel.sendMessage($Message(kind: Info,
                                       timestamp: getTime().toUnix(),
                                       participants: participants))
      else:
        discard
    else:
      echo(getTime().toUnix(), ": invalid message from ", channel.peer.peerId())

proc processServerMessages(channel: ref CadetChannel, tui: Tui, nick: string) {.async.} =
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
        if find(parsed.content, nick) != -1:
          discard execShellCmd("echo -en '\a'");
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
    var message = Message(kind: Join,
                          timestamp: getTime().toUnix())
    if nick != "":
      message.who = nick
    channel.sendMessage($message)
    let tui = initTui()
    await processServerMessages(channel, tui, nick) or processInput(channel, tui)
    tui.clean()
  else:
    var chat = newChat()
    let cadetPort = cadet.openPort(port)
    while true:
      let (hasChannel, channel) = await cadetPort.channels.read()
      if not hasChannel:
        break
      let peerId = channel.peer.peerId()
      chat.clients[peerId] = Client(channel: channel)
      echo(getTime().toUnix(), ": ", peerId, " connected")
      closureScope:
        let channel = channel
        let peerId = peerId
        proc channelDisconnected(future: Future[void]) =
          var client: Client
          discard chat.clients.take(peerId, client)
          if client.nick != "":
            chat.publish(Message(kind: Leave,
                                 timestamp: getTime().toUnix(),
                                 who: client.nick))
          echo(getTime().toUnix(), ": ", peerId, " disconnected")
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
