#!/bin/bash

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# Function to confirm user input
confirm() {
    read -p "$1 (y/n): " response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Operation canceled.${NC}"
        exit 1
    fi
}

# Check for sshpass installation
if ! command -v sshpass &> /dev/null; then
    echo -e "${RED}Error: sshpass is not installed. Please install it to proceed.${NC}"
    exit 1
fi

# Prompt for destination server details
read -p "Enter destination server IP or hostname: " DEST_SERVER
read -p "Enter SSH user for destination server: " DEST_USER
read -sp "Enter password for SSH user: " DEST_PASS
echo

# Check SSH connection
sshpass -p "$DEST_PASS" ssh -o StrictHostKeyChecking=no $DEST_USER@$DEST_SERVER "exit"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Error: Unable to connect to the destination server!${NC}"
    exit 1
fi

# Ensure CloudPanel versions match
echo -e "${YELLOW}Checking CloudPanel versions...${NC}"
SRC_VERSION=$(clpctl --version)
DEST_VERSION=$(sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl --version")

if [[ "$SRC_VERSION" != "$DEST_VERSION" ]]; then
    echo -e "${RED}Error: CloudPanel versions do not match!${NC}"
    exit 1
fi

echo -e "${GREEN}CloudPanel versions match: $SRC_VERSION${NC}"

# Step 2: Select to migrate a user
read -p "Do you want to migrate a user from the source server? (y/n): " MIGRATE_USER
if [[ "$MIGRATE_USER" =~ ^[Yy]$ ]]; then
    # Step 2: Selecting user to migrate...
    echo -e "${YELLOW}Step 2: Selecting user to migrate...${NC}"

    USER_LIST=$(clpctl user:list | tail -n +3 | head -n -1)

    # Parse the user list and store usernames in an array
    USERNAMES=()
    INDEX=1
    echo -e "${YELLOW}Available users on source server:${NC}"
    while read -r line; do
        USERNAME=$(echo $line | awk '{print $1}')
        USERNAMES+=("$USERNAME")
        echo "$INDEX) $USERNAME"
        ((INDEX++))
    done <<< "$USER_LIST"

    # Prompt user to select the user by number
    read -p "Select a user by entering the corresponding number: " USER_SELECTION
    USER_INDEX=$((USER_SELECTION-1))
    SITE_USER=${USERNAMES[$USER_INDEX]}

    echo -e "${GREEN}You selected: $SITE_USER${NC}"

    # Check if user exists on destination server
    echo -e "${YELLOW}Checking if user $SITE_USER exists on destination server...${NC}"
    if sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "id -u $SITE_USER" >/dev/null 2>&1; then
        echo -e "${RED}User $SITE_USER already exists on destination server.${NC}"
        confirm "Do you want to delete this user before proceeding?"
        sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl user:delete --username=$SITE_USER"
        echo -e "${GREEN}User $SITE_USER deleted from destination server.${NC}"
    fi

    # Create user on the destination server
    echo -e "${YELLOW}Creating user $SITE_USER on destination server...${NC}"
    sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl user:create --username=$SITE_USER --password=$(openssl rand -base64 12)"
    echo -e "${GREEN}User $SITE_USER created on destination server.${NC}"

    # List users on destination server for selection
    echo -e "${YELLOW}Available users on destination server:${NC}"
    sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl user:list"

    # Prompt for the destination user to use for site migration
    read -p "Select a user from the destination server for site migration: " SELECTED_USER
else
    # List available users on the destination server
    SELECTED_USER=$(sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl user:list | awk 'NR==4 {print \$1}'")
    echo -e "${GREEN}Using default user on destination server: $SELECTED_USER${NC}"
fi

# Step 3: Select the home directory on the source server
echo -e "${YELLOW}Step 3: Selecting home directory on source server...${NC}"
echo -e "${YELLOW}Available home directories:${NC}"
ls -d /home/*/
read -p "Select the home directory to migrate (e.g., /home/username/): " SELECTED_HOME

# Step 4: List domains in the selected home directory
echo -e "${YELLOW}Available domains in $SELECTED_HOME/htdocs:${NC}"
ls $SELECTED_HOME/htdocs

read -p "Enter the domain to migrate (e.g., example.com): " DOMAIN

# Check if the directory and domain exist
if [[ ! -d "$SELECTED_HOME/htdocs/$DOMAIN" ]]; then
    echo -e "${RED}Error: Directory $SELECTED_HOME/htdocs/$DOMAIN does not exist!${NC}"
    exit 1
fi

# Export database and rsync the site
echo -e "${YELLOW}Exporting database for $DOMAIN...${NC}"
DB_NAME=$(sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl site:list | grep $DOMAIN | awk '{print \$3}'")
DB_USER=$(sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl site:list | grep $DOMAIN | awk '{print \$4}'")

# Step 5: Rsync the directory to the new server
echo -e "${YELLOW}Rsyncing $SELECTED_HOME/htdocs/$DOMAIN to $DEST_SERVER...${NC}"
sshpass -p "$DEST_PASS" rsync -avz $SELECTED_HOME/htdocs/$DOMAIN $DEST_USER@$DEST_SERVER:/home/$SELECTED_USER/htdocs/$DOMAIN

# Step 6: Create the site on the destination server
echo -e "${YELLOW}Creating site on destination server...${NC}"
sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl site:create --siteUser=$SELECTED_USER --domain=$DOMAIN --database=$DB_NAME --dbUser=$DB_USER --dbPass=$(openssl rand -base64 12)"

# Step 7: Reload Nginx
echo -e "${YELLOW}Reloading Nginx on destination server...${NC}"
sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "systemctl reload nginx"

# Step 8: Check for .varnish folder
if [ -d "$SELECTED_HOME/.varnish" ]; then
    echo -e "${YELLOW}Reminder: Enable Varnish in the CloudPanel GUI after migration.${NC}"
fi

# Step 9: Cron Jobs
echo -e "${YELLOW}Reminder: Move Cron Jobs in the CloudPanel GUI on the new server.${NC}"

# Step 10: DNS update
echo -e "${YELLOW}Reminder: Update your DNS configuration to point to the new server.${NC}"
echo -e "${GREEN}Migration completed successfully!${NC}"
