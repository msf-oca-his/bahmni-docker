#!/bin/bash

BAHMNI_DOCKER_ENV_FILE=.env

source ${BAHMNI_DOCKER_ENV_FILE}

# Configuration variables
SOURCE_DIR=${BACKUP_ARTIFACTS_PATH}  # Update this path
BACKUP_SERVER=${BACKUP_SERVER}  # Update with the backup server address
REMOTE_DIR=${BACKUP_REMOTE_DIRECTORY_PATH} # Update with the remote directory path
PASSWORD=${NAS_SERVER_PASSWORD} # Update with the server password
PORT=${BACKUP_SERVER_SSH_PORT}  # Update with the SSH port if different from default (22)

# Step 1: Find the latest folder in the source directory
echo "Finding the latest folder in the source directory..."
latest_folder=$(find "$SOURCE_DIR" -type d -exec stat --format='%Y %n' {} + | sort -n | tail -1 | cut -d' ' -f2-)

if [ -z "$latest_folder" ]; then
  echo "No date folders found in the source directory."
  exit 1
fi

echo "Latest folder: $latest_folder"

# Step 2: Find the latest .sql file in the latest folder
echo "Finding the latest .sql file in the latest folder..."
latest_file=$(find "$latest_folder" -type f -name "*.sql" -printf "%T@ %p\n" | sort -k1,1n | tail -1 | cut -d' ' -f2-)

if [ -z "$latest_file" ]; then
  echo "No .sql files found in the latest folder."
  exit 1
fi

echo "Latest SQL file: $latest_file"

# Step 3: Compress the latest .sql file with a timestamp in the filename
echo "Compressing the latest .sql file..."
current_date=$(date +"%Y-%m-%d")
gzip_latest_file="${latest_file%.*}_$current_date.sql.gz"
gzip -c "$latest_file" > "$gzip_latest_file"

if [ $? -ne 0 ]; then
  echo "Failed to compress the .sql file."
  exit 1
fi

echo "Compressed file: $gzip_latest_file"

# Step 4: Create remote directory on the backup server
echo "Ensuring the remote directory exists on the backup server..."
sshpass -p "$PASSWORD" ssh -p "$PORT" "$BACKUP_SERVER" "mkdir -p $REMOTE_DIR"

if [ $? -ne 0 ]; then
  echo "Failed to create the remote directory on the backup server."
  exit 1
fi

# Step 5: Copy the compressed file to the remote server
echo "Copying the compressed file to the backup server..."
sshpass -p "$PASSWORD" scp -P "$PORT" "$gzip_latest_file" "$BACKUP_SERVER:$REMOTE_DIR"

if [ $? -ne 0 ]; then
  echo "Failed to copy the compressed file to the backup server."
  exit 1
fi

# Step 6: Copy additional directories to the remote server
echo "Copying additional directories to the backup server..."
for folder in clinical_forms configuration_checksums document_images patient_images uploaded-files uploaded_results; do
  local_folder="$SOURCE_DIR/$folder"
  if [ -d "$local_folder" ]; then
    echo "Copying $local_folder to the backup server..."
    sshpass -p "$PASSWORD" scp -P "$PORT" -r "$local_folder" "$BACKUP_SERVER:$REMOTE_DIR"
    if [ $? -ne 0 ]; then
      echo "Failed to copy $local_folder to the backup server."
      exit 1
    fi
  else
    echo "Skipping $local_folder (not found)."
  fi
done

echo "Backup copying completed successfully."
