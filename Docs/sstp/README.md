sudo sstpc --log-stdout --cert-warn \
  --user ui4-ir2 \
  --password '123123qwe' \
  78.110.124.179:4443 \
  usepeerdns require-mschap-v2 noauth


# سرویس را نگه دار که دوباره خراب نکند
sudo systemctl disable --now iran-routing

# rule بای‌پس را بردار
sudo ip rule del fwmark 1 table iran-bypass 2>/dev/null
sudo ip rule list

# ببین mark هنوز هست یا نه
sudo iptables -t mangle -L OUTPUT -n -v --line-numbers | head -30
sudo iptables -t mangle -L PREROUTING -n -v --line-numbers | head -30
