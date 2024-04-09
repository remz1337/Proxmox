#!/usr/bin/env bash

# Author: remz1337
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

# This sets verbose mode if the global variable is set to "yes"
# if [ "$VERBOSE" == "yes" ]; then set -x; fi

# This function sets color variables for formatting output in the terminal
YW=$(echo "\033[33m")
BL=$(echo "\033[36m")
RD=$(echo "\033[01;31m")
GN=$(echo "\033[1;92m")
CL=$(echo "\033[m")
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
BFR="\\r\\033[K"
HOLD="-"

# This sets error handling options and defines the error_handler function to handle errors
set -Eeuo pipefail
trap 'error_handler $LINENO "$BASH_COMMAND"' ERR

# This function handles errors
function error_handler() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID > /dev/null; then kill $SPINNER_PID > /dev/null; fi
  printf "\e[?25h"
  local exit_code="$?"
  local line_number="$1"
  local command="$2"
  local error_message="${RD}[ERROR]${CL} in line ${RD}$line_number${CL}: exit code ${RD}$exit_code${CL}: while executing command ${YW}$command${CL}"
  echo -e "\n$error_message\n"
}

# This function displays a spinner.
function spinner() {
  printf "\e[?25l"
  spinner="/-\\|/-\\|"
  spin_i=0
  while true; do
    printf "\b%s" "${spinner:spin_i++%${#spinner}:1}"
    sleep 0.1
  done
}

# This function displays an informational message with a yellow color.
function msg_info() {
  local msg="$1"
  echo -ne " ${HOLD} ${YW}${msg}   "
  spinner &
  SPINNER_PID=$!
}

# This function displays a success message with a green color.
function msg_ok() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID > /dev/null; then kill $SPINNER_PID > /dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR} ${CM} ${GN}${msg}${CL}"
}

# This function displays a error message with a red color.
function msg_error() {
  if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID > /dev/null; then kill $SPINNER_PID > /dev/null; fi
  printf "\e[?25h"
  local msg="$1"
  echo -e "${BFR} ${CROSS} ${RD}${msg}${CL}"
}

function parse_config(){
  CONFIG=$(pct config $CTID)
#  while IFS= read -r line || [[ -n $line ]]; do
#    if [[ $line == cores* ]]; then
#      CORES=$(echo $line | cut -d ":" -f 2 | xargs)
#    elif [[ $line == memory* ]]; then
#      MEM=$(echo $line | cut -d ":" -f 2 | xargs)
#    elif [[ $line == hostname* ]]; then
#      HOSTNAME=$(echo $line | cut -d ":" -f 2 | xargs)
#    elif [[ $line == ostype* ]]; then
#      OSTYPE=$(echo $line | cut -d ":" -f 2 | xargs)
#    fi
#  done < <(printf '%s' "$CONFIG")

  OSTYPE=$(echo "$CONFIG" | awk '/^ostype/' | cut -d' ' -f2)
  CORES=$(echo "$CONFIG" | awk '/^cores/' | cut -d' ' -f2)
  MEM=$(echo "$CONFIG" | awk '/^memory/' | cut -d' ' -f2)
  HOSTNAME=$(echo "$CONFIG" | awk '/^hostname/' | cut -d' ' -f2)
}

function user_exists(){
#  pct exec  id "$1" &>/dev/null;
  pct exec $CTID -- /bin/bash -c "id $1 &>/dev/null;"
} # silent, it just sets the exit code


# Test if required variables are set
[[ "${CTID:-}" ]] || exit "You need to set 'CTID' variable."
#[[ "${PCT_OSTYPE:-}" ]] || exit "You need to set 'PCT_OSTYPE' variable."


###### Need function to read/write environment variables (default user/passwords/domain...)
DEFAULT_USER="myuser"
DEFAULT_PASSWORD="mypassword"
SHARE_USER="shareuser"
DOMAIN="mydomain.com"


#CTID=$1

# if [ ${#CTID} -le 0 ]; then
  # echo "You need to pass the LXC/VM ID as the first argument."
  # exit
# else
  # parse_config
  # read -p "Run post install script for $HOSTNAME LXC? [Y/N, Default:Yes] " yn
  # case $yn in
    # [Nn]* ) exit;;
# #    * ) proceed=true;;
  # esac
