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

# Function to prompt for MySQL credentials
get_mysql_credentials() {
    read -p "Enter MySQL username (default: admin): " MYSQL_USER
    MYSQL_USER=${MYSQL_USER:-admin}
    
    read -s -p "Enter MySQL password: " MYSQL_PASS
    echo
    
    read -p "Enter database name (default: mydatabase): " DB_NAME
    DB_NAME=${DB_NAME:-mydatabase}
}


# Current web server
echo "Select current web server:"
echo "1) Apache (default)"
echo "2) Nginx"
read -p "Select web server (1-2, default: 1): " web_server_choice
web_server_choice=${web_server_choice:-1}


# Get MySQL credentials
get_mysql_credentials

# Configure MySQL
echo "Configuring MySQL..."

# Check if MySQL user already exists
USER_EXISTS=$(sudo mysql -sse "SELECT EXISTS(SELECT 1 FROM mysql.user WHERE user = '${MYSQL_USER}');")

if [ "$USER_EXISTS" -eq 1 ]; then
    echo "MySQL user '${MYSQL_USER}' already exists. Skipping user creation."
else
    sudo mysql -e "CREATE USER '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${MYSQL_PASS}';"
    sudo mysql -e "GRANT ALL PRIVILEGES ON *.* TO '${MYSQL_USER}'@'localhost' WITH GRANT OPTION;"
    sudo mysql -e "FLUSH PRIVILEGES;"
fi

# Check if the database exists before creating it
DB_EXISTS=$(sudo mysql -sse "SELECT EXISTS(SELECT SCHEMA_NAME FROM information_schema.schemata WHERE SCHEMA_NAME = '${DB_NAME}');")

if [ "$DB_EXISTS" -eq 1 ]; then
    echo "Database '${DB_NAME}' already exists. Skipping database creation."
else
    sudo mysql -e "CREATE DATABASE ${DB_NAME};"
    echo "Database '${DB_NAME}' created."
fi


# Get project details
read -p "Enter GitHub repository URL: " REPO_URL

# Navigate to web root
cd /var/www/html

# Clone the repository
echo "Cloning repository..."
sudo git clone "$REPO_URL" || error_exit "Failed to clone repository"

# Get the repository name from URL and cd into it
REPO_NAME=$(basename "$REPO_URL" .git)
cd "$REPO_NAME"

# Set proper permissions
sudo chown -R www-data:www-data /var/www/html/"$REPO_NAME"
sudo chmod -R 755 /var/www/html/"$REPO_NAME"

# Install dependencies with Composer
echo "Installing Composer dependencies..."
sudo -u www-data composer install || error_exit "Failed to install Composer dependencies"

# Setup environment file
echo "Setting up environment file..."
sudo cp .env.example .env || error_exit "Failed to create .env file"

# Generate application key
sudo php artisan key:generate || error_exit "Failed to generate application key"

# Update database credentials in .env
sudo sed -i "s/DB_CONNECTION=.*/DB_CONNECTION=mysql/" .env
sudo sed -i "s/# DB_HOST=.*/DB_HOST=127.0.0.1/" .env
sudo sed -i "s/# DB_PORT=.*/DB_PORT=3306/" .env
sudo sed -i "s/# DB_DATABASE=.*/DB_DATABASE=${DB_NAME}/" .env
sudo sed -i "s/# DB_USERNAME=.*/DB_USERNAME=${MYSQL_USER}/" .env
sudo sed -i "s/# DB_PASSWORD=.*/DB_PASSWORD=${MYSQL_PASS}/" .env


# Get domain name
read -p "Enter your domain name (e.g., example.com): " DOMAIN_NAME

# Create web server configuration
if [ "$web_server_choice" = "1" ]; then
    # Apache configuration
    echo "Creating Apache configuration..."
    sudo tee /etc/apache2/sites-available/${DOMAIN_NAME}.conf << EOF
<VirtualHost *:80>
    ServerAdmin admin@${DOMAIN_NAME}
    ServerName ${DOMAIN_NAME}
    DocumentRoot /var/www/html/${REPO_NAME}/public

    <Directory /var/www/html/${REPO_NAME}/public>
        Options Indexes MultiViews FollowSymLinks
        AllowOverride All
        Require all granted
    </Directory>

    ErrorLog \${APACHE_LOG_DIR}/error.log
    CustomLog \${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
EOF

    # Enable Apache rewrite module
    sudo a2enmod rewrite

    # Enable the new site
    sudo a2ensite ${DOMAIN_NAME}.conf

    # Disable default site
    sudo a2dissite 000-default.conf

    # Restart Apache
    sudo systemctl restart apache2
else
    # Nginx configuration
    echo "Creating Nginx configuration..."
    sudo tee /etc/nginx/sites-available/${DOMAIN_NAME} << EOF
server {
    listen 80;
    listen [::]:80;
    server_name ${DOMAIN_NAME};
    root /var/www/html/${REPO_NAME}/public;

    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";

    index index.php;

    charset utf-8;

    location / {
        try_files \$uri \$uri/ /index.php?\$query_string;
    }

    location = /favicon.ico { access_log off; log_not_found off; }
    location = /robots.txt  { access_log off; log_not_found off; }

    error_page 404 /index.php;

    location ~ \.php$ {
        fastcgi_pass unix:/var/run/php/php${PHP_VERSION}-fpm.sock;
        fastcgi_param SCRIPT_FILENAME \$realpath_root\$fastcgi_script_name;
        include fastcgi_params;
        fastcgi_hide_header X-Powered-By;
    }

    location ~ /\.(?!well-known).* {
        deny all;
    }
}
EOF

    # Create symbolic link
    sudo ln -s /etc/nginx/sites-available/${DOMAIN_NAME} /etc/nginx/sites-enabled/

    # Remove default nginx site
    sudo rm -f /etc/nginx/sites-enabled/default

    # Test nginx configuration
    sudo nginx -t

    # Restart Nginx
    sudo systemctl restart nginx
fi

# SSL Installation (optional)
if confirm "Do you want to install SSL certificate?"; then
    echo "WARNING: Before proceeding, ensure your domain's DNS A record points to this server's IP address."
    if confirm "Have you configured the DNS settings?"; then
        echo "Installing Certbot..."
        if [ "$web_server_choice" = "1" ]; then
            sudo apt install -y certbot python3-certbot-apache
            echo "Generating SSL certificate..."
            sudo certbot --apache
        else
            sudo apt install -y certbot python3-certbot-nginx
            echo "Generating SSL certificate..."
            sudo certbot --nginx
        fi
    else
        echo "Please configure DNS settings first and run SSL installation later."
    fi
fi

echo "Installation complete!" 