# Installation

  sudo dpkg -i minio_20250422221226.0.0_amd64.deb
  vim /etc/default/minio
  
    MINIO_VOLUMES="/data/minio/disk1/minio"
    MINIO_OPTS="--console-address :9001"
    MINIO_ROOT_USER=root
    MINIO_ROOT_PASSWORD=T89J@zH!zUifnDY!a

  ip -br -c a
  vim /etc/default/minio
  sudo groupadd -r minio-user
  sudo useradd -M -r -g minio-user minio-user
  sudo chown -R minio-user:minio-user /data/minio
