#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Authors: tteck (tteckster)
# License: MIT
# https://github.com/tteck/Proxmox/raw/main/LICENSE

source /dev/stdin <<<"$FUNCTIONS_FILE_PATH"
color
verb_ip6
catch_errors
setting_up_container
network_check
update_os

msg_info "Installing Dependencies (Patience)"
$STD apt-get install -y {curl,sudo,mc,git,gpg,automake,build-essential,xz-utils,libtool,ccache,pkg-config,libgtk-3-dev,libavcodec-dev,libavformat-dev,libswscale-dev,libv4l-dev,libxvidcore-dev,libx264-dev,libjpeg-dev,libpng-dev,libtiff-dev,gfortran,openexr,libatlas-base-dev,libssl-dev,libtbb2,libtbb-dev,libdc1394-22-dev,libopenexr-dev,libgstreamer-plugins-base1.0-dev,libgstreamer1.0-dev,gcc,gfortran,libopenblas-dev,liblapack-dev,libusb-1.0-0-dev}
msg_ok "Installed Dependencies"

msg_info "Installing Python3 Dependencies"
$STD apt-get install -y {python3,python3-dev,python3-setuptools,python3-distutils,python3-pip}
msg_ok "Installed Python3 Dependencies"

msg_info "Installing Node.js"
mkdir -p /etc/apt/keyrings
curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/nodesource.gpg
echo "deb [signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_20.x nodistro main" >/etc/apt/sources.list.d/nodesource.list
$STD apt-get update
$STD apt-get install -y nodejs
msg_ok "Installed Node.js"

msg_info "Installing go2rtc"
mkdir -p /usr/local/go2rtc/bin
cd /usr/local/go2rtc/bin
wget -qO go2rtc "https://github.com/AlexxIT/go2rtc/releases/latest/download/go2rtc_linux_amd64"
chmod +x go2rtc
$STD ln -svf /usr/local/go2rtc/bin/go2rtc /usr/local/bin/go2rtc
msg_ok "Installed go2rtc"

