FROM alpine:3.19

RUN apk add --no-cache \
    bash \
    mysql-client \
    gzip \
    s3cmd \
    age \
    && rm -rf /var/cache/apk/*

# Create non-root user
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

COPY backup.sh /app/
RUN chmod +x /app/backup.sh && \
    chown -R appuser:appgroup /app

# Default environment variables
ENV COMPRESSION="none" \
    ENCRYPTION="none" \
    FILENAME_PREFIX="backup" \
    S3_PATH_PREFIX="" \
    MYSQLDUMP_PARAMETERS=""

# Switch to non-root user
USER appuser

CMD ["/app/backup.sh"]
