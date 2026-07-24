sudo openvpn --config Weekilaw-Pars-Direct.ovpn --dev tun

sudo ip route add 10.0.0.0/8 via 10.2.45.1
sudo ip route add 10.20.0.0/16 via 192.168.254.1