if [[ "$CTTYPE" == "0" ]]; then
  msg_info "Setting Up Hardware Acceleration"
  $STD apt-get -y install {va-driver-all,ocl-icd-libopencl1,intel-opencl-icd,vainfo,intel-gpu-tools}
  chgrp video /dev/dri
  chmod 755 /dev/dri
  chmod 660 /dev/dri/*
  $STD adduser $(id -u -n) video
  $STD adduser $(id -u -n) render
  msg_ok "Set Up Hardware Acceleration"
fi

source <(curl -s https://raw.githubusercontent.com/remz1337/Proxmox/remz/misc/nvidia.func)
check_nvidia_drivers
if [ ! -z $NVD_VER ]; then
  echo -e "Nvidia drivers detected"
  msg_info "Installing Nvidia Dependencies"

  #apt install build-essential software-properties-common python3-pip python-is-python3
  #apt install nvidia-cuda-toolkit

  #Download CUDA (for Debian 11 runfile)
  #https://developer.nvidia.com/cuda-downloads
  #wget https://developer.download.nvidia.com/compute/cuda/12.2.2/local_installers/cuda_12.2.2_535.104.05_linux.run

  #Install CUDA (Uncheck Driver installation if already install, but make sure versions are compatible)
  #Need about 15Gb of free space
  #mkdir -p /tmp/nvidia/cuda
  #cd /tmp/nvidia
  #wget -q https://developer.download.nvidia.com/compute/cuda/12.2.2/local_installers/cuda_12.2.2_535.104.05_linux.run
  #sh cuda_12.2.2_535.104.05_linux.run --extract=/tmp/nvidia/cuda
  #cd /tmp/nvidia/cuda
  #./cuda-linux64-rel-7.5.18-19867135.run

  os=""
  if [ $PCT_OSTYPE == "debian" ]; then
    os="debian$PCT_OSVERSION"
  elif [ $PCT_OSTYPE == "ubuntu" ]; then
    os_ver=$(echo "$var_version" | sed 's|\.||g')
    os="ubuntu$os_ver"
  fi

  check_cuda_version
  TARGET_CUDA_VER=$(echo $NVD_VER_CUDA | sed 's|\.|-|g')

  apt install -y gnupg
  apt-key del 7fa2af80
  wget -q https://developer.download.nvidia.com/compute/cuda/repos/${os}/x86_64/cuda-keyring_1.1-1_all.deb
  dpkg -i cuda-keyring_1.1-1_all.deb
  rm cuda-keyring_1.1-1_all.deb
  apt update

  #Cache Nvidia tools with APT Cacher (if APT proxy is configured)
  #squid-deb-proxy-->/etc/apt/apt.conf.d/30autoproxy
  #auto-apt-proxy-->/etc/apt/apt.conf.d/auto-apt-proxy.conf
  #Tteck manual-->/etc/apt/apt.conf.d/00aptproxy
  #Look in files for "Acquire::http::Proxy"
  if grep -qR "Acquire::http::Proxy" /etc/apt/apt.conf.d/ && [ -f "/etc/apt/sources.list.d/cuda-${os}-x86_64.list" ]; then
    #deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] https://developer.download.nvidia.com/compute/cuda/repos/debian11/x86_64/ /
    #deb [signed-by=/usr/share/keyrings/cuda-archive-keyring.gpg] http://HTTPS///developer.download.nvidia.com/compute/cuda/repos/debian11/x86_64/ /

    #find /etc/apt/sources.list /etc/apt/sources.list.d/ -type f -exec sed -Ei 's!https://!'${LOCAL_APT_CACHE_URL}'/HTTPS///!g' {} \;
    #sed -Ei 's|https://|'${LOCAL_APT_CACHE_URL}'/HTTPS///|g' /etc/apt/sources.list.d/cuda-${os}-x86_64.list

    sed -i "s|https://developer|http://HTTPS///developer|g" /etc/apt/sources.list.d/cuda-${os}-x86_64.list
    apt update
  fi

  #apt install cuda-toolkit-12-4
  apt install -qqy "cuda-toolkit-$TARGET_CUDA_VER"
  apt install -qqy "cudnn-cuda-$NVD_MAJOR_CUDA"

  msg_ok "Installed Nvidia Dependencies"

  msg_info "Installing TensorRT"

  mkdir -p /tensorrt
  cd /tensorrt

  trt_url=$(curl -Lsk https://raw.githubusercontent.com/NVIDIA/TensorRT/main/README.md | grep "https://developer.nvidia.com/downloads/compute/machine-learning/tensorrt/.*/tars/TensorRT-.*.Linux.x86_64-gnu.cuda-${NVD_VER_CUDA}.tar.gz" | sed "s|.*](||g" | sed "s|)||g")
  TRT_VER=$(echo $trt_url | sed "s|.*tensorrt/||g" | sed "s|/tars.*||g")


  #os="ubuntu2204"
  #tag="9.3.0-cuda-12.4"
  #trt_tag="9.3.0"

  #wget -q https://developer.download.nvidia.com/compute/cuda/repos/${os}/x86_64/cuda-keyring_1.1-1_all.deb

  #https://developer.nvidia.com/downloads/compute/machine-learning/tensorrt/10.0.0/local_repo/nv-tensorrt-local-repo-${os}-10.0.0-cuda-${NVD_VER_CUDA}_1.0-1_amd64.deb
  #wget https://developer.nvidia.com/downloads/compute/machine-learning/tensorrt/${trt_tag}/local_repo/nv-tensorrt-local-repo-${os}-${trt_tag}-cuda-${NVD_VER_CUDA}_1.0-1_amd64.deb
  #wget https://developer.nvidia.com/downloads/compute/machine-learning/tensorrt/10.0.0/local_repo/nv-tensorrt-local-repo-ubuntu2204-10.0.0-cuda-12.4_1.0-1_amd64.deb

  #sudo dpkg -i nv-tensorrt-local-repo-${os}-${tag}_1.0-1_amd64.deb
  #sudo cp /var/nv-tensorrt-local-repo-${os}-${tag}/*-keyring.gpg /usr/share/keyrings/
  #sudo apt-get update

  #wget https://developer.nvidia.com/downloads/compute/machine-learning/tensorrt/${trt_tag}/tars/TensorRT-10.0.0.6.Linux.x86_64-gnu.cuda-${NVD_VER_CUDA}.tar.gz

  wget -qO TensorRT-Linux-x86_64-gnu-cuda.tar.gz $trt_url
  tar -xzvf TensorRT-Linux-x86_64-gnu-cuda.tar.gz -C /tensorrt --strip-components 1
  rm TensorRT-Linux-x86_64-gnu-cuda.tar.gz

  #export LD_LIBRARY_PATH=<TensorRT-${version}/lib>:$LD_LIBRARY_PATH

  #python3 -m pip install tensorrt-*-cp3x-none-linux_x86_64.whl

  ####### ADD THIS TO BASHRC
  #export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/tensorrt/TensorRT-8.6.1.6/lib
  echo "PATH=/usr/local/cuda/bin${PATH:+:${PATH}}"  >> /etc/bash.bashrc
  echo "LD_LIBRARY_PATH=/usr/local/cuda/lib64:/tensorrt/lib${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}" >> /etc/bash.bashrc

  #export CUDA_HOME=/usr/local/cuda
  #export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:/usr/local/cuda/lib64:/usr/local/cuda/extras/CUPTI/lib64:/usr/local/cuda-12.2/targets/x86_64-linux/lib:/tensorrt/TensorRT-8.6.1.6/lib
  #export PATH=$PATH:$CUDA_HOME/bin

  source /etc/bash.bashrc

  cd /tensorrt/python
  apt install -qqy python3

  PYTHON_VER=$(python3 --version | sed "s|.* ||g" | sed "s|\.||g" | sed "s|.$||")

  python3 -m pip install tensorrt-*-cp${PYTHON_VER}-none-linux_x86_64.whl

  #cd ../uff
  #python3 -m pip install uff-0.6.9-py2.py3-none-any.whl

  #cd ../graphsurgeon
  #python3 -m pip install graphsurgeon-0.4.6-py2.py3-none-any.whl

  cd ../onnx_graphsurgeon
  #python3 -m pip install onnx_graphsurgeon-0.3.12-py2.py3-none-any.whl
  #python3 -m pip install onnx_graphsurgeon-0.5.0-py2.py3-none-any.whl
  python3 -m pip install onnx_graphsurgeon-*-py2.py3-none-any.whl

  msg_ok "Installed TensorRT"
