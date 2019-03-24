all:
	git submodule sync
	git submodule update --init --recursive
	git submodule foreach --recursive git pull origin master
	cd gnunet_nim; nimble -y install
	nim c groupchat
