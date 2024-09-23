# CloudPanel Migration Script

This script facilitates the migration of websites from one CloudPanel installation to another. It handles user, site, database, and vHost configurations, providing a smooth and efficient transition process.

## Features
- Validates SSH and database connections.
- Supports user and site management, including handling existing users/sites.
- Provides reminders for Varnish, Cron Jobs, and DNS changes post-migration.
- User-friendly console output with color coding.

## Prerequisites
- **Linux-based OS** with access to `bash`.
- **CloudPanel** installed on both source and destination servers.
- **SSH access** to the destination server.
- **MySQL/MariaDB** client tools installed.
- **sshpass** installed on both source and destination servers.

The error you're encountering indicates that the `sshpass` utility is not installed on your system. `sshpass` is often used for non-interactive SSH password authentication.

To install `sshpass`, you can use the following commands based on your operating system:

### For Debian/Ubuntu:
```bash
sudo apt-get update
sudo apt-get install sshpass
```

### For CentOS/RHEL:
```bash
sudo yum install epel-release
sudo yum install sshpass
```

### For macOS (using Homebrew):
```bash
brew install hudochenkov/sshpass/sshpass
```

After installing `sshpass`, try running your script again. If you encounter any further issues, feel free to ask!

## Installation

**Here’s a one-liner that uses `wget`, sets permissions, and runs the script: (Recommended)**

```bash
wget https://raw.githubusercontent.com/anthonycl/CloudPanel-Migration-Script/refs/heads/main/migrate.sh && chmod +x migrate.sh && sudo ./migrate.sh
```

You can paste this line directly into your terminal to download, set permissions, and execute the script or follow the instructions below:

1. **Clone the Repository**:
   You can clone the repository using `git`:
   ```bash
   git clone https://github.com/anthonycl/CloudPanel-Migration-Script.git
   cd CloudPanel-Migration-Script
   ```

   Alternatively, you can use `wget` to download it directly:
   ```bash
   wget https://github.com/anthonycl/CloudPanel-Migration-Script/archive/refs/heads/main.zip
   unzip main.zip
   cd CloudPanel-Migration-Script-main
   ```

2. **Set Permissions**:
   Ensure the script is executable:
   ```bash
   chmod +x migrate.sh
   ```

3. **Execute the Script as Root**:
   It is essential to run the script as the root user to ensure it has the necessary permissions:
   ```bash
   sudo ./migrate.sh
   ```

## Usage
Follow the on-screen prompts to complete the migration process. The script will guide you through selecting the user, domain, database information, and handling file transfers.

## Notes
- Make sure to back up your data before performing any migration.
- Review the output carefully for any required actions post-migration.

## License
This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments
- Thanks to the CloudPanel community for their support and contributions.