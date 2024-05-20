# debbie

Shell script for a freshly installed instance of Debian 12 (Bookworm), installs Nextcloud, Syncthing, and Geoserver.

## Usage

1. When installing Debian, make sure to uncheck everything except for "standard desktop utilities".
2. Login as root and run these commands:

```bash
apt update && apt upgrade
apt install sudo git
usermod -aG sudo <your user>
```

3. Login as your user and run these commands:

```bash
git clone https://github.com/DefinitelyNotMai/debbie.git /tmp/debbie
cd /tmp/debbie
chmod +x install.sh
./deb.sh
```

4. After running the script, either reboot your system or simply log out and log back in.
