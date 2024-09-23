<?php

// NOTE: Credits to the original author of the logic at https://github.com/13th-tempest

namespace SiteData;

use PDO;
use PDOException;

class SettingsFetcher
{
  private $pdo;

  public function __construct()
  {
    // Connect to the SQLite database
    $this->pdo = new PDO($_ENV["DATABASE_URL"] ?? 'sqlite:db.sq3');
    $this->pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
  }

  // Fetch server data from multiple tables
  public function fetchServerData()
  {
    $queries = [
      'config' => "SELECT * FROM config",
      'database_server' => "SELECT * FROM database_server",
      'firewall_rule' => "SELECT * FROM firewall_rule",
      'vhost_template' => "SELECT * FROM vhost_template"
    ];

    $data = [];

    foreach ($queries as $tableName => $query) {
      $stmt = $this->pdo->prepare($query);
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

  // Fetch specific site data based on the domain name
  public function fetchSiteData($domainName)
  {
    function sqlQuery($table, $keyInTable, $keyInSite, $joinTable = null, $joinTableKey = null, $joinSiteKey = null)
    {
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

    // Queries for the given site domain
    $queries = [
      'site' => "SELECT * FROM site WHERE domain_name = :domainName"
    ];
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

  // Save the fetched site data as JSON
  public function saveSiteDataAsJSON($domainName)
  {
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

  // Save the server data as JSON
  public function saveServerDataAsJSON()
  {
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
