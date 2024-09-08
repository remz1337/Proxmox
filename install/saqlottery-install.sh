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

RELEASE=$(curl -s https://api.github.com/repos/remz1337/SAQLottery/releases/latest |
  grep "tag_name" |
  awk '{print substr($2, 2, length($2)-3) }')

msg_info "Downloading SAQLottery ${RELEASE}"
mkdir -p /opt/SAQLottery
cd /tmp
curl -o SAQLottery.tar.gz -fsSLO https://api.github.com/repos/remz1337/SAQLottery/tarball/$RELEASE
tar -xzf SAQLottery.tar.gz -C /opt/SAQLottery/ --strip-components 1
rm SAQLottery.tar.gz
cd -
msg_ok "Downloaded SAQLottery ${RELEASE}"

msg_info "Installing SAQLottery ${RELEASE}"
cd /opt/SAQLottery
$STD bash install_deps.sh
$STD bash install.sh
msg_ok "Installed SAQLottery ${RELEASE}"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"
