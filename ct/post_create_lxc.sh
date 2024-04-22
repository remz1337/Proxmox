#!/usr/bin/env bash

# Author: remz1337
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

# This function sets up the Container OS by generating the locale, setting the timezone, and checking the network connection
default_setup() {
  msg_info "Setting up Container"
  pct exec $CTID -- /bin/bash -c "apt update -qq &>/dev/null"
  pct exec $CTID -- /bin/bash -c "apt install -qqy curl &>/dev/null"
  lxc-attach -n "$CTID" -- bash -c "source <(curl -s https://raw.githubusercontent.com/remz1337/Proxmox/remz/misc/install.func) && color && verb_ip6 && catch_errors && setting_up_container && network_check && update_os" || exit
  msg_ok "Set up Container"
}

reboot_lxc(){
  msg_info "Rebooting LXC to mount shared directory"
  pct reboot $CTID
  sleep 1
  msg_ok "Rebooted LXC to mount shared directory"
}

# This function checks if a given username exists
function user_exists(){
  pct exec $CTID -- /bin/bash -c "id $1 &>/dev/null;"
} # silent, it just sets the exit code

echo -e "${BL}Customizing LXC creation${CL}"

# Test if required variables are set
[[ "${CTID:-}" ]] || exit "You need to set 'CTID' variable."
[[ "${PCT_OSTYPE:-}" ]] || exit "You need to set 'PCT_OSTYPE' variable."
[[ "${PCT_OSVERSION:-}" ]] || exit "You need to set 'PCT_OSVERSION' variable."
[[ "${app:-}" ]] || exit "You need to set 'app' variable."
[[ "${PHS_ADD_SSH_USER:-}" ]] || exit "You need to set 'PHS_ADD_SSH_USER' variable."
[[ "${PHS_SHARED_MOUNT:-}" ]] || exit "You need to set 'PHS_SHARED_MOUNT' variable."
[[ "${PHS_POSTFIX_SAT:-}" ]] || exit "You need to set 'PHS_POSTFIX_SAT' variable."
[[ "${NVIDIA_PASSTHROUGH:-}" ]] || exit "You need to set 'NVIDIA_PASSTHROUGH' variable."


#Call default setup to have local, timezone and update APT
default_setup

#Install APT proxy client
msg_info "Installing APT proxy client"
if [ "$PCT_OSTYPE" == "debian" ] && [ "$PCT_OSVERSION" == "12" ]; then
  #Squid-deb-proxy-client is not available on Deb12, not sure if it's an issue with using PVE7
  #auto-apt-proxy needs a DNS record "apt-proxy" pointing to AptCacherNg machine IP (I did it using PiHole)
  pct exec $CTID -- /bin/bash -c "apt install -qqy auto-apt-proxy &>/dev/null"
else
  pct exec $CTID -- /bin/bash -c "apt install -qqy squid-deb-proxy-client &>/dev/null"
fi
msg_ok "Installed APT proxy client"

#Install sudo if Debian
if [ "$PCT_OSTYPE" == "debian" ]; then
  msg_info "Installing sudo"
  pct exec $CTID -- /bin/bash -c "apt install -yqq sudo &>/dev/null"
  msg_ok "Installed sudo"
fi

if [[ "${PHS_ADD_SSH_USER}" == "yes" ]]; then
  #Add ssh sudo user SSH_USER
  msg_info "Adding SSH user $SSH_USER (sudo)"
  if user_exists "$SSH_USER"; then
    msg_error 'User $SSH_USER already exists.'
  else
    pct exec $CTID -- /bin/bash -c "adduser $SSH_USER --disabled-password --gecos '' --uid 1000 &>/dev/null"
    pct exec $CTID -- /bin/bash -c "echo '$SSH_USER:$SSH_PASSWORD' | chpasswd --encrypted"
    pct exec $CTID -- /bin/bash -c "usermod -aG sudo $SSH_USER"
  fi
  msg_ok "Added SSH user $SSH_USER (sudo)"
fi

