#!/usr/bin/env bash

# Copyright (c) 2021-2024 remz1337
# Author: remz1337
# License: MIT
# https://github.com/remz1337/Proxmox/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os



msg_info "Installing Dependencies"
#Configuration to make unattended installs with APT
#https://serverfault.com/questions/48724/100-non-interactive-debian-dist-upgrade
export DEBIAN_FRONTEND=noninteractive
export APT_LISTCHANGES_FRONTEND=none
#especially libc6, installed part of the dependency script (install_deps.sh)
echo 'libc6 libraries/restart-without-asking boolean true' | debconf-set-selections
cd /opt
$STD apt update
$STD apt upgrade -y
#I tried to install all the dependencies at the beginning, but it induced an error when building nginx, so I kept them in the same order of the Dockerfile
$STD apt install -y git automake build-essential wget xz-utils
msg_ok "Installed Dependencies"


msg_info "Downloading Frigate"
#Pull Frigate from  repo
#git clone https://github.com/blakeblackshear/frigate.git
wget https://github.com/blakeblackshear/frigate/archive/refs/tags/v0.13.0-beta2.tar.gz -O frigate.tar.gz
mkdir frigate
tar -xzf frigate.tar.gz -C frigate --strip-components 1
cd /opt/frigate
#Used in build dependencies scripts
export TARGETARCH=amd64
msg_ok "Downloaded Frigate"

msg_info "Building Nginx with custom modules"
docker/main/build_nginx.sh
msg_ok "Built Nginx with custom modules"

msg_info "Installing go2rtc"
mkdir -p /usr/local/go2rtc/bin
cd /usr/local/go2rtc/bin
wget -O go2rtc "https://github.com/AlexxIT/go2rtc/releases/download/v1.8.1/go2rtc_linux_${TARGETARCH}"
chmod +x go2rtc
msg_ok "Installed go2rtc"

msg_info "Installing object detection models"
cd /opt/frigate

### OpenVino
apt install -y wget python3 python3-distutils
wget https://bootstrap.pypa.io/get-pip.py -O get-pip.py
python3 get-pip.py "pip"
pip install -r docker/main/requirements-ov.txt


# Get OpenVino Model
mkdir -p /opt/frigate/models
cd /opt/frigate/models && omz_downloader --name ssdlite_mobilenet_v2
cd /opt/frigate/models && omz_converter --name ssdlite_mobilenet_v2 --precision FP16

# Build libUSB without udev.  Needed for Openvino NCS2 support
cd /opt/frigate

export CCACHE_DIR=/root/.ccache
export CCACHE_MAXSIZE=2G

apt install -y unzip build-essential automake libtool ccache pkg-config

wget https://github.com/libusb/libusb/archive/v1.0.26.zip -O v1.0.26.zip
unzip v1.0.26.zip
cd libusb-1.0.26
./bootstrap.sh
./configure --disable-udev --enable-shared
make -j $(nproc --all)

apt install -y --no-install-recommends libusb-1.0-0-dev

cd /opt/frigate/libusb-1.0.26/libusb

mkdir -p /usr/local/lib
/bin/bash ../libtool  --mode=install /usr/bin/install -c libusb-1.0.la '/usr/local/lib'
mkdir -p /usr/local/include/libusb-1.0
/usr/bin/install -c -m 644 libusb.h '/usr/local/include/libusb-1.0'
mkdir -p /usr/local/lib/pkgconfig
cd /opt/frigate/libusb-1.0.26/
/usr/bin/install -c -m 644 libusb-1.0.pc '/usr/local/lib/pkgconfig'
ldconfig

######## Frigate expects model files at root of filesystem
#cd /opt/frigate/models
cd /

# Get model and labels
wget -O edgetpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite
wget -O cpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess.tflite

#cp /opt/frigate/labelmap.txt .
cp /opt/frigate/labelmap.txt /labelmap.txt
cp -r /opt/frigate/models/public/ssdlite_mobilenet_v2/FP16 openvino-model

