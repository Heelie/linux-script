#!/bin/sh
basedir=$(pwd)
pathdir="/usr/local/bin"
package="docker*.tgz"
download_url="https://download.docker.com/linux/static/stable/$(uname -m)/"

docker_pkg=`ls $package 2> /dev/null`

if [ $? -ne 0 ]; then
    latest=`curl -s $download_url | grep docker | grep -v docker-root | awk -F "\">" '{print $2}' | awk -F "</a>" '{print $1}' | tail -n 1`
    echo -e "downloading $download_url$latest\n"
    wget -q --show-progress $download_url$latest -O $basedir"/"$latest
    docker_pkg=`ls $package 2> /dev/null`
fi

if [ $(echo $docker_pkg | awk '{print NF}') -gt 1 ]; then
    echo "Multiple Docker Static Installation Packages Found:"
    echo ""
    echo $docker_pkg
    echo ""
    while :
    do
        read -p "select one:" docker_pkg
        if [ -f $docker_pkg ]; then
            break
        else
            echo file: $basedir"/"$docker_pkg not found
        fi
    done
fi

echo -e "\n$docker_pkg is found.\n"

echo -e "Starting extract $docker_pkg\n"
tar -zxf $docker_pkg --strip-components 1 -C $pathdir

echo "Here are the extracted commands:"
for cmd in $(tar -tf $docker_pkg | sed 1d | cut -d "/" -f 2)
do
    which $cmd
done

echo ""
mkdir -p /etc/containerd
echo "Creating /etc/containerd/config.toml"
cat << EOF > /etc/containerd/config.toml
#   Copyright 2018-2022 Docker Inc.

#   Licensed under the Apache License, Version 2.0 (the "License");
#   you may not use this file except in compliance with the License.
#   You may obtain a copy of the License at

#       http://www.apache.org/licenses/LICENSE-2.0

#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.

disabled_plugins = ["cri"]

#root = "/var/lib/containerd"
#state = "/run/containerd"
#subreaper = true
#oom_score = 0

#[grpc]
#  address = "/run/containerd/containerd.sock"
#  uid = 0
#  gid = 0

#[debug]
#  address = "/run/containerd/debug.sock"
#  uid = 0
#  gid = 0
#  level = "info"
EOF
echo "Done."

echo "Creating /etc/systemd/system/containerd.service"
cat << EOF > /etc/systemd/system/containerd.service
# Copyright The containerd Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

[Unit]
Description=containerd container runtime
Documentation=https://containerd.io
After=network.target local-fs.target

[Service]
ExecStartPre=-/sbin/modprobe overlay
ExecStart=$pathdir/containerd --config /etc/containerd/config.toml

Type=notify
Delegate=yes
KillMode=process
Restart=always
RestartSec=5
# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNPROC=infinity
LimitCORE=infinity
LimitNOFILE=infinity
# Comment TasksMax if your systemd version does not supports it.
# Only systemd 226 and above support this version.
TasksMax=infinity
OOMScoreAdjust=-999

[Install]
WantedBy=multi-user.target
EOF
echo "Done."

echo "Creating /etc/systemd/system/docker.socket"
cat << EOF > /etc/systemd/system/docker.socket
[Unit]
Description=Docker Socket for the API

[Socket]
# If /var/run is not implemented as a symlink to /run, you may need to
# specify ListenStream=/var/run/docker.sock instead.
ListenStream=/run/docker.sock
SocketMode=0660
SocketUser=root
SocketGroup=docker

[Install]
WantedBy=sockets.target
EOF
echo "Done."

echo "Creating /etc/systemd/system/docker.service"
cat << EOF > /etc/systemd/system/docker.service
[Unit]
Description=Docker Application Container Engine
Documentation=https://docs.docker.com
After=network-online.target docker.socket firewalld.service containerd.service time-set.target
Wants=network-online.target containerd.service
Requires=docker.socket

[Service]
Type=notify
# the default is not to use systemd for cgroups because the delegate issues still
# exists and systemd currently does not support the cgroup feature set required
# for containers run by docker
ExecStart=$pathdir/dockerd -H fd:// --containerd=/run/containerd/containerd.sock
ExecReload=/bin/kill -s HUP \$MAINPID
TimeoutStartSec=0
RestartSec=2
Restart=always

# Note that StartLimit* options were moved from "Service" to "Unit" in systemd 229.
# Both the old, and new location are accepted by systemd 229 and up, so using the old location
# to make them work for either version of systemd.
StartLimitBurst=3

# Note that StartLimitInterval was renamed to StartLimitIntervalSec in systemd 230.
# Both the old, and new name are accepted by systemd 230 and up, so using the old name to make
# this option work for either version of systemd.
StartLimitInterval=60s

# Having non-zero Limit*s causes performance problems due to accounting overhead
# in the kernel. We recommend using cgroups to do container-local accounting.
LimitNOFILE=infinity
LimitNPROC=infinity
LimitCORE=infinity

# Comment TasksMax if your systemd version does not support it.
# Only systemd 226 and above support this option.
TasksMax=infinity

# set delegate yes so that systemd does not reset the cgroups of docker containers
Delegate=yes

# kill only the docker process, not all processes in the cgroup
KillMode=process
OOMScoreAdjust=-500

[Install]
WantedBy=multi-user.target
EOF
echo "Done."

systemctl daemon-reload
