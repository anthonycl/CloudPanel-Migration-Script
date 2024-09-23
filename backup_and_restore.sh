#!/bin/bash

# Color definitions for a better console experience
NC='\033[0m' # No Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'

# Welcome message
echo -e "${BLUE}Welcome to the CloudPanel Backup and Restore Script!${NC}"
echo -e "${YELLOW}GitHub Repository: https://github.com/anthonycl/CloudPanel-Migration-Script${NC}"

# Function to validate arguments
validate_input() {
    if [ "$1" != "backup" ] && [ "$1" != "restore" ]; then
        echo -e "${RED}Invalid action: $1. Please specify 'backup' or 'restore'.${NC}"
        exit 1
    fi

    if [ -z "$2" ]; then
        echo -e "${RED}Please provide the site domain for $1.${NC}"
        exit 1
    fi
}

# Step 1: Validate user input
ACTION=$1
SITE_DOMAIN=$2

validate_input "$ACTION" "$SITE_DOMAIN"

# Backup function
backup_site() {
    echo -e "${YELLOW}Starting backup for site: $SITE_DOMAIN...${NC}"
    
    # Call the settingsFetcher.php script to backup the site
    php settingsFetcher.php --site="$SITE_DOMAIN" --backup
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}Backup completed successfully for site: $SITE_DOMAIN${NC}"
    else
        echo -e "${RED}Backup failed for site: $SITE_DOMAIN${NC}"
        exit 1
    fi
}

# Restore function
restore_site() {
    echo -e "${YELLOW}Starting restore for site: $SITE_DOMAIN...${NC}"
    
    # Check if the backup file exists
    BACKUP_FILE="/home/backups/${SITE_DOMAIN}.json"
    if [ ! -f "$BACKUP_FILE" ]; then
        echo -e "${RED}Backup file not found for site: $SITE_DOMAIN at $BACKUP_FILE${NC}"
        exit 1
    fi

    # Read the backup file
    SITE_JSON=$(cat "$BACKUP_FILE")
    
    # Extract site details
    SITE_TYPE=$(echo "$SITE_JSON" | jq -r '.site[0].site_type')
    SITE_USER=$(echo "$SITE_JSON" | jq -r '.site[0].siteUser')
    SITE_PASSWORD=$(echo "$SITE_JSON" | jq -r '.site[0].siteUserPassword')
    DOMAIN_NAME=$(echo "$SITE_JSON" | jq -r '.site[0].domain_name')
    
    # Prompt user for missing details if necessary
    if [ -z "$SITE_PASSWORD" ]; then
        read -s -p "Enter the site user password: " SITE_PASSWORD
        echo
    fi

    # Create the site based on its type
    case $SITE_TYPE in
        php)
            read -p "Enter PHP version (default is 8.2): " PHP_VERSION
            PHP_VERSION=${PHP_VERSION:-8.2}
            clpctl site:add:php --domainName="$DOMAIN_NAME" --phpVersion="$PHP_VERSION" --vhostTemplate="Generic" --siteUser="$SITE_USER" --siteUserPassword="$SITE_PASSWORD"
            ;;
        nodejs)
            read -p "Enter Node.js version (default is 18): " NODEJS_VERSION
            NODEJS_VERSION=${NODEJS_VERSION:-18}
            read -p "Enter application port (default is 3000): " APP_PORT
            APP_PORT=${APP_PORT:-3000}
            clpctl site:add:nodejs --domainName="$DOMAIN_NAME" --nodejsVersion="$NODEJS_VERSION" --appPort="$APP_PORT" --siteUser="$SITE_USER" --siteUserPassword="$SITE_PASSWORD"
            ;;
        static)
            clpctl site:add:static --domainName="$DOMAIN_NAME" --siteUser="$SITE_USER" --siteUserPassword="$SITE_PASSWORD"
            ;;
        python)
            read -p "Enter Python version (default is 3.10): " PYTHON_VERSION
            PYTHON_VERSION=${PYTHON_VERSION:-3.10}
            read -p "Enter application port (default is 8080): " APP_PORT
            APP_PORT=${APP_PORT:-8080}
            clpctl site:add:python --domainName="$DOMAIN_NAME" --pythonVersion="$PYTHON_VERSION" --appPort="$APP_PORT" --siteUser="$SITE_USER" --siteUserPassword="$SITE_PASSWORD"
            ;;
        *)
            echo -e "${RED}Unknown site type: $SITE_TYPE. Cannot restore.${NC}"
            exit 1
            ;;
    esac

    # Restore the Vhost configuration
    echo -e "${YELLOW}Restoring Vhost configuration...${NC}"
    VHOST_FILE="/etc/nginx/sites-enabled/${DOMAIN_NAME}.conf"
    if [ -f "$VHOST_FILE" ]; then
        cp "$VHOST_FILE" "/etc/nginx/sites-available/"
        ln -s "/etc/nginx/sites-available/${DOMAIN_NAME}.conf" "/etc/nginx/sites-enabled/${DOMAIN_NAME}.conf"
        echo -e "${GREEN}Vhost configuration restored for $DOMAIN_NAME.${NC}"
    else
        echo -e "${RED}Vhost file not found for $DOMAIN_NAME! Skipping...${NC}"
    fi
    
    # Import the database if it exists in the backup
    DB_NAME=$(echo "$SITE_JSON" | jq -r '.database.db_name // empty')
    DB_USER=$(echo "$SITE_JSON" | jq -r '.database.db_user // empty')
    DB_PASSWORD=$(echo "$SITE_JSON" | jq -r '.database.db_password // empty')

    if [ -n "$DB_NAME" ] && [ -n "$DB_USER" ]; then
        echo -e "${YELLOW}Restoring database...${NC}"
        mysql -u "$DB_USER" -p"$DB_PASSWORD" "$DB_NAME" < "/home/$SITE_USER/htdocs/${DOMAIN_NAME}/database.sql"
        echo -e "${GREEN}Database restored successfully for $DOMAIN_NAME${NC}"
    else
        echo -e "${RED}No database information found in the backup for $DOMAIN_NAME.${NC}"
    fi

    # Reload Nginx
    echo -e "${YELLOW}Reloading Nginx...${NC}"
    /etc/init.d/nginx reload
    echo -e "${GREEN}Nginx reloaded successfully.${NC}"

    echo -e "${GREEN}Restore completed for site: $SITE_DOMAIN!${NC}"
}

# Perform the backup or restore based on user input
case $ACTION in
    backup)
        backup_site
        ;;
    restore)
        restore_site
        ;;
    *)
        echo -e "${RED}Invalid action: $ACTION${NC}"
        exit 1
        ;;
esac
