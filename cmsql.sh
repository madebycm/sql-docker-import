#!/bin/bash

# ---------------------------
# BASIC USAGE FOR THIS SCRIPT
# ---------------------------

# This script is intended to be used with Docker containers running MySQL.
# It will automatically find the latest .sql file in the current directory,
# and import it to a database in found container. 

# Create alias 'csmsql' to this shell script
# 'cmsql' to import the latest .sql file in the current directory

MYSQL_USERS=("root")
DEFAULT_PASSWORD="123"

# Get the directory where the script is located
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
PW_CACHE_FILE="$SCRIPT_DIR/pw-cache.txt"

# Type 'cmsql -r' to remote dump before importing
# Type 'cmsql -p <password>' to specify a custom password
# Type 'cmsql -c' to clear the password cache
# Passwords are cached in pw-cache.txt in the script's directory for future use
# Highly recommend to set up a dedicated read only user for this

# REQUIRES mysqldump
# (macos: brew install mysql-client)
# (ubuntu: sudo apt-get install mysql-client)
# (windows: https://dev.mysql.com/doc/refman/8.0/en/mysql-installer.html)

# Export these in .zprofile or .bash_profile to use -r

# export cmsql_REMOTE_IP=1.2.3.4
# export cmsql_REMOTE_PW=123
# export cmsql_REMOTE_USER=myuser
# export cmsql_REMOTE_DB=mydatabae

REMOTE_SERVER=$cmsql_REMOTE_IP
REMOTE_PASSWORD=$cmsql_REMOTE_PW
REMOTE_USER=$cmsql_REMOTE_USER
REMOTE_DATABASE=$cmsql_REMOTE_DB

skip_user_confirmation=0
custom_password=""
clear_cache=0

# Function to get password from cache
get_cached_password() {
    local container=$1
    if [ -f "$PW_CACHE_FILE" ]; then
        grep "^$container:" "$PW_CACHE_FILE" | cut -d':' -f2
    fi
}

# Function to save password to cache
save_password_to_cache() {
    local container=$1
    local password=$2
    if [ -f "$PW_CACHE_FILE" ]; then
        sed -i.bak "/^$container:/d" "$PW_CACHE_FILE"
    fi
    echo "$container:$password" >> "$PW_CACHE_FILE"
}

# Function to clear password cache
clear_password_cache() {
    if [ -f "$PW_CACHE_FILE" ]; then
        rm "$PW_CACHE_FILE"
        echo "Password cache cleared."
    else
        echo "No password cache file found."
    fi
}

# Parse command line arguments
while getopts "rp:cclean" opt; do
  case $opt in
    r)
      skip_user_confirmation=1
      ;;
    p)
      custom_password="$OPTARG"
      ;;
    c)
      clear_cache=1
      ;;
    clean)
      echo "Listing all .sql files found:"
      ls -l *.sql
      echo
      echo "Please confirm the removal of all .sql files in the folder. (y/n)"
      
      read confirmation
      
      if [ "$confirmation" = "y" ]; then
          echo "Removing all .sql files in folder..."
          rm *.sql
          echo "SQL files cleaned up."
          exit 0
      else
          echo "Removal cancelled."
          exit 0
      fi
      ;;
    \?)
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
  esac
done

if [ $clear_cache -eq 1 ]; then
    clear_password_cache
    exit 0
fi

if [ $skip_user_confirmation -eq 1 ]; then
    echo "Dumping .sql file from remote server..."

    if ! command -v mysqldump &> /dev/null
    then
        echo "mysqldump could not be found. Please install mysqldump. (mysql-client@brew)"
        exit 1
    fi

    if ! mysql -h $REMOTE_SERVER -u $REMOTE_USER -p$REMOTE_PASSWORD -e "SELECT 1" >/dev/null 2>&1; then
        echo "Connection to remote server failed. Please check your credentials."
        exit 1
    fi
    
    mysqldump -h $REMOTE_SERVER -u $REMOTE_USER -p$REMOTE_PASSWORD $REMOTE_DATABASE > dump_.sql
    date=$(date +"%Y%m%d")
    mv dump_.sql dump_auto_$date.sql
    echo "Dump completed."
fi

# Find appropriate docker container
container_ids=$(docker ps --format '{{.Names}}' | grep -E 'mysql|db|mariadb')
if [ -z "$container_ids" ]; then
    echo "No appropriate containers found. Listing all available containers:"
    container_ids=$(docker ps --format '{{.Names}}')
    echo "$container_ids"
    echo
fi

echo "Containers:"
echo "$container_ids"
echo

selected_container=""
while true; do
    if [ "$(echo "$container_ids" | wc -l)" -eq 1 ]; then
        selected_container=$(echo "$container_ids" | head -n 1)
        break
    else
        echo "Please enter the number of the container you want to use:"
        select container in $container_ids; do
            selected_container="$container"
            break
        done
    fi
    
    if [ -n "$selected_container" ]; then
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