if [[ "${PHS_SHARED_MOUNT}" == "yes" ]]; then
  msg_info "Mounting shared directory"
  #Add user $SHARE_USER
  if user_exists "$SHARE_USER"; then
    msg_error 'User $SHARE_USER already exists.'
  else
    pct exec $CTID -- /bin/bash -c "adduser $SHARE_USER --disabled-password --no-create-home --gecos '' --uid 1001 &>/dev/null"
    # Add mount point and user mapping
    # This assumes that we have a "share" drive mounted on host with directory 'public' (/mnt/pve/share/public) AND that $SHARE_USER user (and group) has been added on host with appropriate access to the "public" directory
    cat <<EOF >>/etc/pve/lxc/${CTID}.conf
mp0: /mnt/pve/share/public,mp=/mnt/pve/share
lxc.idmap: u 0 100000 1001
lxc.idmap: g 0 100000 1001
lxc.idmap: u 1001 1001 1
lxc.idmap: g 1001 1001 1
lxc.idmap: u 1002 101002 64534
lxc.idmap: g 1002 101002 64534
EOF
  fi
  msg_ok "Mounted shared directory"

  reboot_lxc
fi

if [[ "${PHS_POSTFIX_SAT}" == "yes" ]]; then
  msg_info "Configuring Postfix Satellite"
  #Install deb-conf-utils to set parameters
  pct exec $CTID -- /bin/bash -c "apt install -qqy debconf-utils &>/dev/null"
  pct exec $CTID -- /bin/bash -c "systemctl stop postfix"
  pct exec $CTID -- /bin/bash -c "mv /etc/postfix/main.cf /etc/postfix/main.cf.BAK"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/main_mailer_type        select  Satellite system | debconf-set-selections"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/destinations    string  $app.localdomain, localhost.localdomain, localhost | debconf-set-selections"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/mailname        string  $app.$DOMAIN | debconf-set-selections"
  #This config assumes that the postfix relay host is already set up in another LXC with hostname "postfix" (using port 255)
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/relayhost       string  [postfix.$DOMAIN]:255 | debconf-set-selections"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/mynetworks      string  127.0.0.0/8 | debconf-set-selections"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/mailbox_limit      string  0 | debconf-set-selections"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/protocols      select  all | debconf-set-selections"
  pct exec $CTID -- /bin/bash -c "dpkg-reconfigure debconf -f noninteractive &>/dev/null"
  pct exec $CTID -- /bin/bash -c "dpkg-reconfigure postfix -f noninteractive &>/dev/null"
  pct exec $CTID -- /bin/bash -c "postconf 'smtp_tls_security_level = encrypt'"
  pct exec $CTID -- /bin/bash -c "postconf 'smtp_tls_wrappermode = yes'"
  pct exec $CTID -- /bin/bash -c "systemctl restart postfix"
  msg_ok "Configured Postfix Satellite"
fi

if [[ "${NVIDIA_PASSTHROUGH}" == "yes" ]]; then
  msg_info "Installing Nvidia Drivers"

  if [ "$NVIDIA_PASSTHROUGH" == "yes" ]; then
    source <(curl -s https://raw.githubusercontent.com/remz1337/Proxmox/remz/misc/nvidia.func)
    check_nvidia_drivers
    gpu_id=$(select_nvidia_gpu)
    gpu_lxc_passthrough $gpu_id
	reboot_lxc
  fi

  if [ -z $NVD_VER ]; then
    echo "No Nvidia drivers detected on host."
    exit-script
  fi

  #DRIVER_VERSION="550.67"
  EXE_FILE="NVIDIA-Linux-x86_64-${NVD_VER}.run"
  DOWNLOAD_URL="https://us.download.nvidia.com/XFree86/Linux-x86_64/${NVD_VER}/${EXE_FILE}"

  pct exec $CTID -- /bin/bash -c "rm NVIDIA-Linux-x86_64-*.run"
  pct exec $CTID -- /bin/bash -c "wget $DOWNLOAD_URL"
  pct exec $CTID -- /bin/bash -c "apt install -qqy libglvnd-dev libvulkan1 pkg-config &>/dev/null"
  pct exec $CTID -- /bin/bash -c "bash $EXE_FILE --no-kernel-module --silent"
  pct exec $CTID -- /bin/bash -c "rm NVIDIA-Linux-x86_64-*.run"
  msg_ok "Installed Nvidia Drivers"
fi

msg_ok "Post install script completed."