wget https://github.com/openvinotoolkit/open_model_zoo/raw/master/data/dataset_classes/coco_91cl_bkgr.txt -O openvino-model/coco_91cl_bkgr.txt
sed -i 's/truck/car/g' openvino-model/coco_91cl_bkgr.txt
# Get Audio Model and labels
wget -qO cpu_audio_model.tflite https://tfhub.dev/google/lite-model/yamnet/classification/tflite/1?lite-format=tflite
cp /opt/frigate/audio-labelmap.txt /audio-labelmap.txt
msg_ok "Installed object detection models"

msg_info "Configuring Python dependencies"
cd /opt/frigate

apt install -y python3 python3-dev wget build-essential cmake git pkg-config libgtk-3-dev libavcodec-dev libavformat-dev libswscale-dev libv4l-dev libxvidcore-dev libx264-dev libjpeg-dev libpng-dev libtiff-dev gfortran openexr libatlas-base-dev libssl-dev libtbb2 libtbb-dev libdc1394-22-dev libopenexr-dev libgstreamer-plugins-base1.0-dev libgstreamer1.0-dev gcc gfortran libopenblas-dev liblapack-dev

pip3 install -r docker/main/requirements.txt

pip3 wheel --wheel-dir=/wheels -r /opt/frigate/docker/main/requirements-wheels.txt
#pip3 wheel --wheel-dir=/trt-wheels -r /opt/frigate/docker/tensorrt/requirements-amd64.txt

#Copy preconfigured files
cp -a /opt/frigate/docker/main/rootfs/. /

#exports are lost upon system reboot...
#export PATH="$PATH:/usr/lib/btbn-ffmpeg/bin:/usr/local/go2rtc/bin:/usr/local/nginx/sbin"

# Install dependencies
/opt/frigate/docker/main/install_deps.sh

#Create symbolic links to ffmpeg and go2rtc
ln -svf /usr/lib/btbn-ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg
ln -svf /usr/lib/btbn-ffmpeg/bin/ffprobe /usr/local/bin/ffprobe
ln -svf /usr/local/go2rtc/bin/go2rtc /usr/local/bin/go2rtc

