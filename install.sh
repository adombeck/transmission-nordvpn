#!/bin/bash

set -euo pipefail
set -x

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )"

install -d -m 755 /usr/local/lib/systemd/system
install -m 644 "${DIR}/systemd/transmission-nordvpn.service" /usr/local/lib/systemd/system
install -m 644 "${DIR}/systemd/transmission-proxy.service" /usr/local/lib/systemd/system
install -m 644 "${DIR}/systemd/transmission-proxy.socket" /usr/local/lib/systemd/system

# Ensure that a transmission-nordvpn user exists
if ! id -u transmission-nordvpn >/dev/null 2>&1; then
  useradd --system \
          --no-create-home \
          --user-group \
          --shell /usr/sbin/nologin \
          --home-dir /var/lib/transmission-nordvpn \
          transmission-nordvpn
fi

# Create the transmission-nordvpn data directory
install -d -m 700 --owner=transmission-nordvpn --group=transmission-nordvpn \
  /var/lib/transmission-nordvpn

# Create the transmission-nordvpn config directory. Set the setgid bit
# so that files created in this directory will be owned by the
# transmission-nordvpn group.
install -d -m 2770 --group=transmission-nordvpn /etc/transmission-nordvpn

write_settings() {
  local password

  # Check if the settings.json already exists. If it does, ask the user
  # if they want to overwrite it.
  if [ -f /etc/transmission-nordvpn/settings.json ]; then
    echo "The file /etc/transmission-nordvpn/settings.json already exists."
    read -p "Do you want to overwrite it? [y/N]" -r OVERWRITE
    if [[ ! $OVERWRITE =~ ^[Yy]$ ]]; then
      return
    fi
  fi

  install -m 644 "${DIR}/settings.json" /etc/transmission-nordvpn

  # Generate a random password for the rpc user
  set +o pipefail
  password=$(base64 < /dev/urandom | tr -cd '[:alnum:]' | head -c 32)
  set -o pipefail

  # Store the password so that it can be retrieved later
  echo "${password}" > /etc/transmission-nordvpn/rpc-password
  chown root:root /etc/transmission-nordvpn/rpc-password
  chmod 600 /etc/transmission-nordvpn/rpc-password

  # Replace the rpc-password in the settings.json file
  sed -i "s/{{RPC_PASSWORD}}/${password}/" /etc/transmission-nordvpn/settings.json
}

write_settings

systemctl daemon-reload
