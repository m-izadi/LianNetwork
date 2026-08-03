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


# Mirror

curl -O https://dl.min.io/client/mc/release/linux-amd64/mc
chmod +x mc
sudo mv mc /usr/local/bin/


mc alias set weekilaw-93 http://185.239.3.93:9000 admin 'strongminiopassword'

mc alias set wkl-fnt-prd-01 http://171.22.25.172:9000 root 'T89J@zH!zUifnDY!a'


mc mb newminio/weegram --ignore-existing


mc mirror --preserve --overwrite weekilaw-93/weekila newminio/weekila

mc mirror --preserve --overwrite --watch weekilaw-93/weekila newminio/weekila

mc ls --summarize weekilaw-93/weekila
mc ls --summarize newminio/weekila
mc du weekilaw-93/weekila