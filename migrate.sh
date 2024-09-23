#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}CloudPanel Migration Script Starting...${NC}"

# Function to confirm action
confirm() {
    read -p "$1 (y/n): " choice
    case "$choice" in 
        y|Y ) echo "Proceeding...";;
        n|N ) echo "Aborting..."; exit 1;;
        * ) echo "Invalid choice"; confirm "$1";;
    esac
}

# Function to validate SSH credentials
validate_ssh() {
    echo -e "${YELLOW}Validating SSH credentials...${NC}"
    sshpass -p "$DEST_PASS" ssh -o StrictHostKeyChecking=no $DEST_USER@$DEST_SERVER "echo 'SSH connection successful!'" >/dev/null 2>&1
    return $?
}

# Function to validate database connection
validate_db() {
    local db_user=$1
    local db_pass=$2
    local db_name=$3
    local server=$4
    echo -e "${YELLOW}Validating database connection for database '$db_name' on server '$server'...${NC}"
    
    mysql -u $db_user -p$db_pass -h $server -e "USE $db_name;" >/dev/null 2>&1
    return $?
}

# Step 1: Get Server Info and SSH credentials
echo -e "${YELLOW}Step 1: Checking system compatibility...${NC}"

read -p "Enter destination server IP or hostname: " DEST_SERVER
read -p "Enter SSH username for destination server: " DEST_USER
read -sp "Enter SSH password for destination server: " DEST_PASS
echo ""

# Check SSH credentials and re-prompt if incorrect
while ! validate_ssh; do
    read -sp "Re-enter SSH password for destination server: " DEST_PASS
    echo ""
done

# Ensure CloudPanel versions match
echo -e "${YELLOW}Checking CloudPanel versions...${NC}"
SRC_VERSION=$(clpctl --version)
DEST_VERSION=$(sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl --version")

if [[ "$SRC_VERSION" != "$DEST_VERSION" ]]; then
    echo -e "${RED}Error: CloudPanel versions do not match!${NC}"
    exit 1
fi

echo -e "${GREEN}CloudPanel versions match: $SRC_VERSION${NC}"

# Step 2: Choose the user and site
echo -e "${YELLOW}Step 2: Selecting user to migrate...${NC}"

# Retrieve user list locally on the source server
USER_LIST=$(clpctl user:list | tail -n +3 | head -n -1)

# Parse the user list and store usernames in an array
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

# Prompt user to select the user by number
read -p "Select a user by entering the corresponding number: " USER_SELECTION
USER_INDEX=$((USER_SELECTION-1))
SITE_USER=${USERNAMES[$USER_INDEX]}

echo -e "${GREEN}You selected: $SITE_USER${NC}"

# Step 3: Check if user exists on destination server
echo -e "${YELLOW}Checking if user $SITE_USER exists on destination server...${NC}"
if sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "id -u $SITE_USER" >/dev/null 2>&1; then
    echo -e "${RED}User $SITE_USER already exists on destination server.${NC}"
    confirm "Do you want to delete this user before proceeding?"
    sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl user:delete --username=$SITE_USER"
    echo -e "${GREEN}User $SITE_USER deleted from destination server.${NC}"
fi

# List available domains for the selected user
echo -e "${YELLOW}Available domains in /home/$SITE_USER/htdocs:${NC}"
ls /home/$SITE_USER/htdocs

read -p "Enter the domain to migrate (e.g., example.com): " DOMAIN

# Step 4: Database Information
echo -e "${YELLOW}Step 4: Collecting database information...${NC}"
read -p "Enter the database name: " DB_NAME
read -p "Enter the database username: " DB_USER
read -sp "Enter the database password: " DB_PASS
echo ""

# Validate source database connection
while ! validate_db $DB_USER $DB_PASS $DB_NAME "localhost"; do
    echo -e "${YELLOW}Re-enter database credentials...${NC}"
    read -p "Enter the database username: " DB_USER
    read -sp "Enter the database password: " DB_PASS
    echo ""
done

# Step 5: Create User and Site on Destination Server
echo -e "${YELLOW}Step 5: Creating user and site on destination server...${NC}"
sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl user:create --username=$SITE_USER --email=${EMAILS[$USER_INDEX]}"
sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl site:create --domain=$DOMAIN --php=8.0 --user=$SITE_USER"

# Step 6: Validate destination database connection
while ! validate_db $DB_USER $DB_PASS $DB_NAME $DEST_SERVER; do
    echo -e "${YELLOW}Re-enter database credentials for the destination server...${NC}"
    read -sp "Re-enter database password: " DB_PASS
    echo ""
done

# Step 7: Export and Transfer Database
echo -e "${YELLOW}Step 7: Exporting and transferring database...${NC}"
mysqldump -u $DB_USER -p$DB_PASS $DB_NAME > /tmp/$DB_NAME.sql
sshpass -p "$DEST_PASS" scp /tmp/$DB_NAME.sql $DEST_USER@$DEST_SERVER:/tmp/

# Step 8: Import Database on New Server
echo -e "${YELLOW}Step 8: Importing database to destination server...${NC}"
sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "clpctl database:create --name=$DB_NAME --user=$DB_USER --password=$DB_PASS"
sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "mysql -u $DB_USER -p$DB_PASS $DB_NAME < /tmp/$DB_NAME.sql"

# Step 9: Rsync Files to New Server
echo -e "${YELLOW}Step 9: Syncing files with rsync...${NC}"
rsync -avz /home/$SITE_USER/htdocs/$DOMAIN $DEST_USER@$DEST_SERVER:/home/$SITE_USER/htdocs/

# Step 10: Copy vHost Configuration from Source to Destination
echo -e "${YELLOW}Step 10: Copying vHost configuration...${NC}"

# Define paths for vHost config files
VHOST_SRC="/etc/nginx/sites-available/$DOMAIN"
VHOST_DEST="/etc/nginx/sites-available/"

# Copy the vHost file from source to destination
sshpass -p "$DEST_PASS" scp $VHOST_SRC $DEST_USER@$DEST_SERVER:$VHOST_DEST

# Reload nginx on destination server
sshpass -p "$DEST_PASS" ssh $DEST_USER@$DEST_SERVER "systemctl reload nginx"

echo -e "${GREEN}vHost configuration copied and nginx reloaded.${NC}"

# Final Step: Remind user about Varnish, Cron Jobs, and DNS
echo -e "${YELLOW}Step 11: Final reminders...${NC}"
if [[ -d "/home/$SITE_USER/.varnish" ]]; then
    echo -e "${YELLOW}Note: Varnish is enabled for this user. Please enable Varnish in the CloudPanel GUI after migration is completed.${NC}"
fi
echo -e "${YELLOW}Ensure Cron Jobs are moved to the new server via CloudPanel GUI.${NC}"
echo -e "${YELLOW}Access the CloudPanel GUI at https://$DEST_SERVER:8443${NC}"
echo -e "${YELLOW}Don't forget to update your DNS to point to the new server!${NC}"

echo -e "${GREEN}Migration completed successfully!${NC}"