# Check for cached password
cached_password=$(get_cached_password "$selected_container")
if [ -n "$cached_password" ] && [ -z "$custom_password" ]; then
    MYSQL_PASSWORD="$cached_password"
    echo "Using cached password for $selected_container"
elif [ -n "$custom_password" ]; then
    MYSQL_PASSWORD="$custom_password"
    save_password_to_cache "$selected_container" "$custom_password"
    echo "Password saved to cache for $selected_container"
else
    echo "No cached password found for $selected_container."
    echo "Please enter the password for $selected_container (or press Enter to use default):"
    read -s input_password
    if [ -n "$input_password" ]; then
        MYSQL_PASSWORD="$input_password"
        save_password_to_cache "$selected_container" "$input_password"
        echo "Password saved to cache for $selected_container"
    else
        MYSQL_PASSWORD="$DEFAULT_PASSWORD"
        echo "Using default password"
    fi
fi

MYSQL_USER="${MYSQL_USERS[0]}"

# Test the connection
if ! docker exec -i -e MYSQL_PWD="$MYSQL_PASSWORD" "$selected_container" mysql -u"$MYSQL_USER" -e "SELECT 1" >/dev/null 2>&1; then
    echo "Connection failed. The password might be incorrect."
    echo "Please enter the correct password for $selected_container:"
    read -s correct_password
    MYSQL_PASSWORD="$correct_password"
    save_password_to_cache "$selected_container" "$correct_password"
    echo "Password updated and saved to cache for $selected_container"
fi

# Search for all MySQL databases in the selected container
databases=$(docker exec -i -e MYSQL_PWD="$MYSQL_PASSWORD" "$selected_container" mysql -u"$MYSQL_USER" --skip-column-names -e 'SHOW DATABASES;' | grep -v -E 'Database|information_schema|mysql|performance_schema|sys')
if [ -z "$databases" ]; then
    echo "No databases found in the selected container."
    exit 1
fi

echo "Databases available in the selected container:"
echo "$databases"
echo

# Prompt user to select a database
selected_database=""
while true; do
    if [ "$(echo "$databases" | wc -l)" -eq 1 ]; then
        selected_database=$(echo "$databases" | head -n 1)
        break
    else
        echo "Please enter the number of the database you want to use:"
        select database in $databases; do
            selected_database="$database"
            break
        done
    fi
    
    if [ -n "$selected_database" ]; then
        break
    else
        echo "Invalid selection. Please try again."
    fi
done

# Empty the selected database
docker exec -i -e MYSQL_PWD="$MYSQL_PASSWORD" "$selected_container" mysql -u"$MYSQL_USER" -e "DROP DATABASE $selected_database; CREATE DATABASE $selected_database;"

# Find the latest SQL file in the working directory
latest_sql_file=$(ls -t *.sql 2>/dev/null | head -n1)
last_modified_date=$(date -r "$latest_sql_file" +"%d.%m.%Y")
today=$(date +"%d.%m.%Y")

if [ "$last_modified_date" = "$today" ]; then
    last_modified_date=$(date -r "$latest_sql_file" +"%H:%M:%S (today)")
else
    last_modified_date=$(date -r "$latest_sql_file" +"%H:%M:%S (%d.%m.%Y)")
fi

if [ -z "$latest_sql_file" ]; then
    echo "No SQL files found in the current directory."
    exit 1
fi

while true; do
    echo "Latest SQL file found: $latest_sql_file (Last modified: $last_modified_date)"

    if [ "$skip_user_confirmation" -eq 1 ]; then  # Check if user confirmation should be skipped
        echo "Dump complete, now importing..."
        answer="y"
    else
        echo "Do you want to use this file? (y/n, default is y)"
        read answer
    fi
    
    if [ "$answer" = "y" ] || [ -z "$answer" ]; then
        break
    elif [ "$answer" = "n" ]; then
        sql_files=$(ls -t *.sql)
        if [ "$(echo "$sql_files" | wc -l)" -eq 1 ]; then
            latest_sql_file=$(echo "$sql_files" | head -n 1)
            break
        else
            echo "Please select an SQL file:"
            select file in $sql_files; do
                latest_sql_file="$file"
                break
            done
            break
        fi
    else
        echo "Invalid input. Please enter 'y' or 'n'."
    fi
done

echo "Importing $latest_sql_file to $selected_database"

# Import the SQL file to the selected database
docker exec -i -e MYSQL_PWD="$MYSQL_PASSWORD" "$selected_container" mysql -u"$MYSQL_USER" "$selected_database" < "$latest_sql_file"

# Verify import and show success message
echo "Import successful! $latest_sql_file has been imported into $selected_database in the container $selected_container using user $MYSQL_USER."