fi

RELEASE=$(curl -s https://api.github.com/repos/blakeblackshear/frigate/releases/latest | grep -o '"tag_name": *"[^"]*"' | cut -d '"' -f 4)
msg_info "Installing Frigate $RELEASE (Perseverance)"
cd ~
mkdir -p /opt/frigate/models
wget -q https://github.com/blakeblackshear/frigate/archive/refs/tags/${RELEASE}.tar.gz -O frigate.tar.gz
tar -xzf frigate.tar.gz -C /opt/frigate --strip-components 1
rm -rf frigate.tar.gz
cd /opt/frigate
$STD pip3 wheel --wheel-dir=/wheels -r /opt/frigate/docker/main/requirements-wheels.txt
cp -a /opt/frigate/docker/main/rootfs/. /
export TARGETARCH="amd64"
echo 'libc6 libraries/restart-without-asking boolean true' | debconf-set-selections
$STD /opt/frigate/docker/main/install_deps.sh
$STD ln -svf /usr/lib/btbn-ffmpeg/bin/ffmpeg /usr/local/bin/ffmpeg
$STD ln -svf /usr/lib/btbn-ffmpeg/bin/ffprobe /usr/local/bin/ffprobe
$STD pip3 install -U /wheels/*.whl
ldconfig
$STD pip3 install -r /opt/frigate/docker/main/requirements-dev.txt
$STD /opt/frigate/.devcontainer/initialize.sh
$STD make version
cd /opt/frigate/web
$STD npm install
$STD npm run build
cp -r /opt/frigate/web/dist/* /opt/frigate/web/
cp -r /opt/frigate/config/. /config
sed -i '/^s6-svc -O \.$/s/^/#/' /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run
cat <<EOF >/config/config.yml
mqtt:
  enabled: false
cameras:
  test:
    ffmpeg:
      #hwaccel_args: preset-vaapi
      inputs:
        - path: /media/frigate/person-bicycle-car-detection.mp4
          input_args: -re -stream_loop -1 -fflags +genpts
          roles:
            - detect
            - rtmp
    detect:
      height: 1080
      width: 1920
      fps: 5
EOF
ln -sf /config/config.yml /opt/frigate/config/config.yml
sed -i -e 's/^kvm:x:104:$/render:x:104:root,frigate/' -e 's/^render:x:105:root$/kvm:x:105:/' /etc/group
echo "tmpfs   /tmp/cache      tmpfs   defaults        0       0" >> /etc/fstab
msg_ok "Installed Frigate $RELEASE"

if [ ! -z $NVD_VER ]; then
  msg_info "Installing TensorRT Object Detection Model (Resilience)"
  ################ BUILDING TENSORRT
  pip3 wheel --wheel-dir=/trt-wheels -r /opt/frigate/docker/tensorrt/requirements-amd64.txt
  pip3 install -U /trt-wheels/*.whl
  #ln -s libnvrtc.so.11.2 /usr/local/lib/python3.9/dist-packages/nvidia/cuda_nvrtc/lib/libnvrtc.so
  ldconfig
  #pip3 install -U /trt-wheels/*.whl

  cp -a /opt/frigate/docker/tensorrt/detector/rootfs/. /

  echo "Depoloying Frigate detector models running on Nvidia GPU"
  echo "Make sure CUDA, cuDNN and TensorRT are already installed (with updated LD_LIBRARY_PATH)"

  ### Install TensorRT detector (using Nvidia GPU)
  # Avoid "LD_LIBRARY_PATH: unbound variable" by initializing the variable
  #export LD_LIBRARY_PATH=${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

  ################################# THIS IS OUTDATED, FRIGATE v0.13 HAS A S6 RUN SCRIPT TO BUILD TENSORRT DEMOS
  #mkdir -p /tensorrt_models
  #cd /tensorrt_models
  #wget https://github.com/blakeblackshear/frigate/raw/master/docker/tensorrt_models.sh
  #chmod +x tensorrt_models.sh
  #######################################################################

  mkdir -p /usr/local/src/tensorrt_demos
  cd /usr/local/src

  #### Need to adjust the tensorrt_demos files to replace TensorRT include path (it's hardcoded to v7 installed in /usr/local)
  ## /tensorrt_demos/plugins/Makefile --> change INCS and LIBS paths

  ######## MAKE SOME EDITS TO UPDATE TENSORRT PATHS
  #Create script to fix hardcoded TensorRT paths
  #fix_tensorrt="$(cat << EOF
  ##!/bin/bash
  #sed -i 's/\/usr\/local\/TensorRT-7.1.3.4/\/tensorrt\/TensorRT-8.6.1.6/g' /usr/local/src/tensorrt_demos/plugins/Makefile
  #EOF
  #)"

  fix_tensorrt="$(cat << EOF
#!/bin/bash
sed -i 's|/usr/local/TensorRT-.*/|/tensorrt/|g' /usr/local/src/tensorrt_demos/plugins/Makefile
EOF
)"

  #echo "${fix_tensorrt}" > /usr/local/src/tensorrt_demos/fix_tensorrt.sh
  echo "${fix_tensorrt}" > /opt/frigate/fix_tensorrt.sh

  #insert after this line :git clone --depth 1 https://github.com/yeahme49/tensorrt_demos.git /tensorrt_demos
  #sed -i '18 i bash \/tensorrt_models\/fix_tensorrt.sh' tensorrt_models.sh
  sed -i '9 i bash \/opt\/frigate\/fix_tensorrt.sh' /opt/frigate/docker/tensorrt/detector/tensorrt_libyolo.sh

  #apt install python and g++
  apt install -qqy python-is-python3 g++
  /opt/frigate/docker/tensorrt/detector/tensorrt_libyolo.sh

  ### NEED TO BUILD THE TRT MODELS
  cd /opt/frigate
  export YOLO_MODELS="yolov4-tiny-288,yolov4-tiny-416,yolov7-tiny-416"
  export TRT_VER="$TRT_VER"
  bash /opt/frigate/docker/tensorrt/detector/rootfs/etc/s6-overlay/s6-rc.d/trt-model-prepare/run

  cat <<EOF >>/config/config.yml
