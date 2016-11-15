#sudo yum -y update
# Only for yum based 
#install_application epel-release
#install_application tree vim wget sysstat mdadm lsof screen wget fuser psmisc 
#install_application net-tools nmap-ncat collectd wget git emacs
#gcloud components update

yum -y install epel-release
yum -y install tree vim wget sysstat mdadm lsof screen wget psmisc net-tools nmap-ncat collectd git dstat

# Needed for compiling 
yum -y install gcc zlib-devel zip unzip flex byacc
#yum -y install maven emacs nginx

# Set time display to America/Los_Angeles
echo "export TZ=America/Los_Angeles" >> /etc/bashrc

cat << HEREDOC1 > /etc/collectd.conf
FQDNLookup   false
LoadPlugin syslog
LoadPlugin cpu
LoadPlugin disk
LoadPlugin interface
LoadPlugin memory
LoadPlugin write_graphite
<Plugin cpu>
  ReportByCpu false
  ReportByState true
</Plugin>
<Plugin disk>
        Disk "/^[hs]d[a-f][0-9]?$/"
</Plugin>
<Plugin interface>
        Interface "eth0"
</Plugin>
<Plugin memory>
        ValuesAbsolute false
        ValuesPercentage true
</Plugin>
<Plugin write_graphite>
  <Node "grf0">
    Host "104.154.91.143"
    Port "2003"
    Protocol "tcp"
    LogSendErrors true
    Prefix ""
    Postfix ""
    StoreRates true
    AlwaysAppendDS false
    EscapeCharacter "_"
  </Node>
</Plugin>
HEREDOC1

setenforce permissive
cat << HEREDOC2 > /etc/selinux/config
SELINUX=permissive
SELINUXTYPE=targeted
HEREDOC2
# Start collectd
systemctl enable collectd
systemctl start collectd

# Modify sshd defaults 
sed -i 's/ClientAliveInterval 420/ClientAliveInterval 0/' /etc/ssh/sshd_config
systemctl restart sshd

# Install sbt
gsutil cp gs://levyx-share/sbt-0.13.0.rpm .
yum install -y ./sbt-0.13.0.rpm

# Install scala
gsutil cp gs://levyx-share/scala-2.11.2.tgz .
tar xzf scala-2.11.2.tgz -C /opt

# Modify /etc/sudouers 
chmod +w /etc/sudoers
sed -i 's/Defaults\s\+requiretty/#Defaults requiretty/' /etc/sudoers
sed -i 's/Defaults\s\+!visiblepw/#Defaults !visiblepw/' /etc/sudoers
chmod -w /etc/sudoers

set -e
set -x 

# Get a list of disks from the metadata server.
BASE_DISK_URL='http://metadata.google.internal/computeMetadata/v1/instance/disks/'
DISK_PATHS=$(curl_v1_metadata "${BASE_DISK_URL}")
MOUNTED_DISKS=()

for DISK_PATH in ${DISK_PATHS}; do
  # Use the metadata server to determine the official index/name of each disk.
  DISK_NAME=$(curl_v1_metadata "${BASE_DISK_URL}${DISK_PATH}device-name")
  DISK_INDEX=$(curl_v1_metadata "${BASE_DISK_URL}${DISK_PATH}index")
  DISK_TYPE=$(curl_v1_metadata "${BASE_DISK_URL}${DISK_PATH}type")

  # Index '0' is the boot disk and is thus already mounted.
  if [[ "${DISK_INDEX}" == '0' ]]; then
    echo "Boot disk is ${DISK_NAME}; will not attempt to mount it."
    continue
  fi

  
  if [[ "${DISK_TYPE}" == 'LOCAL-SSD' ]]; then
    DISK_PREFIX='ed'
  elif [[ "${DISK_TYPE}" == 'PERSISTENT-SSD' ]]; then
    DISK_PREFIX='pd'
    continue
  fi

  # The metadata-specified 'name' can be converted to a disk 'id' by prepending
  # 'google-' and finding it under /dev/disk/by-id.
  DISK_ID="/dev/disk/by-id/google-${DISK_NAME}"
  echo "Resolved disk name '${DISK_NAME}' to expected path '${DISK_ID}'."

  # We will name the mount-point after the official 'disk index'; this means
  # there will be no mounted disk with suffix '0' since '0' is the boot disk.
  DATAMOUNT="/mnt/${DISK_PREFIX}${DISK_INDEX}"
  mkdir -p ${DATAMOUNT}
  MOUNTED_DISKS+=(${DATAMOUNT})
  echo "Mounting '${DISK_ID}' under mount point '${DATAMOUNT}'..."
  #$MOUNT_TOOL=/usr/share/google/safe_format_and_mount
  #${MOUNT_TOOL} -m 'mkfs.ext4 -F' ${DISK_ID} ${DATAMOUNT}
  mkfs.ext4 -F ${DISK_ID} 
  mount ${DISK_ID} ${DATAMOUNT}

  # Idempotently update /etc/fstab
  if cut -d '#' -f 1 /etc/fstab | grep -qvw ${DATAMOUNT}; then
    DISK_UUID=$(blkid ${DISK_ID} -s UUID -o value)
    MOUNT_ENTRY=($(grep -w ${DATAMOUNT} /proc/mounts))
    # Taken from /usr/share/google/safe_format_and_mount
    MOUNT_OPTIONS='defaults,discard'
    echo "UUID=${DISK_UUID} ${MOUNT_ENTRY[@]:1:2} ${MOUNT_OPTIONS} 0 2 \
        # added by bdutil" >> /etc/fstab
  fi
done

wget http://apache.spinellicreations.com/zookeeper/zookeeper-3.4.9/zookeeper-3.4.9.tar.gz
tar xzvf zookeeper-3.4.9.tar.gz
pushd zookeeper-3.4.9/src/c
./configure
make 
make install
popd

wget http://d3kbcqa49mib13.cloudfront.net/spark-1.6.1-bin-hadoop2.4.tgz
tar xzvf spark-1.6.1-bin-hadoop2.4.tgz
