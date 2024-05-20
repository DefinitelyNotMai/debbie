#!/bin/sh

# user input
clear
printf "[INPUT]: Enter desired number between 1024 and 65535 to use as port for SSH: "
read -r PORT_SSH

# add repository for pgadmin
curl -fsS https://www.pgadmin.org/static/packages_pgadmin_org.pub | sudo gpg --dearmor -o /usr/share/keyrings/packages-pgadmin-org.gpg
sudo sh -c 'echo "deb [signed-by=/usr/share/keyrings/packages-pgadmin-org.gpg] https://ftp.postgresql.org/pub/pgadmin/pgadmin4/apt/$(lsb_release -cs) pgadmin4 main" > /etc/apt/sources.list.d/pgadmin4.list && apt update'

# make sure system is up-to-date and install packages
sudo apt update && sudo apt dist-upgrade
sudo apt install build-essential cmake curl fzf golang-go libssl-dev \
	mksh ssh tmux ufw unzip wget apache2 default-jdk default-jre libapache2-mod-php \
	mariadb-server php-cgi php-cli php-curl php-gd php-mbstring php-mysql php-xml \
	php-zip pkg-config postgis postgresql pgadmin4-web syncthing

# pgadmin
sudo /usr/pgadmin4/bin/setup-web.sh

# firewall and ssh configuration
sudo systemctl enable --now ufw
sudo systemctl enable --now ssh
sudo ufw enable
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 8080/tcp
sudo ufw allow 8384/tcp
sudo ufw allow "$PORT_SSH"/tcp
sudo sed -i "s/^#Port 22$/Port $PORT_SSH/" /etc/ssh/sshd_config
sudo sed -i "s/^#PermitRootLogin prohibit-password$/PermitRootLogin no/" /etc/ssh/sshd_config
sudo systemctl restart ssh

# make directories
mkdir -p "$HOME"/.cache "$HOME"/.config/nvim "$HOME"/.local/bin "$HOME"/.local/share/cargo \
	"$HOME"/.local/share/go "$HOME"/.local/share/rustup "$HOME"/.local/share/shell-history \
	"$HOME"/.local/state "$HOME"/.local/src "$HOME"/downloads

# clone dotfiles
git clone https://github.com/DefinitelyNotMai/dotfiles.git /tmp/dotfiles
cp -rvi /tmp/dotfiles/config/lf /tmp/dotfiles/config/shell /tmp/dotfiles/config/tmux \
	/tmp/dotfiles/config/wget "$HOME"/.config
cp -rvi /tmp/dotfiles/config/nvim/plugin "$HOME"/.config/nvim/plugin
ln -sf "$HOME"/.config/shell/profile "$HOME"/.profile
ln -sf "$HOME"/.config/shell/mksh/.mkshrc "$HOME"/.mkshrc
sed -i "47d;46d;45d;44d;" "$HOME"/.config/shell/profile
. "$HOME"/.profile

# install neovim (editor)
git clone https://github.com/neovim/neovim "$HOME"/.local/src/neovim
cd "$HOME"/.local/src/neovim || exit
make CMAKE_BUILD_TYPE=Release
sudo make install

# install latest lf file manager
env CGO_ENABLED=0 go install -ldflags="-s -w" github.com/gokcehan/lf@latest

# install rustup, sccache, and pfetch
curl --proto "=https" --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- --profile minimal --no-modify-path
cargo install sccache
printf "export RUSTC_WRAPPER=sccache\n" >> "$HOME"/.config/shell/profile
. "$HOME"/.profile
cargo install pfetch

# apache2
sudo systemctl enable --now apache2
sudo sed -i "s/memory_limit = 128M/memory_limit = 512M/" /etc/php/8.2/apache2/php.ini
sudo sed -i "s/upload_max_filesize = 2M/upload_max_filesize = 500M/" /etc/php/8.2/apache2/php.ini
sudo sed -i "s/post_max_size = 8M/post_max_size = 500M/" /etc/php/8.2/apache2/php.ini
sudo sed -i "s/max_execution_time = 30/max_execution_time = 300/" /etc/php/8.2/apache2/php.ini
sudo sed -i "s/;date.timezone =/date.timezone = Asia\/Singapore/" /etc/php/8.2/apache2/php.ini
sudo systemctl restart apache2

# mariadb
sudo systemctl enable --now mariadb
clear
printf "[ALERT]: Entering MariaDB session. Please entere these queries one by one:\n"
printf "\`\`\`\n"
printf "CREATE DATABASE nextcloud;\n"
printf "CREATE USER '<your username>'@'localhost' IDENTIFIED BY '<your user password>';\n"
printf "GRANT ALL PRIVILEGES ON nextcloud.* to '<your username>'@'localhost';\n"
printf "FLUSH ALL PRIVILEGES;\n"
printf "EXIT;\n"
printf "\`\`\`\n"
sudo mysql -u root

