all:
	cd gnunet_nim; nimble -y install
	nim c groupchat
