import json, strutils, options

type
  MessageKind* = enum
    Talk,
    Join,
    Leave,
    Info,
    Nick,

  Message* = ref object
    case kind*: MessageKind
    of Talk:
      sender*: string
      content*: string
    of Join, Leave:
      who*: string
    of Info:
      participants*: seq[string]
    of Nick:
      nick*: string
    timestamp*: int64

proc `$`*(message: Message): string =
  var jsonObject = %* { "kind": ($message.kind).toLowerAscii(),
                        "timestamp": message.timestamp }
  case message.kind
  of Talk:
    jsonObject["sender"] = % message.sender
    jsonObject["content"] = % message.content
  of Join, Leave:
    jsonObject["who"] = % message.who
  of Info:
    jsonObject["participants"] = % message.participants
  of Nick:
    jsonObject["nick"] = % message.nick
  $jsonObject

proc parse*(input: string): Option[Message] =
  try:
    some(parseJson(input).to(Message))
  except JsonParsingError, KeyError, JsonKindError:
    none(Message)
