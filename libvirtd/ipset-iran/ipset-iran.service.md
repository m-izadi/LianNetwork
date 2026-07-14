apt install ipset iptables iproute2 iptables-persistent curl -y

ipset create iran hash:net family inet
while read -r cidr; do   ipset add iran "$cidr"; done < /root/ir.zone
sudo ipset restore < /etc/ipset/iran.ipset
sudo ipset create iran hash:net
ipset list iran | head

sudo vim /etc/systemd/system/ipset-iran.service

8  sudo systemctl daemon-reload
   59  sudo systemctl enable ipset-iran
   60  sudo systemctl start ipset-iran
   61  sudo systemctl status ipset-iran