# fi

parse_config

#Install APT proxy client
msg_info "Installing APT proxy client (squid-deb-proxy-client)"
pct exec $CTID -- /bin/bash -c "apt install -y squid-deb-proxy-client"
msg_ok "Installed APT proxy client (squid-deb-proxy-client)"

#Install sudo if Debian
if [ "$OSTYPE" == "debian" ]; then
  msg_info "Installing sudo"
  pct exec $CTID -- /bin/bash -c "apt install -y sudo"
  msg_ok "Installed sudo"
fi

#Add default sudo user DEFAULT_USER
msg_info "Adding default sudo user $DEFAULT_USER"
if user_exists "$DEFAULT_USER"; then
  msg_error 'User $DEFAULT_USER already exists.'
else
#  echo 'user not found'
  pct exec $CTID -- /bin/bash -c "adduser $DEFAULT_USER --gecos '' --uid 1000"
  pct exec $CTID -- /bin/bash -c "usermod -aG sudo $DEFAULT_USER"
  #echo "Default user added."
fi
msg_ok "Added default sudo user $DEFAULT_USER"


if (whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "Shared Mount" --yesno "Mount shared directory and add $SHARE_USER user?" 10 58); then
  SHARED_MOUNT="yes"
else
  SHARED_MOUNT="no"
fi
echo -e "${DGN}Enable Shared Mount: ${BGN}$SHARED_MOUNT${CL}"


if [[ "${SHARED_MOUNT}" == "yes" ]]; then
  msg_info "Mounting shared directory"
  #Add user $SHARE_USER
  if user_exists "$SHARE_USER"; then
    msg_error 'User $SHARE_USER already exists.'
  else
  #  echo 'user not found'
    pct exec $CTID -- /bin/bash -c "adduser $SHARE_USER --gecos '' --uid 1001"
    echo "User $SHARE_USER added."

    #Shutdown LXC for safety
    #pct shutdown $CTID
    #sleep 3

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

    #pct start $CTID
    #sleep 3
  fi
  msg_info "Mounted shared directory"
fi



if (whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "Configure Postfix Satellite" --yesno "Configure Postfix as satellite on $HOSTNAME LXC?" 10 58); then
  POSTFIX_SAT="yes"
else
  POSTFIX_SAT="no"
fi
echo -e "${DGN}Configure Postfix Satellite: ${BGN}$POSTFIX_SAT${CL}"

if [[ "${POSTFIX_SAT}" == "yes" ]]; then
  msg_info "Configuring Postfix Satellite"
  #Install deb-conf-utils to set parameters
  pct exec $CTID -- /bin/bash -c "apt install -y debconf-utils"
  pct exec $CTID -- /bin/bash -c "systemctl stop postfix"
  pct exec $CTID -- /bin/bash -c "mv /etc/postfix/main.cf /etc/postfix/main.cf.BAK"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/main_mailer_type        select  Satellite system | sudo debconf-set-selections -v"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/destinations    string  $HOSTNAME.localdomain, localhost.localdomain, localhost | sudo debconf-set-selections -v"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/mailname        string  $HOSTNAME.$DOMAIN | sudo debconf-set-selections -v"
  #This config assumes that the postfix relay host is already set up in another LXC with hostname "postfix" (using port 255)
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/relayhost       string  [postfix.$DOMAIN]:255 | sudo debconf-set-selections -v"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/mynetworks      string  127.0.0.0/8 | sudo debconf-set-selections -v"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/mailbox_limit      string  0 | sudo debconf-set-selections -v"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/protocols      select  all | sudo debconf-set-selections -v"
  pct exec $CTID -- /bin/bash -c "dpkg-reconfigure debconf -f noninteractive"
  pct exec $CTID -- /bin/bash -c "dpkg-reconfigure postfix -f noninteractive"
  pct exec $CTID -- /bin/bash -c "postconf 'smtp_tls_security_level = encrypt'"
  pct exec $CTID -- /bin/bash -c "postconf 'smtp_tls_wrappermode = yes'"
  pct exec $CTID -- /bin/bash -c "systemctl restart postfix"
  msg_ok "Configured Postfix Satellite"
fi

msg_ok "Post install script completed."

pct reboot $CTID
sleep 3
#exit