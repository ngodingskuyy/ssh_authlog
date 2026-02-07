#!/bin/bash
PATH=/www/server/panel/pyenv/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

install_tmp='/tmp/bt_install.pl'
pluginPath='/www/server/panel/plugin/ssh_authlog'
icon_src="$pluginPath/icon.png"
icon_dst='/www/server/panel/BTPanel/static/img/soft_ico/ico-ssh_authlog.png'

Install_ssh_authlog(){
	mkdir -p "$pluginPath"

	# basic file checks
	if [ ! -f "$pluginPath/index.html" ] || [ ! -f "$pluginPath/ssh_authlog_main.py" ]; then
		echo "Plugin files missing under $pluginPath" > "$install_tmp"
		exit 1
	fi

	# copy icon if present
	if [ -f "$icon_src" ]; then
		mkdir -p "$(dirname "$icon_dst")"
		\cp -arf "$icon_src" "$icon_dst"
	fi

	# make sure scripts are executable (in case of repair)
	chmod 755 "$pluginPath"/*.sh 2>/dev/null || true

	echo 'Successify' > "$install_tmp"
	echo 'Successify'
}

Uninstall_ssh_authlog(){
	# remove icon if we placed it
	rm -f "$icon_dst" 2>/dev/null || true

	# remove plugin directory
	rm -rf "$pluginPath"

	echo 'Successify' > "$install_tmp"
	echo 'Successify'
}

action=$1
if [ "$action" = "install" ]; then
	Install_ssh_authlog
else
	Uninstall_ssh_authlog
fi
