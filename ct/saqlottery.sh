#!/usr/bin/env bash
source <(curl -s https://raw.githubusercontent.com/remz1337/Proxmox/remz/misc/build.func)
# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# Co-Author: remz1337
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

function header_info {
clear
cat <<"EOF"
   _____ ___   ____    __          __  __                 
  / ___//   | / __ \  / /   ____  / /_/ /____  _______  __
  \__ \/ /| |/ / / / / /   / __ \/ __/ __/ _ \/ ___/ / / /
 ___/ / ___ / /_/ / / /___/ /_/ / /_/ /_/  __/ /  / /_/ / 
/____/_/  |_\___\_\/_____/\____/\__/\__/\___/_/   \__, /  
                                                 /____/   
EOF
}
header_info
echo -e "Loading..."
APP="SAQLottery"
var_disk="2"
var_cpu="1"
var_ram="128"
var_os="debian"
var_version="12"
variables
color
catch_errors

function default_settings() {
  CT_TYPE="1"
  PW=""
  CT_ID=$NEXTID
  HN=$NSAPP
  DISK_SIZE="$var_disk"
  CORE_COUNT="$var_cpu"
  RAM_SIZE="$var_ram"
  BRG="vmbr0"
  NET="dhcp"
  GATE=""
  APT_CACHER=""
  APT_CACHER_IP=""
  DISABLEIP6="no"
  MTU=""
  SD=""
  NS=""
  MAC=""
  VLAN=""
  SSH="no"
  VERB="no"
  echo_default
}

function update_script() {
  header_info
  if [[ ! -f /etc/systemd/system/saqlottery.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  RELEASE=$(curl -s https://api.github.com/repos/remz1337/SAQLottery/releases/latest |
    grep "tag_name" |
    awk '{print substr($2, 2, length($2)-3) }')
  cd /tmp
  curl -o SAQLottery.tar.gz -fsSLO https://api.github.com/repos/remz1337/SAQLottery/tarball/$RELEASE
  tar -xzf SAQLottery.tar.gz -C /opt/SAQLottery/ --strip-components 1
  rm SAQLottery.tar.gz
  msg_ok "Updated $APP LXC"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"