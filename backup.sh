#!/bin/bash
set -e

# Use dedicated temp directory with proper permissions
TEMP_DIR="/tmp/backups"
cd "$TEMP_DIR"

# Default parameters for mysqldump (non-locking priority)
DEFAULT_MYSQLDUMP_PARAMS="--single-transaction --quick --no-tablespaces --skip-lock-tables --skip-add-locks"

# Generate timestamp for filename
TIMESTAMP=$(date +%Y%m%d%H%M%S)
FILENAME="${FILENAME_PREFIX}_${DB_NAME}_${TIMESTAMP}.sql"
COMPRESSED_FILENAME="${FILENAME}.gz"
ENCRYPTED_FILENAME="${FILENAME}.age"
FINAL_FILENAME="${FILENAME}"

# Validate required environment variables
if [ -z "$DB_NAME" ] || [ -z "$DB_HOST" ] || [ -z "$DB_USERNAME" ] || [ -z "$DB_PASSWORD" ]; then
  echo "Error: Required database environment variables not set"
  exit 1
fi

if [ -z "$S3_HOST" ] || [ -z "$S3_ACCESS_KEY" ] || [ -z "$S3_SECRET_KEY" ] || [ -z "$S3_BUCKET" ]; then
  echo "Error: Required S3 environment variables not set"
  exit 1
fi

# Validate encryption settings
if [ "$ENCRYPTION" = "age" ]; then
  if [ -z "$ENCRYPTION_KEY" ] && [ -z "$ENCRYPTION_FILE" ]; then
    echo "Error: ENCRYPTION_KEY or ENCRYPTION_FILE must be provided when ENCRYPTION is set to 'age'"
    exit 1
  fi
  if [ -n "$ENCRYPTION_KEY" ] && [ -n "$ENCRYPTION_FILE" ]; then
    echo "Error: ENCRYPTION_KEY and ENCRYPTION_FILE are mutually exclusive"
    exit 1
  fi
fi

# Combine default and custom mysqldump parameters
MYSQLDUMP_PARAMS="$DEFAULT_MYSQLDUMP_PARAMS"
if [ -n "$MYSQLDUMP_PARAMETERS" ]; then
  MYSQLDUMP_PARAMS="$MYSQLDUMP_PARAMETERS"
fi

# Perform database backup
echo "Starting backup of database $DB_NAME from $DB_HOST..."
MYSQL_PWD="$DB_PASSWORD" mysqldump -h "$DB_HOST" -u "$DB_USERNAME" $MYSQLDUMP_PARAMS "$DB_NAME" > "$FILENAME"
echo "Database backup completed: $FILENAME"

# Compression
if [ "$COMPRESSION" = "gzip" ]; then
  echo "Compressing backup file..."
  gzip -f "$FILENAME"
  FINAL_FILENAME="${COMPRESSED_FILENAME}"
  echo "Compression completed: $FINAL_FILENAME"
fi

# Encryption
if [ "$ENCRYPTION" = "age" ]; then
  echo "Encrypting backup file..."
  if [ -n "$ENCRYPTION_KEY" ]; then
    echo "$ENCRYPTION_KEY" | age -R - -o "${FINAL_FILENAME}.age" "$FINAL_FILENAME"
  else
    age -R "$ENCRYPTION_FILE" -o "${FINAL_FILENAME}.age" "$FINAL_FILENAME"
  fi
  rm -f "$FINAL_FILENAME"
  FINAL_FILENAME="${FINAL_FILENAME}.age"
  echo "Encryption completed: $FINAL_FILENAME"
fi

# Configure s3cmd
echo "Configuring S3 client..."
cat > $TEMP_DIR/.s3cfg << EOF
host_base = $S3_HOST
host_bucket = $S3_HOST/$S3_BUCKET
access_key = $S3_ACCESS_KEY
secret_key = $S3_SECRET_KEY
use_https = True
EOF

# Upload to S3
S3_DEST="s3://$S3_BUCKET"
if [ -n "$S3_PATH_PREFIX" ]; then
  S3_DEST="$S3_DEST/$S3_PATH_PREFIX"
fi
S3_DEST="$S3_DEST/$FINAL_FILENAME"

echo "Uploading backup to $S3_DEST..."
s3cmd -c $TEMP_DIR/.s3cfg put "$FINAL_FILENAME" "$S3_DEST"
echo "Upload completed successfully"

# Cleanup
rm -f "$FILENAME" "$COMPRESSED_FILENAME" "${COMPRESSED_FILENAME}.age" "${FILENAME}.age"
echo "Backup process completed successfully"
