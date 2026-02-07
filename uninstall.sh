#!/bin/bash
PATH=/www/server/panel/pyenv/bin:/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

pluginPath='/www/server/panel/plugin/ssh_authlog'

# keep same behavior as panel plugins: uninstall via install.sh else branch
if [ -f "$pluginPath/install.sh" ]; then
	bash "$pluginPath/install.sh" uninstall
else
	# fallback
	rm -f /www/server/panel/BTPanel/static/img/soft_ico/ico-ssh_authlog.png 2>/dev/null || true
	rm -rf "$pluginPath"
	echo 'Successify'
fi
