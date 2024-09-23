#!/bin/bash

# Color definitions
NC='\033[0m' # No Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'

# Welcome message
echo -e "${BLUE}Welcome to the CloudPanel Migration Script!${NC}"
echo -e "${YELLOW}GitHub Repository: https://github.com/anthonycl/CloudPanel-Migration-Script${NC}"

# Step 1: Get destination server credentials
read -p "Enter destination server hostname or IP: " DEST_SERVER
read -p "Enter SSH username for destination server: " DEST_USER
read -p "Enter password for SSH user (or press enter to skip/public key authentication): " DEST_PASS

# Check SSH connection
if [[ -n "$DEST_PASS" ]]; then
    sshpass -p "$DEST_PASS" ssh -o StrictHostKeyChecking=no "$DEST_USER@$DEST_SERVER" exit
    if [ $? -ne 0 ]; then
        echo -e "${RED}SSH connection failed! Please check your credentials.${NC}"
        exit 1
    fi
else
    ssh -o StrictHostKeyChecking=no "$DEST_USER@$DEST_SERVER" exit
    if [ $? -ne 0 ]; then
        echo -e "${RED}SSH connection failed! Please check your public key authentication.${NC}"
        exit 1
    fi
fi

# Ensure CloudPanel versions match
echo -e "${YELLOW}Checking CloudPanel versions...${NC}"
SRC_VERSION=$(clpctl --version)
DEST_VERSION=$(sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "clpctl --version")

if [[ "$SRC_VERSION" != "$DEST_VERSION" ]]; then
    echo -e "${RED}Error: CloudPanel versions do not match!${NC}"
    exit 1
fi
echo -e "${GREEN}CloudPanel versions match: $SRC_VERSION${NC}"

# Step 2: Select user to migrate
echo -e "${YELLOW}Step 2: Selecting user to migrate...${NC}"
USER_LIST=$(clpctl user:list | tail -n +3 | head -n -1)
USERNAMES=()
EMAILS=()
INDEX=1

echo -e "${YELLOW}Available users on source server:${NC}"
while read -r line; do
    USERNAME=$(echo $line | awk '{print $1}')
    EMAIL=$(echo $line | awk '{print $4}')
    USERNAMES+=("$USERNAME")
    EMAILS+=("$EMAIL")
    echo "$INDEX) $USERNAME ($EMAIL)"
    ((INDEX++))
done <<< "$USER_LIST"

# Ask if the user wants to migrate a user
read -p "Do you want to migrate a user from the source server? (yes/no): " MIGRATE_USER
if [[ "$MIGRATE_USER" =~ ^[Yy](es)?$ ]]; then
    read -p "Select a user by entering the corresponding number: " USER_SELECTION
    USER_INDEX=$((USER_SELECTION-1))
    SITE_USER=${USERNAMES[$USER_INDEX]}
    echo -e "${GREEN}You selected: $SITE_USER${NC}"

    # Check if user exists on destination server
    echo -e "${YELLOW}Checking if user $SITE_USER exists on destination server...${NC}"
    if sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "id -u $SITE_USER" >/dev/null 2>&1; then
        echo -e "${RED}User $SITE_USER already exists on destination server.${NC}"
        read -p "Do you want to delete this user before proceeding? (yes/no): " DELETE_USER
        if [[ "$DELETE_USER" =~ ^[Yy](es)?$ ]]; then
            sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "clpctl user:delete --username=$SITE_USER"
            echo -e "${GREEN}User $SITE_USER deleted from destination server.${NC}"
        fi
    fi

    # Create user on destination server
    sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "clpctl user:create --username=$SITE_USER --email=${EMAILS[$USER_INDEX]} --role=Admin"
    echo -e "${GREEN}User $SITE_USER created on destination server.${NC}"
fi

# Step 3: List all users in /home on source server
echo -e "${YELLOW}Step 3: Listing all users on source server...${NC}"
SOURCE_USERS=($(ls /home))
INDEX=1

echo -e "${YELLOW}Available users in /home:${NC}"
for USER in "${SOURCE_USERS[@]}"; do
    echo "$INDEX) $USER"
    ((INDEX++))
done

read -p "Select a user by entering the corresponding number for site migration: " USER_SELECTION
SELECTED_SOURCE_USER=${SOURCE_USERS[$((USER_SELECTION-1))]}
echo -e "${GREEN}You selected: $SELECTED_SOURCE_USER${NC}"

# Step 4: List sites in the selected user's home directory
SELECTED_HOME_DIR="/home/$SELECTED_SOURCE_USER"
echo -e "${YELLOW}Available sites in $SELECTED_HOME_DIR/htdocs:${NC}"

if [ -d "$SELECTED_HOME_DIR/htdocs" ]; then
    SITES=($(ls "$SELECTED_HOME_DIR/htdocs/"))
    INDEX=1
    for site in "${SITES[@]}"; do
        echo "$INDEX) $site"
        ((INDEX++))
    done

    read -p "Select a site to migrate (enter the corresponding number): " SITE_SELECTION
    SELECTED_SITE=${SITES[$((SITE_SELECTION-1))]}
    echo -e "${GREEN}You selected: $SELECTED_SITE${NC}"
