cd ~

# Update system packages

sudo apt update && sudo apt upgrade -y

# Install required tools

sudo apt install -y software-properties-common
sudo add-apt-repository universe
sudo apt update
sudo apt install -y git

# Clone the repository

rm -rf nextcloud-setup
git clone https://github.com/wagura-maurice/nextcloud-setup.git
cd nextcloud-setup

# Make all scripts executable

sudo chmod +x ./prepare-system.sh
sudo chmod +x src/utilities/install/_.sh
sudo chmod +x src/utilities/configure/_.sh

# Run system preparation script

sudo ./prepare-system.sh

# Install system dependencies

sudo ./src/utilities/install/install-system.sh

# Configure system dependencies

sudo ./src/utilities/configure/configure-system.sh

# Install Apache

sudo ./src/utilities/install/install-apache.sh

# Configure Apache for Nextcloud

sudo ./src/utilities/configure/configure-apache.sh

# Install PHP

sudo ./src/utilities/install/install-php.sh

# Configure PHP for Nextcloud

sudo ./src/utilities/configure/configure-php.sh