ffmpeg:
  hwaccel_args: preset-nvidia-h264
  output_args:
    record: preset-record-generic-audio-aac

detectors:
  tensorrt:
    type: tensorrt
#    device: 0

model:
  path: /config/model_cache/tensorrt/${TRT_VER}/yolov7-tiny-416.trt
  input_tensor: nchw
  input_pixel_format: rgb
  width: 416
  height: 416
EOF
  msg_ok "Installed TensorRT Object Detection Model (Resilience)"
elif grep -q -o -m1 'avx[^ ]*' /proc/cpuinfo; then
  echo -e "AVX support detected"
  msg_info "Installing Openvino Object Detection Model (Resilience)"
  $STD pip install -r /opt/frigate/docker/main/requirements-ov.txt
  cd /opt/frigate/models
  export ENABLE_ANALYTICS=NO
  $STD /usr/local/bin/omz_downloader --name ssdlite_mobilenet_v2 --num_attempts 2
  $STD /usr/local/bin/omz_converter --name ssdlite_mobilenet_v2 --precision FP16 --mo /usr/local/bin/mo
  cd /
  cp -r /opt/frigate/models/public/ssdlite_mobilenet_v2 openvino-model
  wget -q https://github.com/openvinotoolkit/open_model_zoo/raw/master/data/dataset_classes/coco_91cl_bkgr.txt -O openvino-model/coco_91cl_bkgr.txt
  sed -i 's/truck/car/g' openvino-model/coco_91cl_bkgr.txt
  cat <<EOF >>/config/config.yml
