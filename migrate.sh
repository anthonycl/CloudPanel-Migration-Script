#!/bin/bash

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print notices
function notice {
    echo -e "${YELLOW}*** $1 ***${NC}"
}

# Function to check SSH connection
check_ssh_connection() {
    local user="$1"
    local server="$2"
    local method="$3"
    local key="$4"
    
    if [[ "$method" == "password" ]]; then
        sshpass -p "$DEST_PASS" ssh -o StrictHostKeyChecking=no "$user@$server" "exit" &> /dev/null
    else
        ssh -i "$key" -o StrictHostKeyChecking=no "$user@$server" "exit" &> /dev/null
    fi

    return $?
}

# Prompt for SSH credentials
read -p "Enter SSH username for destination server: " DEST_USER
read -p "Enter destination server IP or hostname: " DEST_SERVER

# Initial SSH method to password
SSH_METHOD="password"

# Prompt for SSH password
read -sp "Enter SSH password for $DEST_USER: (or enter to skip or use publickey auth)" DEST_PASS
echo ""

# Check initial SSH connection
if ! check_ssh_connection "$DEST_USER" "$DEST_SERVER" "$SSH_METHOD"; then
    notice "Password authentication failed or not allowed."

    # Check for default SSH public key
    DEFAULT_KEY="$HOME/.ssh/id_rsa"
    if [[ -f "$DEFAULT_KEY" ]]; then
        echo "Default SSH key found at $DEFAULT_KEY."
        read -p "Do you want to use the default key? (y/n): " USE_DEFAULT_KEY
    else
        echo "No default SSH key found."
        USE_DEFAULT_KEY="n"
    fi

    if [[ "$USE_DEFAULT_KEY" == "y" ]]; then
        SSH_KEY="$DEFAULT_KEY"
    else
        read -p "Enter the path to your SSH public key: " SSH_KEY
    fi

    # Confirm SSH key
    if [[ -f "$SSH_KEY" ]]; then
        echo "Using SSH key at $SSH_KEY."
        SSH_METHOD="publickey"
    else
        echo -e "${RED}Invalid SSH key path. Exiting.${NC}"
        exit 1
    fi
fi

# Final SSH connection check
if ! check_ssh_connection "$DEST_USER" "$DEST_SERVER" "$SSH_METHOD" "$SSH_KEY"; then
    echo -e "${RED}SSH connection failed with the chosen method. Exiting.${NC}"
    exit 1
fi

echo -e "${GREEN}SSH connection established successfully using $SSH_METHOD.${NC}"

# Step 1: Ensure CloudPanel versions match
echo -e "${YELLOW}Checking CloudPanel versions...${NC}"
SRC_VERSION=$(clpctl --version)
DEST_VERSION=$(sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "clpctl --version")

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
    # Skip lines that do not contain user information
    if [[ "$line" =~ ^\| ]]; then
        # Extract the username and email using awk
        USERNAME=$(echo "$line" | awk '{print $2}')
        EMAIL=$(echo "$line" | awk '{print $6}')
        USERNAMES+=("$USERNAME")
        EMAILS+=("$EMAIL")
        echo "$INDEX) $USERNAME ($EMAIL)"
        ((INDEX++))
    fi
done <<< "$USER_LIST"

