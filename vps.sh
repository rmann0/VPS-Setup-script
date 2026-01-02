#!/bin/bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [ "$EUID" -ne 0 ]; then 
  echo -e "${RED}Please run this script as root or with sudo${NC}"
  exit 1
fi

echo -e "${BLUE}Enter the new username:${NC}"
read -p "" NEW_USER
if [ -z "$NEW_USER" ]; then
  echo -e "${RED}Username cannot be empty!${NC}"
  exit 1
fi

if id "$NEW_USER" >/dev/null 2>&1; then
  echo -e "${RED}User $NEW_USER already exists!${NC}"
  exit 1
fi

echo -e "${BLUE}Enter the password for $NEW_USER:${NC}"
read -s NEW_USER_PASS1
if [ -z "$NEW_USER_PASS1" ]; then
  echo -e "${RED}Password cannot be empty!${NC}"
  exit 1
fi
echo

echo -e "${BLUE}Confirm the password for $NEW_USER:${NC}"
read -s NEW_USER_PASS2
echo

if [ "$NEW_USER_PASS1" != "$NEW_USER_PASS2" ]; then
  echo -e "${RED}Passwords do not match!${NC}"
  exit 1
fi

NEW_USER_PASS="$NEW_USER_PASS1"

SSH_PORT=$(( ( RANDOM % 64511 ) + 1025 ))

echo -e "${GREEN}Creating new user $NEW_USER...${NC}"
if ! useradd -m $NEW_USER -s /bin/bash || \
   ! usermod -aG sudo "$NEW_USER" || \
   ! echo "$NEW_USER:$NEW_USER_PASS" | chpasswd; then
  echo -e "${RED}Failed to create user $NEW_USER!${NC}"
  exit 1
fi

echo -e "${GREEN}Creating SSH key directory...${NC}"
SSH_DIR="/home/$NEW_USER/.ssh"
mkdir -p "$SSH_DIR"
chown "$NEW_USER:$NEW_USER" "$SSH_DIR"
chmod 700 "$SSH_DIR"

IP_ADDR=$(ip -4 addr show scope global | grep inet | awk '{print $2}' | cut -d'/' -f1 | head -n1)
if [ -z "$IP_ADDR" ]; then
  echo -e "${RED}Could not determine server IP address!${NC}"
  exit 1
fi

echo -e "${YELLOW}Now copy your SSH key from your local machine with this command:${NC}"
echo -e "${YELLOW}ssh-copy-id -i ~/.ssh/*public_key_name*.pub $NEW_USER@$IP_ADDR${NC}"
echo -e "${BLUE}You will need to enter the password you just set${NC}"
echo -e "${BLUE}Waiting for the authorized_keys file to be created...${NC}"

while [ ! -f "$SSH_DIR/authorized_keys" ]; do
  sleep 2
done

echo -e "${GREEN}Keys detected, setting permissions...${NC}"
chmod 600 "$SSH_DIR/authorized_keys"
chown "$NEW_USER:$NEW_USER" "$SSH_DIR/authorized_keys"

echo -e "${GREEN}Updating the system...${NC}"
if ! apt update || ! apt full-upgrade -y || ! apt autoremove -y; then
  echo -e "${RED}System update failed!${NC}"
  exit 1
fi

echo -e "${GREEN}Installing packages...${NC}"
apt install -y sudo wget curl

if sysctl net.ipv4.tcp_congestion_control | grep bbr; then
    echo "BBR is already enabled"
else
    echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
    sysctl -p > /dev/null
    echo "Enabled BBR"
fi

echo -e "${GREEN}Configuring SSH with port $SSH_PORT...${NC}"
update_sshd_config() {
  local param="$1"
  local value="$2"
  local file="/etc/ssh/sshd_config"
  
  sed -i "/^\s*$param/d" "$file"
  echo "$param $value" >> "$file"
}

if ! update_sshd_config "Port" "$SSH_PORT" || \
   ! update_sshd_config "PermitRootLogin" "no" || \
   ! update_sshd_config "PasswordAuthentication" "no" || \
   ! update_sshd_config "PubkeyAuthentication" "yes"; then
  echo -e "${RED}Failed to configure SSH!${NC}"
  exit 1
fi

echo -e "${GREEN}Configuring firewall...${NC}"

debconf-set-selections <<EOF
iptables-persistent iptables-persistent/autosave_v4 boolean true
iptables-persistent iptables-persistent/autosave_v6 boolean true
EOF

apt install iptables-persistent netfilter-persistent -y
iptables -A INPUT -p icmp -j ACCEPT
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp -m state --state NEW -m tcp --dport $SSH_PORT -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp -m tcp --dport 443 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT
iptables -P INPUT DROP
netfilter-persistent save

systemctl restart sshd

echo -e "${GREEN}Setup completed!${NC}"
echo -e "${BLUE}New SSH port: $SSH_PORT${NC}"
echo -e "${BLUE}Username: $NEW_USER${NC}"
echo -e "${YELLOW}Test the new connection before closing this session!${NC}"
echo -e "${YELLOW}Use: ssh -p $SSH_PORT $NEW_USER@$IP_ADDR -i ~/.ssh/*public_key_name*.pub${NC}"