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

# Step 3: Select destination user
echo -e "${YELLOW}Step 3: Selecting user on destination server...${NC}"
DEST_USER_LIST=$(sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "clpctl user:list" | tail -n +3 | head -n -1)
DEST_USERNAMES=()
DEST_INDEX=1

echo -e "${YELLOW}Available users on destination server:${NC}"
while read -r line; do
    DEST_USERNAME=$(echo $line | awk '{print $1}')
    DEST_USERNAMES+=("$DEST_USERNAME")
    echo "$DEST_INDEX) $DEST_USERNAME"
    ((DEST_INDEX++))
done <<< "$DEST_USER_LIST"

read -p "Select a user by entering the corresponding number for site migration: " DEST_USER_SELECTION
DEST_USER_INDEX=$((DEST_USER_SELECTION-1))
SELECTED_DEST_USER=${DEST_USERNAMES[$DEST_USER_INDEX]}
echo -e "${GREEN}You selected: $SELECTED_DEST_USER${NC}"

# Step 4: List home directories on source server
echo -e "${YELLOW}Step 4: Selecting home directory...${NC}"
HOME_DIRS=($(ls -d /home/*/))
INDEX=1
echo -e "${YELLOW}Available home directories:${NC}"
for dir in "${HOME_DIRS[@]}"; do
    echo "$INDEX) $(basename "$dir")"
    ((INDEX++))
done

read -p "Select a home directory by entering the corresponding number: " HOME_SELECTION
SELECTED_HOME_DIR=${HOME_DIRS[$((HOME_SELECTION-1))]}

# Step 5: List sites in selected home directory
echo -e "${YELLOW}Available sites in $SELECTED_HOME_DIR/htdocs:${NC}"
SITES=($(ls "$SELECTED_HOME_DIR/htdocs/"))
INDEX=1
for site in "${SITES[@]}"; do
    echo "$INDEX) $site"
    ((INDEX++))
done

read -p "Select a site to migrate (enter the corresponding number): " SITE_SELECTION
SELECTED_SITE=${SITES[$((SITE_SELECTION-1))]}
echo -e "${GREEN}You selected: $SELECTED_SITE${NC}"

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
VHOST_SRC="/etc/nginx/sites-available/$SELECTED_SITE"
VHOST_DEST="/etc/nginx/sites-available/$SELECTED_SITE"

# Copy the Vhost configuration file from source to destination
if scp "$VHOST_SRC" "$DEST_USER@$DEST_SERVER:$VHOST_DEST"; then
    echo -e "${GREEN}Vhost configuration copied successfully.${NC}"
else
    echo -e "${RED}Failed to copy Vhost configuration.${NC}"
    exit 1
fi

# Step 9: Copy home directory and site files
echo -e "${YELLOW}Copying home directory and site files...${NC}"
rsync -avz "$SELECTED_HOME_DIR/" "$DEST_USER@$DEST_SERVER:/home/$SELECTED_DEST_USER/htdocs/$SELECTED_SITE/"

# Step 10: Import the database if applicable
if [[ "$MIGRATE_DB" =~ ^[Yy](es)?$ ]]; then
    echo -e "${YELLOW}Importing database...${NC}"
    sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "mysql -u $DB_USER -p'$DB_PASS' $DB_NAME < $SELECTED_HOME_DIR/database.sql"
    echo -e "${GREEN}Database imported successfully.${NC}"
fi

# Step 11: Reload Nginx
echo -e "${YELLOW}Reloading Nginx on destination server...${NC}"
sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "systemctl reload nginx"

# Step 12: Final notices
echo -e "${YELLOW}Important Notices:${NC}"
if [ -d "$SELECTED_HOME_DIR/.varnish" ]; then
    echo -e "${GREEN}You need to enable Varnish in the CloudPanel GUI after the migration is completed.${NC}"
fi
echo -e "${GREEN}Remember to move Cron Jobs in the CloudPanel GUI on the new server.${NC}"
echo -e "${GREEN}Don't forget to update your DNS configuration to point to the new server.${NC}"

echo -e "${GREEN}Migration completed successfully!${NC}"