# Check if no users were found
if [[ ${#USERNAMES[@]} -eq 0 ]]; then
    echo -e "${RED}No users found on the source server.${NC}"
    exit 1
fi

# Prompt user to select the user by number
read -p "Select a user by entering the corresponding number: " USER_SELECTION
USER_INDEX=$((USER_SELECTION-1))

# Validate user selection
if [[ $USER_INDEX -lt 0 || $USER_INDEX -ge ${#USERNAMES[@]} ]]; then
    echo -e "${RED}Invalid selection.${NC}"
    exit 1
fi

SITE_USER=${USERNAMES[$USER_INDEX]}

echo -e "${GREEN}You selected: $SITE_USER${NC}"

# Step 3: Check if user exists on destination server
echo -e "${YELLOW}Checking if user $SITE_USER exists on destination server...${NC}"
if sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "id -u $SITE_USER" >/dev/null 2>&1; then
    echo -e "${RED}User $SITE_USER already exists on destination server.${NC}"
    read -p "Do you want to delete this user before proceeding? (y/n): " CONFIRM_DELETE
    if [[ "$CONFIRM_DELETE" == "y" ]]; then
        sshpass -p "$DEST_PASS" ssh "$DEST_USER@$DEST_SERVER" "clpctl user:delete --username=$SITE_USER"
        echo -e "${GREEN}User $SITE_USER deleted from destination server.${NC}"
    else
        echo -e "${RED}Migration aborted due to existing user.${NC}"
        exit 1
    fi
fi

# Step 4: List available domains for the selected user
echo -e "${YELLOW}Available domains in /home/$SITE_USER/htdocs:${NC}"
ssh "$SOURCE_USER@$DEST_SERVER" "ls /home/$SITE_USER/htdocs"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to list domains in /home/$SITE_USER/htdocs.${NC}"
    exit 1
fi

# Step 5: Export the database from the source server
ssh "$SOURCE_USER@$DEST_SERVER" "mysqldump -u $DB_USER -p'$DB_PASS' $DB_NAME > /tmp/$DB_NAME.sql"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to export database $DB_NAME from the source server.${NC}"
    exit 1
fi

# Step 6: Copy files using rsync
rsync -avz -e "ssh -o StrictHostKeyChecking=no" "/home/$SOURCE_USER/htdocs/$DOMAIN_NAME/" "$DEST_USER@$DEST_SERVER:/home/$DEST_USER/htdocs/$DOMAIN_NAME/"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to transfer files for $DOMAIN_NAME.${NC}"
    exit 1
fi

# Step 7: Create user on the destination server
ssh "$DEST_USER@$DEST_SERVER" "clpctl user:create --username=$SITE_USER --password='$DEST_PASS'"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to create user $SITE_USER on the destination server.${NC}"
    exit 1
fi

# Step 8: Create site on the destination server
ssh "$DEST_USER@$DEST_SERVER" "clpctl site:create --domain=$DOMAIN_NAME --user=$SITE_USER"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to create site $DOMAIN_NAME on the destination server.${NC}"
    exit 1
fi

# Step 9: Import the database on the destination server
ssh "$DEST_USER@$DEST_SERVER" "mysql -u $DB_USER -p'$DB_PASS' $DB_NAME < /tmp/$DB_NAME.sql"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to import database $DB_NAME on the destination server.${NC}"
    exit 1
fi

# Step 10: Clean up temporary database file
ssh "$SOURCE_USER@$DEST_SERVER" "rm /tmp/$DB_NAME.sql"

# Step 11: Copy vhost configuration
VHOST_SOURCE="/etc/nginx/sites-available/$DOMAIN_NAME"
VHOST_DEST="/etc/nginx/sites-available/$DOMAIN_NAME"
ssh "$SOURCE_USER@$DEST_SERVER" "cp $VHOST_SOURCE $VHOST_DEST"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to copy vhost configuration.${NC}"
    exit 1
fi

# Step 12: Reload Nginx on the destination server
ssh "$DEST_USER@$DEST_SERVER" "sudo systemctl reload nginx"
if [[ $? -ne 0 ]]; then
    echo -e "${RED}Failed to reload Nginx on the destination server.${NC}"
    exit 1
fi

# Step 13: Check for Varnish configuration
if ssh "$SOURCE_USER@$DEST_SERVER" "[ -d /home/$SOURCE_USER/.varnish ]"; then
    echo -e "${YELLOW}Remember to enable Varnish in the CloudPanel GUI after migration.${NC}"
fi

# Step 14: Reminder to move Cron Jobs
echo -e "${YELLOW}Don't forget to move Cron Jobs in the CloudPanel GUI on the new server.${NC}"
echo -e "${YELLOW}Also, update your DNS configuration to point to the new server.${NC}"

echo -e "${GREEN}Migration completed successfully!${NC}"
