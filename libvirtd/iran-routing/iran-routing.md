vim /etc/systemd/system/iran-routing.service
vim /usr/local/bin/iran-routing.sh
systemctl daemon-reload
systemctl enable iran-routing
systemctl start iran-routing
systemctl status iran-routing
sudo chmod +x /usr/local/bin/iran-routing.sh
systemctl start iran-routing
systemctl status iran-routing