#!/usr/bin/env bash
# This is part of devcontainers-contrib script library
# source: https://github.com/devcontainers-contrib/features
set -e
set -x

PLUGIN=${PLUGIN:-""}
VERSION=${VERSION:-"latest"}
PLUGINREPO=${PLUGINREPO:-""}

# Clean up
rm -rf /var/lib/apt/lists/*

if [ -z "$PLUGIN" ]; then
	echo -e "'plugin' variable is empty, skipping"
	exit 0
fi

if [ "$(id -u)" -ne 0 ]; then
	echo -e 'Script must be run as
    root. Use sudo, su, or add "USER root" to your Dockerfile before running this script.'
	exit 1
fi

check_alpine_packages() {
    apk add -v --no-cache "$@"
}

check_packages() {
	if ! dpkg -s "$@" >/dev/null 2>&1; then
		if [ "$(find /var/lib/apt/lists/* | wc -l)" = "0" ]; then
			echo "Running apt-get update..."
			apt-get update -y
		fi
		apt-get -y install --no-install-recommends "$@"
	fi
}

updaterc() {
	if cat /etc/os-release | grep "ID_LIKE=.*alpine.*\|ID=.*alpine.*" ; then
		echo "Updating /etc/profile"
		echo -e "$1" >>/etc/profile
	fi
	if [[ "$(cat /etc/bash.bashrc)" != *"$1"* ]]; then
		echo "Updating /etc/bash.bashrc"
		echo -e "$1" >>/etc/bash.bashrc
	fi
	if [ -f "/etc/zsh/zshrc" ] && [[ "$(cat /etc/zsh/zshrc)" != *"$1"* ]]; then
		echo "Updating /etc/zsh/zshrc"
		echo -e "$1" >>/etc/zsh/zshrc
	fi
}

install_via_asdf() {
	PLUGIN=$1
	VERSION=$2
	REPO=$3

	# install git and curl if does not exists
	if cat /etc/os-release | grep "ID_LIKE=.*alpine.*\|ID=.*alpine.*" ; then
        check_alpine_packages curl git ca-certificates
	elif cat /etc/os-release | grep  "ID_LIKE=.*debian.*\|ID=.*debian.*"; then
		check_packages curl git ca-certificates
	fi

	# asdf may be installed somewhere on the machine, but we need it to be accessible to the remote user
	# the code bellow will return 2 only when asdf is available, and 1 otherwise
	set +e
	su - "$_REMOTE_USER" <<EOF
		if type asdf >/dev/null 2>&1; then
			exit 2
		fi
		exit 1
EOF
	exit_code=$?
	set -e

	if [ "${exit_code}" -eq 2 ]; then
		# asdf already available to remote user, use it
		su - "$_REMOTE_USER" <<EOF

			if asdf list "$PLUGIN" >/dev/null 2>&1; then
				echo "$PLUGIN  already exists - skipping installation"
				exit 0
			fi
			asdf plugin add "$PLUGIN" "$REPO"
			asdf install "$PLUGIN" "$VERSION"
			asdf global "$PLUGIN" "$VERSION"
EOF
	else
		# asdf is not available to remote user, install it, then update rc files

		su - "$_REMOTE_USER" <<EOF
			git clone --depth=1 \
				-c core.eol=lf \
				-c core.autocrlf=false \
				-c fsck.zeroPaddedFilemode=ignore \
				-c fetch.fsck.zeroPaddedFilemode=ignore \
				-c receive.fsck.zeroPaddedFilemode=ignore \
				"https://github.com/asdf-vm/asdf.git" $_REMOTE_USER_HOME/.asdf 2>&1
			
			. $_REMOTE_USER_HOME/.asdf/asdf.sh
			if asdf list "$PLUGIN" >/dev/null 2>&1; then
				echo "$PLUGIN  already exists - skipping installation"
				exit 0
			fi
			asdf plugin add "$PLUGIN" "$REPO"
			asdf install "$PLUGIN" "$VERSION"
			asdf global "$PLUGIN" "$VERSION"
EOF
		updaterc ". $_REMOTE_USER_HOME/.asdf/asdf.sh"
	fi 
}

install_via_asdf "$PLUGIN" "$VERSION" "$PLUGINREPO"