detectors:
  ov:
    type: openvino
    device: AUTO
    model:
      path: /openvino-model/FP16/ssdlite_mobilenet_v2.xml
model:
  width: 300
  height: 300
  input_tensor: nhwc
  input_pixel_format: bgr
  labelmap_path: /openvino-model/coco_91cl_bkgr.txt
EOF
  msg_ok "Installed Openvino Object Detection Model (Resilience)"
else
  cat <<EOF >>/config/config.yml
model:
  path: /cpu_model.tflite
EOF
fi

msg_info "Installing Coral Object Detection Model (Resilience)"
cd /opt/frigate
export CCACHE_DIR=/root/.ccache
export CCACHE_MAXSIZE=2G
wget -q https://github.com/libusb/libusb/archive/v1.0.26.zip
unzip -q v1.0.26.zip
rm v1.0.26.zip
cd libusb-1.0.26
$STD ./bootstrap.sh
$STD ./configure --disable-udev --enable-shared
$STD make -j $(nproc --all)
cd /opt/frigate/libusb-1.0.26/libusb
mkdir -p /usr/local/lib
$STD /bin/bash ../libtool  --mode=install /usr/bin/install -c libusb-1.0.la '/usr/local/lib'
mkdir -p /usr/local/include/libusb-1.0
$STD /usr/bin/install -c -m 644 libusb.h '/usr/local/include/libusb-1.0'
ldconfig
cd /
wget -qO edgetpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess_edgetpu.tflite
wget -qO cpu_model.tflite https://github.com/google-coral/test_data/raw/release-frogfish/ssdlite_mobiledet_coco_qat_postprocess.tflite
cp /opt/frigate/labelmap.txt /labelmap.txt
wget -qO cpu_audio_model.tflite https://tfhub.dev/google/lite-model/yamnet/classification/tflite/1?lite-format=tflite
cp /opt/frigate/audio-labelmap.txt /audio-labelmap.txt
mkdir -p /media/frigate
wget -qO /media/frigate/person-bicycle-car-detection.mp4 https://github.com/intel-iot-devkit/sample-videos/raw/master/person-bicycle-car-detection.mp4
msg_ok "Installed Coral Object Detection Model"

