################
GNUnet Groupchat
################

This is a simple client-server chat system, using CADET.

Installation
============

Requirements
------------

* GNUnet >= 0.11.0 (https://gnunet.org)
* Nim >= 0.18.0    (https://nim-lang.org)

Install
-------

`git submodule sync && git submodule update --init --recursive`
`make`

Running
=======

Server
------
`./groupchat --config:<PATH-TO-GNUNET-CONFIG> --port:<SHARED-SECRET-STRING>`

EXAMPLE:
`./groupchat --config:~/.config/gnunet.conf --port:welcome`

(Server will need to share its Peer-ID with clients. You can find your Peer-ID by running `gnunet-peerinfo -s`)

Client
------
`./groupchat --config:<PATH-TO-GNUNET-CONFIG> --server:<SERVER'S-PEER-ID> --port:<SHARED-SECRET-STRING>`

EXAMPLE:
`./groupchat --config:~/.config/gnunet.conf --server:P4T5GHS1PCZ06R82D3KW8Z8J1113BQZWAWGYHTZ8G1ZXMWXQGAVG --port:welcome`
