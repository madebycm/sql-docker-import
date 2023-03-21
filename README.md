# MySQL Database Importer for Docker Containers

This script helps you to easily import an SQL file into a MySQL database running inside a Docker container. The script automatically detects appropriate containers, lists available MySQL databases, empties the selected database, imports the latest SQL file from the working directory, and verifies the import.

## Prerequisites

- Docker installed and running
- A running MySQL/MariaDB container
- SQL file(s) to import

## Usage

1. Download or copy the script to your local machine.
2. Make sure the script is executable:

```bash
chmod +x cmsql.sh
```

3. Run the script
```./cmsql.sh```

## Tips

- The script tries to find appropriate containers by searching for names containing "mysql", "db", or "mariadb".
- It ignores system databases such as information_schema, mysql, performance_schema, and sys.
- You can press Enter instead of typing "1" when there's only one result for containers, databases, or SQL files.
- Pressing Enter works as "y" when confirming the SQL file.

## Pitfalls

- Make sure to run the script in the directory containing the SQL files to import.
- The script assumes that you have permission to access and modify the databases in the container.
- The script is configured to work with MySQL and MariaDB databases. Other database systems may require modifications to the script.

### Disclaimer

This script is provided "as-is" with no warranty. Always ensure you have a backup of your data before running any script that modifies databases.
