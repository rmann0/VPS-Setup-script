This script automates basic setup of Ubuntu/Debian VPS.

### Features
- Creates a new non-root user and adds it to the sudo group
- Configures SSH key-only authentication
- Disables root login and password authentication
- Generates a random non-standard SSH port
- Waits for SSH key upload via `ssh-copy-id`
- Updates system
- Enables TCP BBR congestion control
- Configures firewall (iptables):
    - Allows SSH (custom port), HTTP (80), HTTPS (443)
    - Blocks all other incoming traffic
- Restarts SSH with the new configuration
---
You can download and run the script in a single command:
```bash
bash <(curl -fsSL https://raw.githubusercontent.com/rmann0/VPS-Setup-script/main/vps.sh)
```
or using `wget`:
```bash
bash <(wget -qO- https://raw.githubusercontent.com/rmann0/VPS-Setup-script/main/vps.sh)
```
