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
BGN=$(echo "\033[4;92m")
DGN=$(echo "\033[32m")
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

# This function sets up the Container OS by generating the locale, setting the timezone, and checking the network connection
default_setup() {
  msg_info "Setting up Container"
  pct exec $CTID -- /bin/bash -c "apt update -qq &>/dev/null"
  pct exec $CTID -- /bin/bash -c "apt install -qqy curl &>/dev/null"
  lxc-attach -n "$CTID" -- bash -c "source <(curl -s https://raw.githubusercontent.com/remz1337/Proxmox/remz/misc/install.func) && color && verb_ip6 && catch_errors && setting_up_container && network_check && update_os" || exit
  msg_ok "Set up Container"
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

# Set a global variable for the PHS environment file
PVE_ENV="/etc/pve-helper-scripts.conf"

function read_proxmox_helper_scripts_env(){
  #Check if file exists
  if [ ! -f "$PVE_ENV" ]; then
    echo -e "${BL}File not found. Creating file...${CL}"
    touch "$PVE_ENV"
    chown root:root "$PVE_ENV"
    chmod 0600 "$PVE_ENV"
  else
    source "$PVE_ENV"
#    if [ -z "$SSH_USER" ] || [ -z "$SSH_PASSWORD" ] || [ -z "$SHARE_USER" ] || [ -z "$DOMAIN" ]; then
#      msg_error "Missing proxmox-helper-scripts environment variables"
#      exit-script
#    fi
  fi
}

function add_proxmox_helper_scripts_env(){
  #check if first parameter was passed and it's an integer
  if [ $# -ge 1 ] && [ ! -z "$1" ]; then
    PHS_VAR_NAME=$1
	DEFAULT_VALUE=""
	if [ $# -ge 2 ] && [ ! -z "$2" ]; then
	  DEFAULT_VALUE=$2
	fi
    if PHS_VAR_VALUE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --inputbox "Set value for environment variable $PHS_VAR_NAME" 8 58 $DEFAULT_VALUE --title "VALUE" 3>&1 1>&2 2>&3); then
      if [ -z "$PHS_VAR_VALUE" ]; then
        PHS_VAR_VALUE=""
      fi
      echo -e "${DGN}Setting Proxmox-Helper-Scripts Envrionment Variable $PHS_VAR_NAME: ${BGN}${PHS_VAR_VALUE}${CL}"
      if grep -q "${PHS_VAR_NAME}=.*" "$PVE_ENV"; then
        # code if found
        sed -i 's/${PHS_VAR_NAME}=.*/${PHS_VAR_NAME}=${PHS_VAR_VALUE}/g' "$PVE_ENV"
      else
        # code if not found
        echo "${PHS_VAR_NAME}=${PHS_VAR_VALUE}" >> "$PVE_ENV"
      fi
    else
      exit-script
    fi
  else
    msg_error "You need to pass the variable name to set as the first parameter"
  fi
  read_proxmox_helper_scripts_env
}


echo -e "${BL}Customizing LXC creation${CL}"

# Test if required variables are set
[[ "${CTID:-}" ]] || exit "You need to set 'CTID' variable."
[[ "${PCT_OSTYPE:-}" ]] || exit "You need to set 'PCT_OSTYPE' variable."
[[ "${PCT_OSVERSION:-}" ]] || exit "You need to set 'PCT_OSVERSION' variable."


#Call default setup to have local, timezone and update APT
default_setup


###### Need function to read/write environment variables (default user/passwords/domain...)
#SSH_USER="myuser"
#SSH_PASSWORD="mypassword" # Use a prompt to save it encrypted, like the admin token for vaultwarden
#SHARE_USER="shareuser"
#DOMAIN="mydomain.com"
read_proxmox_helper_scripts_env


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


if (whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "SSH User" --yesno "Add common sudo user with SSH access?" 10 58); then
  ADD_SSH_USER="yes"
else
  ADD_SSH_USER="no"
fi
echo -e "${DGN}Add common sudo user with SSH access: ${BGN}$ADD_SSH_USER${CL}"

if [[ "${ADD_SSH_USER}" == "yes" ]]; then
  if [ -z ${SSH_USER+x} ] || [ -z ${SSH_PASSWORD+x} ]; then
    msg_error "Missing proxmox-helper-scripts environment variables"
    add_proxmox_helper_scripts_env "SSH_USER" "admin"
    add_proxmox_helper_scripts_env "SSH_PASSWORD"
  fi
  #Add ssh sudo user SSH_USER
  msg_info "Adding SSH user $SSH_USER (sudo)"
  if user_exists "$SSH_USER"; then
    msg_error 'User $SSH_USER already exists.'
  else
  #  echo 'user not found'
    pct exec $CTID -- /bin/bash -c "adduser $SSH_USER --disabled-password --gecos '' --uid 1000 &>/dev/null"
    pct exec $CTID -- /bin/bash -c "chpasswd <<<'$SSH_USER:$SSH_PASSWORD'"
    pct exec $CTID -- /bin/bash -c "usermod -aG sudo $SSH_USER"
    #echo "Default user added."
  fi
  msg_ok "Added SSH user $SSH_USER (sudo)"
fi


if (whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "Shared Mount" --yesno "Mount shared directory and add share user?" 10 58); then
  SHARED_MOUNT="yes"
else
  SHARED_MOUNT="no"
fi
echo -e "${DGN}Enable Shared Mount: ${BGN}$SHARED_MOUNT${CL}"


if [[ "${SHARED_MOUNT}" == "yes" ]]; then
  if [ -z ${SHARE_USER+x} ]; then
    msg_error "Missing proxmox-helper-scripts environment variables"
    add_proxmox_helper_scripts_env "SHARE_USER" "share"
  fi
  msg_info "Mounting shared directory"
  #Add user $SHARE_USER
  if user_exists "$SHARE_USER"; then
    msg_error 'User $SHARE_USER already exists.'
  else
  #  echo 'user not found'
    pct exec $CTID -- /bin/bash -c "adduser $SHARE_USER --disabled-password --gecos '' --uid 1001 &>/dev/null"
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
  msg_ok "Mounted shared directory"

  msg_info "Rebooting LXC to mount shared directory"
  pct reboot $CTID
  sleep 3
  msg_ok "Rebooting LXC to mount shared directory"
fi



if (whiptail --backtitle "Proxmox VE Helper Scripts" --defaultno --title "Configure Postfix Satellite" --yesno "Configure Postfix as satellite on $HOSTNAME LXC?" 10 58); then
  POSTFIX_SAT="yes"
else
  POSTFIX_SAT="no"
fi
echo -e "${DGN}Configure Postfix Satellite: ${BGN}$POSTFIX_SAT${CL}"

if [[ "${POSTFIX_SAT}" == "yes" ]]; then
  if [ -z ${DOMAIN+x} ]; then
    msg_error "Missing proxmox-helper-scripts environment variables"
    add_proxmox_helper_scripts_env "DOMAIN" "example.com"
  fi
  msg_info "Configuring Postfix Satellite"
  #Install deb-conf-utils to set parameters
  pct exec $CTID -- /bin/bash -c "apt install -qqy debconf-utils &>/dev/null"
  pct exec $CTID -- /bin/bash -c "systemctl stop postfix"
  pct exec $CTID -- /bin/bash -c "mv /etc/postfix/main.cf /etc/postfix/main.cf.BAK"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/main_mailer_type        select  Satellite system | debconf-set-selections"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/destinations    string  $HOSTNAME.localdomain, localhost.localdomain, localhost | debconf-set-selections"
  pct exec $CTID -- /bin/bash -c "echo postfix postfix/mailname        string  $HOSTNAME.$DOMAIN | debconf-set-selections"
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

msg_ok "Post install script completed."