# nextcloud
wget https://download.nextcloud.com/server/releases/latest.zip -O "$HOME"/downloads/latest.zip
sudo unzip "$HOME"/downloads/latest.zip -d /var/www/html
sudo chown -R www-data:www-data /var/www/html/nextcloud
sudo chmod 755 /var/www/html/nextcloud
sh -c '{
	printf "<VirtualHost *:80>\n"
	printf "\tServerAdmin admin@example.com\n"
	printf "\tDocumentRoot /var/www/html/nextcloud/\n"
	printf "\tServerName 0.0.0.0\n"
	printf "\tAlias /nextcloud \"/var/www/html/nextcloud/\"\n\n"
	printf "\t<Directory /var/www/html/nextcloud/>\n"
	printf "\t\tOptions +FollowSymlinks\n"
	printf "\t\tAllowOverride All\n"
	printf "\t\tRequire all granted\n"
	printf "\t\t\t<IfModule mod_dav.c>\n"
	printf "\t\t\t\tDav off\n"
	printf "\t\t\t</IfModule>\n"
	printf "\t\tSetEnv HOME /var/www/html/nextcloud\n"
	printf "\t\tSetEnv HTTP_HOME /var/www/html/nextcloud\n"
	printf "\t</Directory>\n\n"
	printf "\tErrorLog ${APACHE_LOG_DIR}/error.log\n"
	printf "\tCustomLog ${APACHE_LOG_DIR}/access.log combined\n"
	printf "</VirtualHost>\n"
}' | sudo tee /etc/apache2/sites-available/nextcloud.conf > /dev/null 2>&1
cd /etc/apache2/sites-available || exit
sudo a2ensite nextcloud.conf
sudo a2enmod rewrite
sudo a2enmod headers
sudo a2enmod env
sudo a2enmod dir
sudo a2enmod mime
sudo systemctl restart apache2
clear
printf "[ALERT]: To finish Nextcloud installation, please open <your server's ip> in your browser and fill in the form.\n"
printf "Press <Enter> when you have finished to continue.\n"
read -r ans
sudo sed -i "s/^);$/  'skeletondirectory' => '',/" /var/www/html/nextcloud/config/config.php
printf ");\n" | sudo tee -a /var/www/html/nextcloud/config/config.php > /dev/null 2>&1

# syncthing
sudo mkdir /opt/syncthing-config
sudo chown www-data:www-data /opt/syncthing-config
sudo mkdir /srv/syncthing
sudo chown www-data:www-data /srv/syncthing
sh -c '{
	printf "[Unit]\n"
	printf "Description=Syncthing - Open Source Continuous File Synchronization for %s\n "%I"
	printf "Documentation=man:syncthing(1)\n"
	printf "After=network.target\n"
	printf "StartLimitIntervalSec=60\n"
	printf "StartLimitBurst=4\n\n"
	printf "[Service]\n"
	printf "User=www-data\n"
	printf "ExecStart=/usr/bin/syncthing serve --no-browser --no-restart --home=/opt/syncthing-config --logflags=3 --logfile=/var/log/syncthing.log\n
	printf "Restart=on-failure\n"
	printf "RestartSec=1\n"
	printf "SuccessExitStatus=3 4\n"
	printf "RestartForceExitStatus=3 4\n\n"
	printf "# Hardening\n"
	printf "ProtectSystem=full\n"
	printf "PrivateTmp=true\n"
	printf "SystemCallArchitectures=native\n"
	printf "MemoryDenyWriteExecute=true\n"
	printf "NoNewPrivileges=true\n\n"
	printf "[Install]\n"
	printf "WantedBy=multi-user.target\n"
}' | sudo tee /lib/systemd/system/syncthing@www-data.service
sudo systemctl enable --now syncthing@www-data
sudo systemctl stop syncthing@www-data
sudo sed -i "s/127.0.0.1/0.0.0.0/" /opt/syncthing-config/config.xml
sudo systemctl restart syncthing@www-data

# geoserver
sudo mkdir /usr/share/geoserver
sudo chown www-data:www-data /usr/share/geoserver
wget https://build.geoserver.org/geoserver/main/geoserver-main-latest-bin.zip -O "$HOME"/downloads/geoserver-main-latest-bin.zip
sudo unzip "$HOME"/downloads/geoserver-main-latest-bin.zip -d /usr/share/geoserver
sh -c '{
	printf "[Unit]\n"
	printf "Description=Geoserver\n"
	printf "After=multi-user.target\n\n"
	printf "[Service]\n"
	printf "Type=simple\n"
	printf "User=www-data\n"
	printf "WorkingDirectory=/usr/share/geoserver/bin\n"
	printf "ExecStart=/bin/sh /usr/share/geoserver/bin/startup.sh\n"
	printf "Restart=always\n"
	printf "RestartSec=5\n"
	printf "Environment=GEOSERVER_HOME=/usr/share/geoserver\n
	printf "Environment=GEOSERVER_DATA_DIR=/srv/syncthing/geodata\n\n
	printf "[Install]\n"
	printf "WantedBy=multi-user.target\n"
}' | sudo tee /lib/systemd/system/geoserver@www-data.service
sudo sed -i "201d;196d;163d;142d;" /usr/share/geoserver/webapps/geoserver/WEB-INF/web.xml
sudo mv /usr/share/geoserver/data_dir /srv/syncthing/geodata
sudo mkdir /srv/syncthing/geodata/custom
sudo chown -R www-data:www-data /srv/syncthing/geodata
sudo systemctl enable --now geoserver@www-data
