#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# Co-Author: remz1337
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

function header_info() {
  clear
  cat <<"EOF"
    _   __      _     ___          ____       _                     
   / | / /   __(_)___/ (_)___ _   / __ \_____(_)   _____  __________
  /  |/ / | / / / __  / / __ `/  / / / / ___/ / | / / _ \/ ___/ ___/
 / /|  /| |/ / / /_/ / / /_/ /  / /_/ / /  / /| |/ /  __/ /  (__  ) 
/_/ |_/ |___/_/\__,_/_/\__,_/  /_____/_/  /_/ |___/\___/_/  /____/  
                                                                    
EOF
}
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
CM='\xE2\x9C\x94\033'
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
header_info
echo "Loading..."

#Make sure host as appropriate dependencies
apt install -y dkms pve-headers wget

#Clean up old files
rm NVIDIA-Linux-x86_64-*.run

DRIVER_VERSION="550.67"
EXE_FILE="NVIDIA-Linux-x86_64-$DRIVER_VERSION.run"
DOWNLOAD_URL="https://us.download.nvidia.com/XFree86/Linux-x86_64/$DRIVER_VERSION/$EXE_FILE"

wget -q $DOWNLOAD_URL

#Dependencies for OpenGL/Vulkan
apt install -y libglvnd-dev libvulkan1 pkg-config

bash "$EXE_FILE" --dkms

#echo "Installation of NVIDIA drivers complete"

#Clean up install file to avoid backing it up
rm NVIDIA-Linux-x86_64-*.run

wait
header_info
echo -e "${GN} Finished, Nvidia drivers installed.${CL}\n"
