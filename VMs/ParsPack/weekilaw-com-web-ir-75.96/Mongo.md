# WeekiLaw
mongosh mongodb://WeekiLa:vaki1a2W@130.185.75.96:27017/?authSource=admin --eval "db.adminCommand"

mongosh mongodb://WeekiLa:vaki1a2W@127.0.0.1:27017/?authSource=admin --eval "db.adminCommand"

### Dump

docker exec -it c8d63f89b7ae bash

mongosh "mongodb://WeekiLa:vaki1a2W@127.0.0.1:27017/?authSource=admin" --eval "db.adminCommand('listDatabases')"

mkdir -p ~/mongo-migrate && cd ~/mongo-migrate

mongodump \
  --uri="mongodb://WeekiLa:vaki1a2W@127.0.0.1:27017/test?authSource=admin" \
  --out=./dump-weekilaw

mongodump \
  --uri="mongodb://WeekiLa:vaki1a2W@127.0.0.1:27017/weekilaw_ai_gateway?authSource=admin" \
  --out=./dump-weekilaw-ai-gateway

### CP TO VM

sudo docker cp mongodb:/data/db/mongo-migrate/dump-weekilaw-ai-gateway .
sudo docker cp mongodb:/data/db/mongo-migrate/dump-weekilaw .

### Tar

tar -czf weekilaw-$(date +%F).tgz dump-weekilaw
tar -czf weekilaw-ai-gateway-$(date +%F).tgz dump-weekilaw-ai-gateway

### CP to Destination
scp -P5566 weekilaw-*.tgz  izadi@158.255.74.75:~


## Destination

cd mongo-bkp/

tar -xzf weekilaw-2026-08-03.tgz
tar -xzf weekilaw-ai-gateway-2026-08-03.tgz

sudo docker cp dump-weekilaw mongodb:/tmp/dump-weekilaw
sudo docker cp dump-weekilaw-ai-gateway mongodb:/tmp/dump-weekilaw-ai-gateway

### Container

mongosh "mongodb://root:FNJ78dLHD7hln@d@127.0.0.1:27017/?authSource=admin" --eval "db.adminCommand('listDatabases')"

mongorestore 



sudo docker exec -it mongodb mongorestore \
  -u root -p 'FNJ78dLHD7hln@d' --authenticationDatabase admin \
  --nsFrom='test.*' \
  --nsTo='weekilaw.*' \
  --dir=/tmp/dump-weekilaw


sudo docker exec -it mongodb mongorestore \
  -u root -p 'FNJ78dLHD7hln@d' --authenticationDatabase admin \
  --dir=/tmp/dump-weekilaw-ai-gateway


sudo docker exec -it mongodb mongosh \
  -u root -p 'FNJ78dLHD7hln@d' --authenticationDatabase admin \
  --eval "db.adminCommand('listDatabases')"




# Lawgram
mongosh "mongodb://test:test123@185.239.3.93:27017/?authSource=admin" --eval "db.adminCommand('listDatabases')"

mongosh mongodb://admin:strongpassword@127.0.0.1:27017/?authSource=admin --eval "db.adminCommand"