else
    echo -e "${RED}No 'htdocs' directory found for user $SELECTED_SOURCE_USER.${NC}"
    exit 1
fi

# Step 4a: Confirm site type
echo -e "${YELLOW}Please select the site type to add:${NC}"
echo "1) PHP"
echo "2) Node.js"
echo "3) Static"
echo "4) Python"
read -p "Enter the corresponding number for the site type: " SITE_TYPE_SELECTION

case $SITE_TYPE_SELECTION in
    1)
        SITE_TYPE="php"
        read -p "Enter PHP version (default is 8.2): " PHP_VERSION
        PHP_VERSION=${PHP_VERSION:-8.2}
        read -p "Enter site user password: " -s SITE_USER_PASSWORD
        echo
        ;;
    2)
        SITE_TYPE="nodejs"
        read -p "Enter Node.js version (default is 18): " NODEJS_VERSION
        NODEJS_VERSION=${NODEJS_VERSION:-18}
        read -p "Enter application port (default is 3000): " APP_PORT
        APP_PORT=${APP_PORT:-3000}
        read -p "Enter site user password: " -s SITE_USER_PASSWORD
        echo
        ;;
    3)
        SITE_TYPE="static"
        read -p "Enter site user password: " -s SITE_USER_PASSWORD
        echo
        ;;
    4)
        SITE_TYPE="python"
        read -p "Enter Python version (default is 3.10): " PYTHON_VERSION
        PYTHON_VERSION=${PYTHON_VERSION:-3.10}
        read -p "Enter application port (default is 8080): " APP_PORT
        APP_PORT=${APP_PORT:-8080}
        read -p "Enter site user password: " -s SITE_USER_PASSWORD
        echo
        ;;
    *)
        echo -e "${RED}Invalid selection. Exiting...${NC}"
        exit 1
        ;;
esac

# Step 4b: Add the site on the destination server with appropriate parameters
echo -e "${YELLOW}Adding site to destination server...${NC}"
case $SITE_TYPE in
    php)
        sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "clpctl site:add:php --domainName=$SELECTED_SITE --phpVersion=$PHP_VERSION --vhostTemplate='Generic' --siteUser=$SITE_USER --siteUserPassword='$SITE_USER_PASSWORD'"
        ;;
    nodejs)
        sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "clpctl site:add:nodejs --domainName=$SELECTED_SITE --nodejsVersion=$NODEJS_VERSION --appPort=$APP_PORT --siteUser=$SITE_USER --siteUserPassword='$SITE_USER_PASSWORD'"
        ;;
    static)
        sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "clpctl site:add:static --domainName=$SELECTED_SITE --siteUser=$SITE_USER --siteUserPassword='$SITE_USER_PASSWORD'"
        ;;
    python)
        sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "clpctl site:add:python --domainName=$SELECTED_SITE --pythonVersion=$PYTHON_VERSION --appPort=$APP_PORT --siteUser=$SITE_USER --siteUserPassword='$SITE_USER_PASSWORD'"
        ;;
esac

# Step 5: Copy home directory and site files
echo -e "${YELLOW}Copying home directory and site files...${NC}"

# Ensure the destination directory exists
sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "mkdir -p /home/$SITE_USER/htdocs/$SELECTED_SITE"

# Now run rsync to copy the files
rsync -avz "$SELECTED_HOME_DIR/htdocs/$SELECTED_SITE/" "$DEST_USER@$DEST_SERVER:/home/$SITE_USER/htdocs/$SELECTED_SITE/"

# Step 6: Database migration option
read -p "Do you want to migrate the database for this site? (yes/no): " MIGRATE_DB
if [[ "$MIGRATE_DB" =~ ^[Yy](es)?$ ]]; then
    # Step 7: Database details
    read -p "Enter the database name for the site: " DB_NAME
    read -p "Enter the database username: " DB_USER
    read -s -p "Enter the database password: " DB_PASS
    echo # New line for better formatting
fi

# Step 8: Copy Vhost
echo -e "${YELLOW}Copying Vhost configuration...${NC}"
VHOST_SRC="/etc/nginx/sites-enabled/$SELECTED_SITE.conf"
VHOST_DEST="/etc/nginx/sites-enabled/$SELECTED_SITE.conf"

# Copy the Vhost configuration file from source to destination
if scp "$VHOST_SRC" "$DEST_USER@$DEST_SERVER:$VHOST_DEST"; then
    echo -e "${GREEN}Vhost configuration copied successfully.${NC}"
else
    echo -e "${RED}Failed to copy Vhost configuration.${NC}"
    exit 1
fi

# Step 9: Import the database if applicable
if [[ "$MIGRATE_DB" =~ ^[Yy](es)?$ ]]; then
    echo -e "${YELLOW}Importing database...${NC}"
    sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "mysql -u $DB_USER -p'$DB_PASS' $DB_NAME < $SELECTED_HOME_DIR/database.sql"
    echo -e "${GREEN}Database imported successfully.${NC}"
fi

# Step 10: Reload Nginx
echo -e "${YELLOW}Reloading Nginx on destination server...${NC}"
sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "/etc/init.d/nginx reload"

# Step 11: Final notices
echo -e "${YELLOW}Important Notices:${NC}"
echo -e "${GREEN}Remember
