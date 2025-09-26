# Nextcloud Setup

This repository contains all the necessary files and scripts to set up a Nextcloud server with Apache and PHP-FPM optimizations.

## Structure

- `scripts/` - Installation and setup scripts
- `configs/` - Configuration files for Apache and PHP-FPM
- `docs/` - Documentation and guides

## 🚀 Getting Started

### Prerequisites
- Ubuntu 22.04 LTS server
- Minimum 2GB RAM (4GB recommended)
- Root or sudo access
- At least 10GB free disk space

### Installation Steps

1. **Prepare Your System**
   ```bash
   # Update package lists
   sudo apt update && sudo apt upgrade -y
   
   # Install required dependencies
   sudo apt install -y git
   ```

2. **Clone the Repository**
   ```bash
   git clone https://github.com/yourusername/nextcloud-setup.git
   cd nextcloud-setup
   ```

3. **Configure Your Setup**
   - Review and modify settings in `configs/install-config.conf`
   - Adjust PHP settings in `configs/php-settings.ini` if needed
   - Configure your web server in `configs/apache-nextcloud.conf`

4. **Run the Installation**
   ```bash
   # Make the script executable
   chmod +x ./scripts/install-nextcloud.sh
   
   # Run the installation (as root or with sudo)
   sudo ./scripts/install-nextcloud.sh
   ```

5. **Post-Installation**
   - Access your Nextcloud instance at `https://your-domain.com`
   - Complete the web-based setup wizard
   - Review security recommendations in `docs/security-hardening.md`

### Need Help?
- Check the [troubleshooting guide](docs/troubleshooting.md)
- Review the [detailed installation guide](docs/installation-guide.md)
- [Open an issue](https://github.com/yourusername/nextcloud-setup/issues) for support
3. Configure your web server with the provided config files