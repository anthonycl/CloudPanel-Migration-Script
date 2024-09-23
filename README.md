# 🚀 CloudPanel Migration Script

Welcome to the **CloudPanel Migration Script**! This script simplifies the migration of websites from one CloudPanel installation to another. It also includes a **backup and restore utility** to handle individual or bulk backups of your sites and server settings. 🛠️

## ✨ Features
- Validates SSH and database connections.
- Manages users, sites, databases, and vHost configurations.
- Offers reminders for **Varnish**, **Cron Jobs**, and **DNS updates** post-migration.
- Automated **backup and restore** process for sites and server data.
- Easy-to-use with color-coded console output for clarity.

---

## 📦 Prerequisites
- **Linux-based OS** with `bash`.
- **CloudPanel** installed on both source and destination servers.
- **SSH access** to the destination server.
- **MySQL/MariaDB** client tools installed.
- **`sshpass`** installed on both source and destination servers.
- **PHP** with `json` and `openssl` extensions installed.

### Install `sshpass`:
For password authentication, ensure you have `sshpass` installed. Here are the install commands based on your OS:

#### For Debian/Ubuntu:
```bash
sudo apt-get update
sudo apt-get install sshpass
```

#### For CentOS/RHEL:
```bash
sudo yum install epel-release
sudo yum install sshpass
```

#### For macOS (Homebrew):
```bash
brew install hudochenkov/sshpass/sshpass
```

---

## 🛠️ Installation

### Quick Setup:

**One-liner** to download, set permissions, and execute the migration script:
```bash
git clone https://github.com/anthonycl/CloudPanel-Migration-Script.git && cd CloudPanel-Migration-Script/ && chmod +x migrate.sh && sudo ./migrate.sh
```

### Step-by-Step:
1. **Clone the Repository**:
   ```bash
   git clone https://github.com/anthonycl/CloudPanel-Migration-Script.git
   cd CloudPanel-Migration-Script
   ```

   Alternatively, download using `wget`:
   ```bash
   wget https://github.com/anthonycl/CloudPanel-Migration-Script/archive/refs/heads/main.zip
   unzip main.zip
   cd CloudPanel-Migration-Script-main
   ```

2. **Set Permissions** (if necessary):
   ```bash
   chmod +x migrate.sh
   ```

3. **Run the Script as Root**:
   ```bash
   sudo ./migrate.sh
   ```

---

## 💾 Backup and Restore Script

The `backup_and_restore.sh` script provides an automated way to back up or restore all sites or individual sites on CloudPanel.

### Backup All Sites:
```bash
./backup_and_restore.sh backup --all
```

### Backup a Specific Site:
```bash
./backup_and_restore.sh backup --site=example.com
```

### Restore All Sites:
```bash
./backup_and_restore.sh restore --all
```

### Restore a Specific Site:
```bash
./backup_and_restore.sh restore --site=example.com
```

---

## 📝 `settingsFetcher.php`

This script fetches site and server configurations and stores them in JSON format for backup purposes. Does not need to be called seperately outside of bash scripts, but you can if you want to.

### Usage:

1. **To Backup Site Data:**
```php
<?php
require 'settingsFetcher.php';
$settingsFetcher = new \SiteData\SettingsFetcher();
$settingsFetcher->saveSiteDataAsJSON('example.com');
```

2. **To Backup Server Data:**
```php
<?php
require 'settingsFetcher.php';
$settingsFetcher = new \SiteData\SettingsFetcher();
$settingsFetcher->saveServerDataAsJSON();
```

The data will be saved as `siteName.json` or `server.json` in the `backups` directory.

---

## 🌟 Acknowledgments
- Special thanks to [13th-tempest](https://github.com/13th-tempest) for contributions to the backup and restore script!

---

## ⚖️ License
This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.