pip3 install -U /wheels/*.whl
ldconfig
msg_ok "Configured Python dependencies"

msg_info "Installing NodeJS"
# Install Node 16
#wget -O- https://deb.nodesource.com/setup_16.x | bash -

# Install Node 21
#curl -fsSL https://deb.nodesource.com/setup_21.x | sudo -E bash -
#sudo apt-get install -y nodejs
curl -fsSL https://deb.nodesource.com/setup_21.x | bash -

apt install -y nodejs
#npm install -g npm@9
npm install -g npm
msg_ok "Installed NodeJS"

msg_info "Installing Frigate"
pip3 install -r /opt/frigate/docker/main/requirements-dev.txt

# Frigate web build
# This should be architecture agnostic, so speed up the build on multiarch by not using QEMU.
cd /opt/frigate/web

npm install

npm run build

cp -r dist/BASE_PATH/monacoeditorwork/* dist/assets/

cd /opt/frigate/

cp -r /opt/frigate/web/dist/* /opt/frigate/web/



### BUILD COMPLETE, NOW INITIALIZE

mkdir /config
cp -r /opt/frigate/config/. /config
cp /config/config.yml.example /config/config.yml

################### EDIT CONFIG FILE HERE ################
#mqtt:
#  enabled: False
#
#cameras:
#  Camera1:
#    ffmpeg:
#      hwaccel_args: -c:v h264_cuvid
##      hwaccel_args: preset-nvidia-h264 #This one is not working...
#      inputs:
#        - path: rtsp://user:password@192.168.1.123:554/h264Preview_01_main
#          roles:
#            - detect
#    detect:
#      enabled: False
#      width: 2560
#      height: 1920
#########################################################

cd /opt/frigate

/opt/frigate/.devcontainer/initialize.sh

### POST_CREATE SCRIPT

############## Skip the ssh known hosts editing commands when running as root
######/opt/frigate/.devcontainer/post_create.sh

# Frigate normal container runs as root, so it have permission to create
# the folders. But the devcontainer runs as the host user, so we need to
# create the folders and give the host user permission to write to them.
#sudo mkdir -p /media/frigate
#sudo chown -R "$(id -u):$(id -g)" /media/frigate

make version

cd /opt/frigate/web

npm install

npm run build

cd /opt/frigate
msg_ok "Installed Frigate"

msg_info "Configuring Services"
#####Start order should be:
#1. Go2rtc
#2. Frigate
#3. Nginx

### Starting go2rtc
#Create systemd service. If done manually, edit the file (nano /etc/systemd/system/go2rtc.service) then copy/paste the service configuraiton
go2rtc_service="$(cat << EOF

[Unit]
Description=go2rtc service
After=network.target
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStart=bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/go2rtc/run

[Install]
WantedBy=multi-user.target

EOF
)"

echo "${go2rtc_service}" > /etc/systemd/system/go2rtc.service

systemctl start go2rtc
systemctl enable go2rtc

#Allow for a small delay before starting the next service
sleep 3

#Test go2rtc access at
#http://<machine_ip>:1984/



### Starting Frigate
#First, comment the call to S6 in the run script
sed -i '/^s6-svc -O \.$/s/^/#/' /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run

#Second, install yq, needed by script to check database path
wget -O /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
chmod a+x /usr/local/bin/yq

#Create systemd service
frigate_service="$(cat << EOF

[Unit]
Description=Frigate service
After=go2rtc.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStart=bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run

[Install]
WantedBy=multi-user.target

EOF
)"

echo "${frigate_service}" > /etc/systemd/system/frigate.service

systemctl start frigate
systemctl enable frigate

#Allow for a small delay before starting the next service
sleep 3

### Starting Nginx

## Call nginx from absolute path
## nginx --> /usr/local/nginx/sbin/nginx
sed -i 's/exec nginx/exec \/usr\/local\/nginx\/sbin\/nginx/g' /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run

#Can't log to /dev/stdout with systemd, so log to file
sed -i 's/error_log \/dev\/stdout warn\;/error_log nginx\.err warn\;/' /usr/local/nginx/conf/nginx.conf
sed -i 's/access_log \/dev\/stdout main\;/access_log nginx\.log main\;/' /usr/local/nginx/conf/nginx.conf

#Create systemd service
nginx_service="$(cat << EOF

[Unit]
Description=Nginx service
After=frigate.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStart=bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run

[Install]
WantedBy=multi-user.target

EOF
)"

echo "${nginx_service}" > /etc/systemd/system/nginx.service

systemctl start nginx
systemctl enable nginx
msg_ok "Configured Services"


#Test frigate through Nginx access at
#http://<machine_ip>:5000/


######## FULL FRIGATE CONFIG EXAMPLE:
#https://docs.frigate.video/configuration/

msg_ok "Don't forget to edit the Frigate config file (/config/config.yml) and reboot. Example configuration at https://docs.frigate.video/configuration/"
msg_ok "Frigate standalone installation complete! You can access the web interface at http://<machine_ip>:5000"






















########### OLD VW SCRIPT:


#Select DB engine (Sqlite or PostgreSQL, will maybe add MySQL later)
DB_ENGINE=""
while [ -z "$DB_ENGINE" ]; do
if DB_ENGINE=$(whiptail --backtitle "Proxmox VE Helper Scripts" --title "VAULTWARDEN DATABASE" --radiolist "Choose Database" 10 58 2 \
  "sqlite" "" OFF \
  "postgresql" "" OFF \
  3>&1 1>&2 2>&3); then
  if [ -n "$DB_ENGINE" ]; then
	echo -e "${DGN}Using Database Engine: ${BGN}$DB_ENGINE${CL}"
  fi
else
  exit-script
fi
done

#Fail2ban option
if (whiptail --backtitle "Proxmox VE Helper Scripts" --title "Fail2ban" --yesno "Configure fail2ban?" 10 58); then
  ENABLE_F2B=1
else
  ENABLE_F2B=0
fi

msg_info "Installing Dependencies"
$STD apt-get update
$STD apt-get -qqy install \
  git \
  build-essential \
  pkgconf \
  libssl-dev \
  libmariadb-dev-compat \
  libpq-dev \
  curl \
  sudo \
  argon2 \
  mc
msg_ok "Installed Dependencies"

WEBVAULT=$(curl -s https://api.github.com/repos/dani-garcia/bw_web_builds/releases/latest |
  grep "tag_name" |
  awk '{print substr($2, 2, length($2)-3) }')

VAULT=$(curl -s https://api.github.com/repos/dani-garcia/vaultwarden/releases/latest |
  grep "tag_name" |
  awk '{print substr($2, 2, length($2)-3) }')

msg_info "Installing Rust"
wget -qL https://sh.rustup.rs
$STD bash index.html -y --profile minimal
echo 'export PATH=~/.cargo/bin:$PATH' >>~/.bashrc
export PATH=~/.cargo/bin:$PATH
rm index.html
msg_ok "Installed Rust"

msg_info "Building Vaultwarden ${VAULT} (Patience)"
$STD git clone https://github.com/dani-garcia/vaultwarden
cd vaultwarden
#$STD cargo build --features "sqlite,mysql,postgresql" --release
$STD cargo build --features "$DB_ENGINE" --release
msg_ok "Built Vaultwarden ${VAULT}"

$STD addgroup --system vaultwarden
$STD adduser --system --home /opt/vaultwarden --shell /usr/sbin/nologin --no-create-home --gecos 'vaultwarden' --ingroup vaultwarden --disabled-login --disabled-password vaultwarden
mkdir -p /opt/vaultwarden/bin
mkdir -p /opt/vaultwarden/data
cp target/release/vaultwarden /opt/vaultwarden/bin/

msg_info "Downloading Web-Vault ${WEBVAULT}"
curl -fsSLO https://github.com/dani-garcia/bw_web_builds/releases/download/$WEBVAULT/bw_web_$WEBVAULT.tar.gz
tar -xzf bw_web_$WEBVAULT.tar.gz -C /opt/vaultwarden/
msg_ok "Downloaded Web-Vault ${WEBVAULT}"

#admintoken=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 70 | head -n 1)
admintoken=$(generate_token)
admintoken_hash=$(echo -n ${admintoken} | argon2 "$(openssl rand -base64 32)" -t 2 -m 16 -p 4 -l 64 -e)

#Local server IP
vw_ip4=$(hostname -I | awk '{print $1}')
#vw_ip4=$(ip a s dev eth0 | awk '/inet / {print $2}' | cut -d/ -f1)
#$STD vw_ip4=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
#echo "Local IP:$ip4"

cat <<EOF >/opt/vaultwarden/.env
ADMIN_TOKEN=${admintoken_hash}
ROCKET_ADDRESS=${vw_ip4}
DATA_FOLDER=/opt/vaultwarden/data
DATABASE_MAX_CONNS=10
WEB_VAULT_FOLDER=/opt/vaultwarden/web-vault
WEB_VAULT_ENABLED=true
EOF


if [ "$DB_ENGINE" == "postgresql" ]; then
  msg_info "Installing PostgreSQL"
  #sudo apt install postgresql postgresql-contrib libpq-dev dirmngr git libssl-dev pkg-config build-essential curl wget apt-transport-https ca-certificates software-properties-common pwgen -y
  $STD apt -qqy install postgresql postgresql-contrib
  msg_ok "Installed PostgreSQL"
  

  ### Configure PostgreSQL DB
  # Random password
  #postgresql_pwd=$(cat /dev/urandom | tr -dc 'a-zA-Z0-9' | fold -w 24 | head -n 1)
  postgresql_pwd=$(generate_token)
  sudo -u postgres psql -c "CREATE DATABASE vaultwarden;"
  sudo -u postgres psql -c "CREATE USER vaultwarden WITH ENCRYPTED PASSWORD '${postgresql_pwd}';"
  sudo -u postgres psql -c "GRANT all privileges ON database vaultwarden TO vaultwarden;"
  sudo -u postgres psql -c "GRANT USAGE ON SCHEMA public TO vaultwarden;"
  sudo -u postgres psql -c "ALTER DATABASE vaultwarden OWNER TO vaultwarden;"
  #echo "Successfully setup PostgreSQL DB vaultwarden with user vaultwarden and password ${postgresql_pwd}"

  echo "DATABASE_URL=postgresql://vaultwarden:${postgresql_pwd}@localhost:5432/vaultwarden" >> /opt/vaultwarden/.env
fi



msg_info "Creating Service"
chown -R vaultwarden:vaultwarden /opt/vaultwarden/
chown root:root /opt/vaultwarden/bin/vaultwarden
chmod +x /opt/vaultwarden/bin/vaultwarden
chown -R root:root /opt/vaultwarden/web-vault/
chmod +r /opt/vaultwarden/.env

service_path="/etc/systemd/system/vaultwarden.service"
echo "[Unit]
Description=Bitwarden Server (Powered by Vaultwarden)
Documentation=https://github.com/dani-garcia/vaultwarden
After=network.target
[Service]
User=vaultwarden
Group=vaultwarden
EnvironmentFile=-/opt/vaultwarden/.env
ExecStart=/opt/vaultwarden/bin/vaultwarden
LimitNOFILE=65535
LimitNPROC=4096
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
DevicePolicy=closed
ProtectControlGroups=yes
ProtectKernelModules=yes
ProtectKernelTunables=yes
RestrictNamespaces=yes
RestrictRealtime=yes
MemoryDenyWriteExecute=yes
LockPersonality=yes
WorkingDirectory=/opt/vaultwarden
ReadWriteDirectories=/opt/vaultwarden/data
AmbientCapabilities=CAP_NET_BIND_SERVICE
[Install]
WantedBy=multi-user.target" >$service_path
systemctl daemon-reload
$STD systemctl enable --now vaultwarden.service
msg_ok "Created Service"


if [ "$ENABLE_F2B" == 1 ]; then
  msg_info "Configuring fail2ban"

  #####Fail2ban setup
  $STD apt -qqy install fail2ban

  #Create files
  touch /etc/fail2ban/filter.d/vaultwarden.conf
  touch /etc/fail2ban/jail.d/vaultwarden.local
  touch /etc/fail2ban/filter.d/vaultwarden-admin.conf
  touch /etc/fail2ban/jail.d/vaultwarden-admin.local

  #Set vaultwarden fail2ban filter conf File
  vaultwardenfail2banfilter="/etc/fail2ban/filter.d/vaultwarden.conf"
  echo "[INCLUDES]
before = common.conf

[Definition]
failregex = ^.*Username or password is incorrect\. Try again\. IP: <HOST>\. Username:.*$
ignoreregex =" > $vaultwardenfail2banfilter

  #Set vaultwarden fail2ban jail conf File
  vaultwardenfail2banjail="/etc/fail2ban/jail.d/vaultwarden.local"
  echo "[vaultwarden]
enabled = true
port = 80,443,8081
filter = vaultwarden
action = iptables-allports[name=vaultwarden]
maxretry = 3
bantime = 14400
findtime = 14400" > $vaultwardenfail2banjail

  #Set vaultwarden fail2ban admin filter conf File
  vaultwardenfail2banadminfilter="/etc/fail2ban/filter.d/vaultwarden-admin.conf"
  echo "[INCLUDES]
before = common.conf

[Definition]
failregex = ^.*Unauthorized Error: Invalid admin token\. IP: <HOST>.*$
ignoreregex =" > $vaultwardenfail2banadminfilter

  #Set vaultwarden fail2ban admin jail conf File
  vaultwardenfail2banadminjail="/etc/fail2ban/jail.d/vaultwarden-admin.local"
  echo "[vaultwarden-admin]
enabled = true
port = 80,443
filter = vaultwarden-admin
action = iptables-allports[name=vaultwarden]
maxretry = 5
bantime = 14400
findtime = 14400" > $vaultwardenfail2banadminjail

  #In case of debian os, need to explicitly set the backend for fail2ban
  #see https://github.com/fail2ban/fail2ban/issues/3292
  os=$(less /etc/os-release | grep "^ID=")
  os="${os:3}"
  if [ "$os" == "debian" ]; then
    echo "backend = systemd" >> /etc/fail2ban/jail.d/defaults-debian.conf
  fi

  systemctl daemon-reload
  $STD systemctl restart fail2ban
  msg_info "Configured fail2ban"
fi

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"

msg_info "Important! Save the following admin token:"
echo "${admintoken}"
msg_info "Admin panel accessible at $vw_ip4:8000/admin"
