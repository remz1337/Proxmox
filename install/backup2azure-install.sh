#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# Co-Author: remz1337
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

source /dev/stdin <<< "$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies"
$STD apt-get install -y curl
$STD apt-get install -y sudo
$STD apt-get install -y mc
msg_ok "Installed Dependencies"

RELEASE=$(curl -s https://api.github.com/repos/remz1337/Backup2Azure/releases/latest |
  grep "tag_name" |
  awk '{print substr($2, 2, length($2)-3) }')

msg_info "Downloading Backup2Azure ${RELEASE}"
mkdir -p /opt/Backup2Azure
cd /tmp
curl -o Backup2Azure.tar.gz -fsSLO https://api.github.com/repos/remz1337/Backup2Azure/tarball/$RELEASE
tar -xzf Backup2Azure.tar.gz -C /opt/Backup2Azure/ --strip-components 1
rm Backup2Azure.tar.gz
cd -
msg_ok "Downloaded Backup2Azure ${RELEASE}"

msg_info "Installing Backup2Azure ${RELEASE}"
cd /opt/Backup2Azure
$STD bash install_deps.sh
$STD bash install.sh
msg_ok "Installed Backup2Azure ${RELEASE}"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

echo -e "Update configuration in ${BL}/etc/Backup2Azure/backup2azure.conf${CL}"
