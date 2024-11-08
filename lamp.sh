#!/bin/bash

# Function to display error messages
error_exit() {
    echo "$1" >&2
    exit 1
}

# Function to prompt for user confirmation
confirm() {
    read -r -p "${1:-Are you sure?} [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            true
            ;;
        *)
            false
            ;;
    esac
}

# Function to select PHP version
select_php_version() {
    echo "Available PHP versions:"
    echo "1) PHP 7.4"
    echo "2) PHP 8.0"
    echo "3) PHP 8.1"
    echo "4) PHP 8.2"
    echo "5) PHP 8.3"
    echo "6) PHP 8.4"
    read -p "Select PHP version (1-4): " php_choice
    
    case $php_choice in
        1) PHP_VERSION="7.4" ;;
        2) PHP_VERSION="8.0" ;;
        3) PHP_VERSION="8.1" ;;
        4) PHP_VERSION="8.2" ;;
        5) PHP_VERSION="8.3" ;;
        6) PHP_VERSION="8.4" ;;
        *) error_exit "Invalid PHP version selected" ;;
    esac
    echo "Selected PHP version: $PHP_VERSION"
}

# Function to prompt for MySQL credentials
get_mysql_credentials() {
    read -p "Enter MySQL username (default: admin): " MYSQL_USER
    MYSQL_USER=${MYSQL_USER:-admin}
    
    read -s -p "Enter MySQL password: " MYSQL_PASS
    echo
    
    read -p "Enter database name (default: mydatabase): " DB_NAME
    DB_NAME=${DB_NAME:-mydatabase}
}

# Update system
echo "Updating system packages..."
sudo apt update || error_exit "Failed to update system packages"

# Install Apache
echo "Installing Apache2..."
sudo apt install -y apache2 || error_exit "Failed to install Apache2"

# Add PHP repository and install PHP
echo "Setting up PHP repository..."
sudo apt install -y ca-certificates apt-transport-https software-properties-common
sudo add-apt-repository -y ppa:ondrej/php
sudo apt update

# Select PHP version
select_php_version

# Install PHP and extensions
echo "Installing PHP ${PHP_VERSION} and extensions..."
sudo apt install -y php${PHP_VERSION} \
    php${PHP_VERSION}-common \
    php${PHP_VERSION}-opcache \
    php${PHP_VERSION}-cli \
    php${PHP_VERSION}-gd \
    php${PHP_VERSION}-curl \
    php${PHP_VERSION}-mysql \
    php${PHP_VERSION}-mbstring \
    php${PHP_VERSION}-zip \
    php${PHP_VERSION}-xml \
    php${PHP_VERSION}-intl || error_exit "Failed to install PHP"

# Install MySQL
echo "Installing MySQL server..."
sudo apt install -y mysql-server || error_exit "Failed to install MySQL"

# Get MySQL credentials
get_mysql_credentials

# Configure MySQL
echo "Configuring MySQL..."
sudo mysql -e "CREATE USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASS}';"
sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'localhost' WITH GRANT OPTION;"
sudo mysql -e "FLUSH PRIVILEGES;"
sudo mysql -e "CREATE DATABASE ${DB_NAME};"

# Install Git
echo "Installing Git..."
sudo apt install -y git || error_exit "Failed to install Git"

# Install Composer
echo "Installing Composer..."
cd ~
curl -sS https://getcomposer.org/installer -o /tmp/composer-setup.php
HASH=$(curl -sS https://composer.github.io/installer.sig)
php -r "if (hash_file('SHA384', '/tmp/composer-setup.php') === '$HASH') { echo 'Installer verified'; } else { echo 'Installer corrupt'; unlink('composer-setup.php'); } echo PHP_EOL;"
sudo php /tmp/composer-setup.php --install-dir=/usr/local/bin --filename=composer

# Install Node.js
echo "Installing Node.js..."
cd ~
curl -sL https://deb.nodesource.com/setup_20.x -o nodesource_setup.sh
sudo bash nodesource_setup.sh
sudo apt install -y nodejs

# Install Yarn (optional)
if confirm "Do you want to install Yarn?"; then
    echo "Installing Yarn..."
    npm install --global yarn
fi

echo "Installation complete!"
echo "PHP Version: ${PHP_VERSION}"
echo "MySQL User: ${MYSQL_USER}"
echo "Database Name: ${DB_NAME}"