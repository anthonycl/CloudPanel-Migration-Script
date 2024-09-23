#!/bin/bash

# Color definitions for better output
NC='\033[0m' # No Color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'

# Function to prompt for missing parameters
prompt_for_param() {
    local param_name=$1
    local default_value=$2

    if [ -n "$default_value" ]; then
        read -p "$param_name [$default_value]: " input_value
        echo "${input_value:-$default_value}"
    else
        read -p "$param_name: " input_value
        echo "$input_value"
    fi
}

# Function to add a site based on the site type and JSON data
add_site_from_json() {
    local json_file=$1

    # Parse JSON file to extract necessary data
    local domain_name=$(jq -r '.site[0].domain_name' "$json_file")
    local site_type=$(jq -r '.site[0].site_type' "$json_file")

    echo -e "${YELLOW}Adding site $domain_name of type $site_type...${NC}"

    case $site_type in
        php)
            local php_version=$(jq -r '.site[0].php_version // empty' "$json_file")
            php_version=$(prompt_for_param "Enter PHP version" "$php_version")

            local vhost_template=$(jq -r '.site[0].vhostTemplate // empty' "$json_file")
            vhost_template=$(prompt_for_param "Enter Vhost Template" "$vhost_template")

            local site_user=$(jq -r '.site[0].siteUser // empty' "$json_file")
            site_user=$(prompt_for_param "Enter Site User" "$site_user")

            local site_user_password=$(jq -r '.site[0].siteUserPassword // empty' "$json_file")
            site_user_password=$(prompt_for_param "Enter Site User Password" "$site_user_password")

            clpctl site:add:php --domainName="$domain_name" --phpVersion="$php_version" --vhostTemplate="$vhost_template" --siteUser="$site_user" --siteUserPassword="$site_user_password"
            ;;
        nodejs)
            local nodejs_version=$(jq -r '.site[0].nodejsVersion // empty' "$json_file")
            nodejs_version=$(prompt_for_param "Enter Node.js Version" "$nodejs_version")

            local app_port=$(jq -r '.site[0].appPort // empty' "$json_file")
            app_port=$(prompt_for_param "Enter App Port" "$app_port")

            local site_user=$(jq -r '.site[0].siteUser // empty' "$json_file")
            site_user=$(prompt_for_param "Enter Site User" "$site_user")

            local site_user_password=$(jq -r '.site[0].siteUserPassword // empty' "$json_file")
            site_user_password=$(prompt_for_param "Enter Site User Password" "$site_user_password")

            clpctl site:add:nodejs --domainName="$domain_name" --nodejsVersion="$nodejs_version" --appPort="$app_port" --siteUser="$site_user" --siteUserPassword="$site_user_password"
            ;;
        static)
            local site_user=$(jq -r '.site[0].siteUser // empty' "$json_file")
            site_user=$(prompt_for_param "Enter Site User" "$site_user")

            local site_user_password=$(jq -r '.site[0].siteUserPassword // empty' "$json_file")
            site_user_password=$(prompt_for_param "Enter Site User Password" "$site_user_password")

            clpctl site:add:static --domainName="$domain_name" --siteUser="$site_user" --siteUserPassword="$site_user_password"
            ;;
        python)
            local python_version=$(jq -r '.site[0].python_version // empty' "$json_file")
            python_version=$(prompt_for_param "Enter Python Version" "$python_version")

            local app_port=$(jq -r '.site[0].appPort // empty' "$json_file")
            app_port=$(prompt_for_param "Enter App Port" "$app_port")

            local site_user=$(jq -r '.site[0].siteUser // empty' "$json_file")
            site_user=$(prompt_for_param "Enter Site User" "$site_user")

            local site_user_password=$(jq -r '.site[0].siteUserPassword // empty' "$json_file")
            site_user_password=$(prompt_for_param "Enter Site User Password" "$site_user_password")

            clpctl site:add:python --domainName="$domain_name" --pythonVersion="$python_version" --appPort="$app_port" --siteUser="$site_user" --siteUserPassword="$site_user_password"
            ;;
        *)
            echo -e "${RED}Unsupported site type: $site_type${NC}"
            exit 1
            ;;
    esac
}

# Function to handle backup and restore commands
backup_or_restore() {
    local action=$1
    local target=$2

    case $action in
        backup)
            if [ "$target" == "--all" ]; then
                # Loop through all sites and create backups
                for domain in $(clpctl site:list | awk '{print $2}' | grep -v Domain); do
                    echo -e "${YELLOW}Backing up site $domain...${NC}"
                    # Correctly calling settingsFetcher.php to generate JSON for each site
                    php settingsFetcher.php --site "$domain" --backup
                done
            elif [[ "$target" == --site=* ]]; then
                local domain="${target#*=}"
                echo -e "${YELLOW}Backing up site $domain...${NC}"
                # Correctly calling settingsFetcher.php to generate JSON for a single site
                php settingsFetcher.php --site "$domain" --backup
            else
                echo -e "${RED}Invalid backup option${NC}"
            fi
            ;;
        restore)
            if [ "$target" == "--all" ]; then
                # Loop through all JSON files in backups directory
                for json_file in /home/backups/*.json; do
                    echo -e "${YELLOW}Restoring from $json_file...${NC}"
                    add_site_from_json "$json_file"
                done
            elif [[ "$target" == --site=* ]]; then
                local domain="${target#*=}"
                local json_file="/home/backups/$domain.json"
                if [ -f "$json_file" ]; then
                    echo -e "${YELLOW}Restoring site $domain from $json_file...${NC}"
                    add_site_from_json "$json_file"
                else
                    echo -e "${RED}No backup found for $domain.${NC}"
                fi
            else
                echo -e "${RED}Invalid restore option${NC}"
            fi
            ;;
        *)
            echo -e "${RED}Invalid action. Use 'backup' or 'restore'.${NC}"
            ;;
    esac
}

# Main entry point
if [ "$#" -ne 2 ]; then
    echo -e "${RED}Usage: $0 {backup|restore} --all or --site=example.com${NC}"
    exit 1
fi

action=$1
target=$2

# Check if the backups site exists, and if not, create it
if ! clpctl site:list | grep -q "backups.local"; then
    echo -e "${YELLOW}Creating backups site...${NC}"
    secure_password=$(openssl rand -base64 12)
    clpctl site:add:static --domainName="backups.local" --siteUser="backups" --siteUserPassword="$secure_password"
fi

# Ensure the backups directory exists
BACKUP_DIR="/home/backups"
mkdir -p "$BACKUP_DIR"

# Execute the requested action
backup_or_restore "$action" "$target"
