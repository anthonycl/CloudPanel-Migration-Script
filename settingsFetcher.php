<?php

// NOTE: Credits to the original author of the logic at https://github.com/13th-tempest

namespace SiteData;

use PDO;
use PDOException;

class SettingsFetcher {

    private $pdo;

    public function __construct() {
        // Initialize the PDO connection to the database
        $this->pdo = new PDO($_ENV["DATABASE_URL"] ?? 'sqlite:db.sq3');
        $this->pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    }

    // Fetch server data and save as JSON
    public function fetchServerData() {
        $queries = [
            'config' => "SELECT * FROM config",
            'database_server' => "SELECT * FROM database_server",
            'firewall_rule' => "SELECT * FROM firewall_rule",
            'vhost_template' => "SELECT * FROM vhost_template"
        ];

        $data = [];

        // Execute each query and store results
        foreach ($queries as $tableName => $query) {
            $stmt = $this->pdo->prepare($query);
            $stmt->execute();

            // Fetch table data and filter out NULL values
            $tableData = $stmt->fetchAll(PDO::FETCH_ASSOC);
            if ($tableData) {
                $filteredTableData = array_map(function ($row) {
                    return array_filter($row, function ($value) {
                        return $value !== null;
                    });
                }, $tableData);

                // Store the data under its table name
                $data[$tableName] = $filteredTableData;
            }
        }
        return $data;
    }

    // Fetch site data for a specific domain name and save as JSON
    public function fetchSiteData($domainName) {
        function sqlQuery($table, $keyInTable, $keyInSite, $joinTable = null, $joinTableKey = null, $joinSiteKey = null) {
            $query = "
                SELECT t.* 
                FROM $table t 
                JOIN site s 
                ON t.$keyInTable = s.$keyInSite 
                WHERE s.domain_name = :domainName";

            if ($joinTable != null) {
                $query = "
                    SELECT t.* 
                    FROM $table t 
                    JOIN $joinTable jt 
                    ON t.$keyInTable = jt.$joinTableKey 
                    JOIN site s 
                    ON jt.$joinSiteKey = s.$keyInSite 
                    WHERE s.domain_name = :domainName";
            }

            return [$table => $query];
        }

        $queries = [
            'site' => "SELECT * FROM site WHERE domain_name = :domainName"
        ];

        // Add all relevant tables to be fetched
        $queries += sqlQuery('basic_auth', 'id', 'basic_auth_id');
        $queries += sqlQuery('blocked_bot', 'site_id', 'id');
        $queries += sqlQuery('blocked_ip', 'site_id', 'id');
        $queries += sqlQuery('certificate', 'id', 'certificate_id');
        $queries += sqlQuery('cron_job', 'site_id', 'id');
        $queries += sqlQuery('database', 'site_id', 'id');
        $queries += sqlQuery('database_user', 'database_id', 'id', 'database', 'id', 'site_id');
        $queries += sqlQuery('ftp_user', 'site_id', 'id');
        $queries += sqlQuery('nodejs_settings', 'id', 'nodejs_settings_id');
        $queries += sqlQuery('php_settings', 'id', 'php_settings_id');
        $queries += sqlQuery('python_settings', 'id', 'python_settings_id');
        $queries += sqlQuery('user', 'id', 'id', 'user_sites', 'user_id', 'site_id');
        $queries += sqlQuery('ssh_user', 'site_id', 'id');

        $data = [];

        // Include environment variables
        $envVars = ['APP_ENV', 'APP_DEBUG', 'APP_SECRET', 'APP_VERSION', 'DATABASE_URL'];
        foreach ($envVars as $envVar) {
            if (isset($_ENV[$envVar])) {
                $data[$envVar] = $_ENV[$envVar];
            }
        }

        // Execute each query and store the data
        foreach ($queries as $tableName => $query) {
            $stmt = $this->pdo->prepare($query);
            $stmt->bindParam(':domainName', $domainName);
            $stmt->execute();

            $tableData = $stmt->fetchAll(PDO::FETCH_ASSOC);

            if ($tableData) {
                $filteredTableData = array_map(function ($row) {
                    return array_filter($row, function ($value) {
                        return $value !== null;
                    });
                }, $tableData);

                $data[$tableName] = $filteredTableData;
            }
        }

        return $data;
    }

    // Save site data as JSON
    public function saveSiteDataAsJSON($domainName) {
        try {
            $data = $this->fetchSiteData($domainName);
            $jsonData = json_encode($data, JSON_PRETTY_PRINT);
            $jsonFileName = "$domainName.json";
            file_put_contents($jsonFileName, $jsonData);

            return "Data saved to $jsonFileName successfully.";
        } catch (PDOException $e) {
            return "Database error: " . $e->getMessage();
        }
    }

    // Save server data as JSON
    public function saveServerDataAsJSON() {
        try {
            $data = $this->fetchServerData();
            $jsonData = json_encode($data, JSON_PRETTY_PRINT);
            $jsonFileName = "server.json";
            file_put_contents($jsonFileName, $jsonData);

            return "Data saved to $jsonFileName successfully.";
        } catch (PDOException $e) {
            return "Database error: " . $e->getMessage();
        }
    }
}

// Handle command-line arguments
$options = getopt("", ["site:", "backup"]);

if (!isset($options['site'])) {
    echo "Error: No site specified. Use --site=example.com to specify the site domain.\n";
    exit(1);
}

$siteDomain = $options['site'];
$isBackup = isset($options['backup']);

// Initialize the SettingsFetcher class
$settingsFetcher = new SettingsFetcher();

if ($isBackup) {
    // Create a backup JSON for the specified site
    echo $settingsFetcher->saveSiteDataAsJSON($siteDomain);
} else {
    // Output settings data to the console
    $siteData = $settingsFetcher->fetchSiteData($siteDomain);
    echo json_encode($siteData, JSON_PRETTY_PRINT);
}