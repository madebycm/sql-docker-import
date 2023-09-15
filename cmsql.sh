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
MYSQL_PASSWORDS=("123")

# Type 'cmsql -r' to remote dump before importing
# Highly recommend to set up a dedicated read only user for this

# REQUIRES mysqldump
# (macos: brew install mysql-client)
# (ubuntu: sudo apt-get install mysql-client)
# (windows: https://dev.mysql.com/doc/refman/8.0/en/mysql-installer.html)

REMOTE_SERVER=$cmsql_REMOTE_IP
REMOTE_PASSWORD=$cmsql_REMOTE_PW
REMOTE_USER=$cmsql_REMOTE_USER
REMOTE_DATABASE=$cmsql_REMOTE_DB

# Export these in .zprofile or .bash_profile

# export cmsql_REMOTE_IP=1.2.3.4
# export cmsql_REMOTE_PW=123
# export cmsql_REMOTE_USER=myuser
# export cmsql_REMOTE_DB=mydatabae

if [[ $1 == "-r" ]]; then

    echo "Dumping .sql file from remote server..."

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

for i in "${!MYSQL_USERS[@]}"; do
    MYSQL_USER="${MYSQL_USERS[$i]}"
    MYSQL_PASSWORD="${MYSQL_PASSWORDS[$i]}"
done


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
    echo "Do you want to use this file? (y/n, default is y)"
    read answer
    
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
docker exec -i -e MYSQL_PWD="$MYSQL_PASSWORD" "$selected_container" mysql -u"$MYSQL_USER" "$selected_database" <"$latest_sql_file"

# Verify import and show success message
echo "Import successful! $latest_sql_file has been imported into $selected_database in the container $selected_container using user $MYSQL_USER."
