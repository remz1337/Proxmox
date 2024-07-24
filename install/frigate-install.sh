#!/usr/bin/env bash

# Copyright (c) 2021-2024 tteck
# Author: tteck (tteckster)
# Co-Author: remz1337
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
$STD apt-get install -y {curl,sudo,mc,git,gpg,automake,build-essential,xz-utils,libtool,ccache,pkg-config,libgtk-3-dev,libavcodec-dev,libavformat-dev,libswscale-dev,libv4l-dev,libxvidcore-dev,libx264-dev,libjpeg-dev,libpng-dev,libtiff-dev,gfortran,openexr,libatlas-base-dev,libssl-dev,libtbb2,libtbb-dev,libdc1394-22-dev,libopenexr-dev,libgstreamer-plugins-base1.0-dev,libgstreamer1.0-dev,gcc,gfortran,libopenblas-dev,liblapack-dev,libusb-1.0-0-dev,jq}
msg_ok "Installed Dependencies"

msg_info "Installing Python3 Dependencies"
$STD apt-get install -y {python3,python3-dev,python3-setuptools,python3-distutils,python3-pip}
$STD pip install --upgrade pip
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

msg_info "Setting Up Hardware Acceleration"
$STD apt-get -y install {va-driver-all,ocl-icd-libopencl1,intel-opencl-icd,vainfo,intel-gpu-tools}
if [[ "$CTTYPE" == "0" ]]; then
  chgrp video /dev/dri
  chmod 755 /dev/dri
  chmod 660 /dev/dri/*
fi
msg_ok "Set Up Hardware Acceleration"

RELEASE=$(curl -s https://api.github.com/repos/blakeblackshear/frigate/releases/latest | jq -r '.tag_name')
msg_ok "Stop spinner to prevent segmentation fault"
msg_info "Installing Frigate $RELEASE (Perseverance)"
if [ -n "$SPINNER_PID" ] && ps -p $SPINNER_PID > /dev/null; then kill $SPINNER_PID > /dev/null; fi
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
wget -q -O /opt/frigate/docker/main/install_deps.sh https://raw.githubusercontent.com/blakeblackshear/frigate/dev/docker/main/install_deps.sh
$STD /opt/frigate/docker/main/install_deps.sh
$STD apt update
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
if [[ "$CTTYPE" == "0" ]]; then
  sed -i -e 's/^kvm:x:104:$/render:x:104:root,frigate/' -e 's/^render:x:105:root$/kvm:x:105:/' /etc/group
else
  sed -i -e 's/^kvm:x:104:$/render:x:104:frigate/' -e 's/^render:x:105:$/kvm:x:105:/' /etc/group
fi
echo "tmpfs   /tmp/cache      tmpfs   defaults        0       0" >> /etc/fstab
msg_ok "Installed Frigate $RELEASE"

source <(curl -s https://raw.githubusercontent.com/remz1337/Proxmox/remz/misc/nvidia.func)
check_nvidia_drivers
if [ ! -z $NVD_VER ]; then
  echo -e "Nvidia drivers detected"
  msg_info "Installing Nvidia Dependencies"
  os=""
  if [ $PCT_OSTYPE == "debian" ]; then
    os="debian$PCT_OSVERSION"
  elif [ $PCT_OSTYPE == "ubuntu" ]; then
    os_ver=$(echo "$var_version" | sed 's|\.||g')
    os="ubuntu$os_ver"
  fi
  check_cuda_version
  TARGET_CUDA_VER=$(echo $NVD_VER_CUDA | sed 's|\.|-|g')
  $STD apt install -y gnupg
  $STD apt-key del 7fa2af80
  wget -q https://developer.download.nvidia.com/compute/cuda/repos/${os}/x86_64/cuda-keyring_1.1-1_all.deb
  $STD dpkg -i cuda-keyring_1.1-1_all.deb
  $STD apt install -y software-properties-common
  $STD apt update
  $STD add-apt-repository contrib
  rm cuda-keyring_1.1-1_all.deb
  if grep -qR "Acquire::http::Proxy" /etc/apt/apt.conf.d/ && [ -f "/etc/apt/sources.list.d/cuda-${os}-x86_64.list" ]; then
    sed -i "s|https://developer|http://HTTPS///developer|g" /etc/apt/sources.list.d/cuda-${os}-x86_64.list
  fi
  $STD apt update && sleep 1
  $STD apt update
  $STD apt install -qqy "cuda-toolkit-$TARGET_CUDA_VER"
  $STD apt install -qqy "cudnn-cuda-$NVD_MAJOR_CUDA"
  msg_ok "Installed Nvidia Dependencies"

  msg_info "Installing TensorRT"
  #pip3 wheel --wheel-dir=/trt-wheels -r /opt/frigate/docker/tensorrt/requirements-amd64.txt
  #pip3 install -U /trt-wheels/*.whl
  # Use latest TensorRT version (instead of fixed v8)
  $STD pip3 install --extra-index-url 'https://pypi.nvidia.com' numpy tensorrt cuda-python cython nvidia-cuda-runtime-cu12 nvidia-cuda-runtime-cu11 nvidia-cublas-cu11 nvidia-cudnn-cu11 onnx protobuf
  TRT_VER=$(pip freeze | grep tensorrt== | sed "s|tensorrt==||g")
  TRT_MAJOR=${TRT_VER%%.*}
  trt_url="https://developer.nvidia.com/downloads/compute/machine-learning/tensorrt/${TRT_VER}/local_repo/nv-tensorrt-local-repo-ubuntu2204-${TRT_VER}-cuda-${NVD_VER_CUDA}_1.0-1_amd64.deb"
  $STD wget -qO nv-tensorrt-local-repo-amd64.deb $trt_url
  $STD dpkg -i nv-tensorrt-local-repo-amd64.deb
  #Nvidia only provides DEB package for Ubuntu, but still works with Debian
  cp /var/nv-tensorrt-local-repo-ubuntu2204-${TRT_VER}-cuda-${NVD_VER_CUDA}/nv-tensorrt-local-*-keyring.gpg /usr/share/keyrings/
  rm nv-tensorrt-local-repo-amd64.deb
  $STD apt update
  # Needed on top of the python install for the NvInfer.h header
  $STD apt install -y tensorrt-dev
  export PATH=/usr/local/cuda/bin${PATH:+:${PATH}}
  export LD_LIBRARY_PATH=/usr/local/cuda/lib64:/usr/local/lib/python3.9/dist-packages/tensorrt_libs${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}
  echo "PATH=${PATH}"  >> /etc/bash.bashrc
  echo "LD_LIBRARY_PATH=${LD_LIBRARY_PATH}" >> /etc/bash.bashrc
  ldconfig
  # Temporarily get my patched frigate tensorrt.py plugin (with support for TensorRT v10)
  curl -s https://raw.githubusercontent.com/remz1337/frigate/dev/frigate/detectors/plugins/tensorrt.py > /opt/frigate/frigate/detectors/plugins/tensorrt.py
  msg_ok "Installed TensorRT"

  msg_info "Installing TensorRT Object Detection Model (Resilience)"
  cp -a /opt/frigate/docker/tensorrt/detector/rootfs/. /
  mkdir -p /usr/local/src/tensorrt_demos
  cd /usr/local/src
  fix_tensorrt="$(cat << EOF
#!/bin/bash
sed -i 's|/usr/local/TensorRT-.*/|/usr/local/lib/python3.9/dist-packages/tensorrt_libs/|g' /usr/local/src/tensorrt_demos/plugins/Makefile
EOF
)"
  echo "${fix_tensorrt}" > /opt/frigate/fix_tensorrt.sh
  if [ $TRT_MAJOR -gt 8 ]; then
    echo "sed -i 's|-lnvparsers ||g' /usr/local/src/tensorrt_demos/plugins/Makefile" >> /opt/frigate/fix_tensorrt.sh
  fi
  sed -i '18,21 s|.|#&|' /opt/frigate/docker/tensorrt/detector/tensorrt_libyolo.sh
  sed -i '9 i bash \/opt\/frigate\/fix_tensorrt.sh' /opt/frigate/docker/tensorrt/detector/tensorrt_libyolo.sh
  #Temporarly get my fork patched for TensorRT v10
  #sed -i 's|NateMeyer|remz1337|g' /opt/frigate/docker/tensorrt/detector/tensorrt_libyolo.sh
  $STD apt install -qqy python-is-python3 g++
  $STD /opt/frigate/docker/tensorrt/detector/tensorrt_libyolo.sh
  cd /opt/frigate
  export YOLO_MODELS="yolov4-tiny-288,yolov4-tiny-416,yolov7-tiny-416,yolov7-320"
  export TRT_VER="$TRT_VER"
  $STD bash /opt/frigate/docker/tensorrt/detector/rootfs/etc/s6-overlay/s6-rc.d/trt-model-prepare/run
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
  path: /config/model_cache/tensorrt/yolov7-tiny-416.trt
  input_tensor: nchw
  input_pixel_format: rgb
  width: 416
  height: 416
EOF
  msg_ok "Installed TensorRT Object Detection Model (Resilience)"
elif grep -q -o -m1 'avx[^ ]*' /proc/cpuinfo; then
  msg_ok "AVX Support Detected"
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
  msg_ok "Installed Openvino Object Detection Model"
else
  cat <<EOF >>/config/config.yml
model:
  path: /cpu_model.tflite
EOF
fi

msg_info "Installing Coral Object Detection Model (Patience)"
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
wget -qO yamnet-tflite-classification-tflite-v1.tar.gz https://www.kaggle.com/api/v1/models/google/yamnet/tfLite/classification-tflite/1/download
tar xzf yamnet-tflite-classification-tflite-v1.tar.gz
rm -rf yamnet-tflite-classification-tflite-v1.tar.gz
mv 1.tflite cpu_audio_model.tflite
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
$STD apt-get -y autoremove
$STD apt-get -y autoclean
msg_ok "Cleaned"

echo -e "Don't forget to edit the Frigate config file (${GN}/config/config.yml${CL}) and reboot. Example configuration at https://docs.frigate.video/configuration/"