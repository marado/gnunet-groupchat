# Package

version       = "0.1.0"
author        = "secushare"
description   = "A chat application using GNUnet"
license       = "GPL-3.0"
srcDir        = "src"
bin           = @["groupchat","groupchat_nimbox"]



# Dependencies

requires "nim >= 0.19.0"
requires "gnunet_nim >= 0.1.0"
requires "nimbox"