msg_info "Building Nginx with Custom Modules"
$STD /opt/frigate/docker/main/build_nginx.sh
sed -i 's/exec nginx/exec \/usr\/local\/nginx\/sbin\/nginx/g' /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run
sed -i 's/error_log \/dev\/stdout warn\;/error_log \/dev\/shm\/logs\/nginx\/current warn\;/' /usr/local/nginx/conf/nginx.conf
sed -i 's/access_log \/dev\/stdout main\;/access_log \/dev\/shm\/logs\/nginx\/current main\;/' /usr/local/nginx/conf/nginx.conf
msg_ok "Built Nginx"

msg_info "Creating Services"
cat <<EOF >/etc/systemd/system/create_directories.service
[Unit]
Description=Create necessary directories for logs

[Service]
Type=oneshot
ExecStart=/bin/bash -c '/bin/mkdir -p /dev/shm/logs/{frigate,go2rtc,nginx} && /bin/touch /dev/shm/logs/{frigate/current,go2rtc/current,nginx/current} && /bin/chmod -R 777 /dev/shm/logs'

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now create_directories
sleep 3
cat <<EOF >/etc/systemd/system/go2rtc.service
[Unit]
Description=go2rtc service
After=network.target
After=create_directories.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStartPre=+rm /dev/shm/logs/go2rtc/current
ExecStart=bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/go2rtc/run
StandardOutput=file:/dev/shm/logs/go2rtc/current
StandardError=file:/dev/shm/logs/go2rtc/current

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now go2rtc
sleep 3
cat <<EOF >/etc/systemd/system/frigate.service
[Unit]
Description=Frigate service
After=go2rtc.service
After=create_directories.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStartPre=+rm /dev/shm/logs/frigate/current
ExecStart=bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/frigate/run
StandardOutput=file:/dev/shm/logs/frigate/current
StandardError=file:/dev/shm/logs/frigate/current

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now frigate
sleep 3
cat <<EOF >/etc/systemd/system/nginx.service
[Unit]
Description=Nginx service
After=frigate.service
After=create_directories.service
StartLimitIntervalSec=0

[Service]
Type=simple
Restart=always
RestartSec=1
User=root
ExecStartPre=+rm /dev/shm/logs/nginx/current
ExecStart=bash /opt/frigate/docker/main/rootfs/etc/s6-overlay/s6-rc.d/nginx/run
StandardOutput=file:/dev/shm/logs/nginx/current
StandardError=file:/dev/shm/logs/nginx/current

[Install]
WantedBy=multi-user.target
EOF
systemctl enable -q --now nginx
msg_ok "Configured Services"

motd_ssh
customize

msg_info "Cleaning up"
$STD apt-get autoremove
$STD apt-get autoclean
msg_ok "Cleaned"

msg_ok "Don't forget to edit the Frigate config file (/config/config.yml) and reboot. Example configuration at https://docs.frigate.video/configuration/"
msg_ok "Frigate standalone installation complete! You can access the web interface at http://<machine_ip>:5000"