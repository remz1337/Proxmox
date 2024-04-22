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
    ____             __              ___   ___                      
   / __ )____ ______/ /____  ______ |__ \ /   |____  __  __________ 
  / __  / __ `/ ___/ //_/ / / / __ \__/ // /| /_  / / / / / ___/ _ \
 / /_/ / /_/ / /__/ ,< / /_/ / /_/ / __// ___ |/ /_/ /_/ / /  /  __/
/_____/\__,_/\___/_/|_|\__,_/ .___/____/_/  |_/___/\__,_/_/   \___/ 
                           /_/                                      

EOF
}
header_info
echo -e "Loading..."
APP="Backup2Azure"
var_disk="4"
var_cpu="1"
var_ram="512"
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
  if [[ ! -f /etc/systemd/system/backup2azure.service ]]; then
    msg_error "No ${APP} Installation Found!"
    exit
  fi
  msg_info "Updating $APP LXC"
  RELEASE=$(curl -s https://api.github.com/repos/remz1337/Backup2Azure/releases/latest |
    grep "tag_name" |
    awk '{print substr($2, 2, length($2)-3) }')
  cd /tmp
  curl -o Backup2Azure.tar.gz -fsSLO https://api.github.com/repos/remz1337/Backup2Azure/tarball/$RELEASE
  tar -xzf Backup2Azure.tar.gz -C /opt/Backup2Azure/ --strip-components 1
  rm Backup2Azure.tar.gz
  msg_ok "Updated $APP LXC"
  exit
}

start
build_container
description

msg_ok "Completed Successfully!\n"