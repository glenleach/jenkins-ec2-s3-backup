#!/bin/bash
# Log all output for debugging
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1
set -ex

# Variables
BUCKET_NAME="${bucket_name}"
JENKINS_HOME="/var/jenkins_home"

# Install dependencies
yum update -y
amazon-linux-extras install docker -y
yum install -y docker awscli unzip zip

# Start and enable Docker
systemctl start docker
systemctl enable docker

# Add ec2-user to docker group for SSH sessions
usermod -aG docker ec2-user

# Wait until Docker daemon is running and responsive
echo "Ensuring Docker daemon is running and responsive before starting Jenkins container..."
for i in $(seq 1 12); do
  if docker info > /dev/null 2>&1; then
    echo "Docker is running and responsive."
    break
  fi
  echo "Docker not ready yet. Waiting 5 seconds... ($i/12)"
  sleep 5
  if [ $i -eq 12 ]; then
    echo "Docker did not become ready in 60 seconds. Exiting."
    exit 1
  fi
done

# Create Jenkins home directory and set permissions
mkdir -p "$JENKINS_HOME"
chown 1000:1000 "$JENKINS_HOME"

# --- RESTORE LOGIC ---
echo "Checking for existing Jenkins home backup in S3..."
RESTORE_OCCURRED=0
if aws s3 ls "s3://$BUCKET_NAME/jenkins_home/" | grep -q .; then
  echo "Found Jenkins home backup in S3. Restoring..."
  aws s3 sync s3://$BUCKET_NAME/jenkins_home/ "$JENKINS_HOME/"
  chown -R 1000:1000 "$JENKINS_HOME"
  echo "Restore complete. Waiting 10 seconds for file system to settle."
  sleep 10
  RESTORE_OCCURRED=1
else
  echo "No Jenkins home backup found in S3. Starting with a fresh Jenkins home."
fi

# --- AUTOMATE JENKINS URL IF RESTORE OCCURRED ---
if [ "$RESTORE_OCCURRED" -eq 1 ]; then
  NEW_URL="http://$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4):8080/"
  JENKINS_CONFIG="$JENKINS_HOME/jenkins.model.JenkinsLocationConfiguration.xml"
  if [ -f "$JENKINS_CONFIG" ]; then
    echo "Updating Jenkins URL in $JENKINS_CONFIG to $NEW_URL"
    sed -i "s|<jenkinsUrl>.*</jenkinsUrl>|<jenkinsUrl>$NEW_URL</jenkinsUrl>|" "$JENKINS_CONFIG"
    chown 1000:1000 "$JENKINS_CONFIG"
  fi
fi

# Pull Jenkins image with retries
for i in $(seq 1 5); do
  if docker pull jenkins/jenkins:lts; then
    echo "Successfully pulled Jenkins image"
    break
  fi
  echo "Docker pull failed, attempt $i of 5, retrying in 10 seconds..."
  sleep 10
  if [ $i -eq 5 ]; then
    echo "Failed to pull Jenkins image after 5 attempts"
    exit 1
  fi
done

# Run Jenkins container as root
docker run -d --restart unless-stopped \
  --name jenkins \
  -p 8080:8080 -p 50000:50000 \
  -v "$JENKINS_HOME":/var/jenkins_home \
  jenkins/jenkins:lts

# Verify container is running
if ! docker ps | grep -q jenkins; then
  echo "Jenkins container failed to start. Attempting to start again..."
  docker start jenkins
  sleep 5
  if ! docker ps | grep -q jenkins; then
    echo "Failed to start Jenkins container after retry"
    exit 1
  fi
fi

# Wait for Jenkins to initialize
echo "Waiting for Jenkins to initialize..."
for i in $(seq 1 60); do
  if docker exec jenkins test -f /var/jenkins_home/secrets/initialAdminPassword; then
    echo "Jenkins initialized successfully"
    echo "Initial admin password:"
    docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
    break
  fi
  echo "Waiting for Jenkins to initialize... ($i/60)"
  sleep 5
  if [ $i -eq 60 ]; then
    if docker exec jenkins test -f /var/jenkins_home/jenkins.install.UpgradeWizard.state; then
      echo "Jenkins likely restored from backup. Setup wizard not required."
      echo "Log in with your existing admin credentials."
    else
      echo "Jenkins failed to initialize within 5 minutes."
    fi
  fi
done


# Set up daily backup to S3 at 2am
cat <<'EOF' > /usr/local/bin/jenkins_backup.sh
#!/bin/bash
set -e
BUCKET_NAME="__BUCKET_NAME__"
JENKINS_HOME="/var/jenkins_home"
echo "Starting Jenkins backup at $(date)"

# Ensure Jenkins is running before backup
if ! docker ps | grep -q jenkins; then
  echo "Jenkins container not running. Attempting to start..."
  docker start jenkins
  sleep 10
  if ! docker ps | grep -q jenkins; then
    echo "Failed to start Jenkins container. Backup aborted."
    exit 1
  fi
fi

# Sync Jenkins home to S3
echo "Syncing $JENKINS_HOME to s3://$BUCKET_NAME/jenkins_home/"
aws s3 sync $JENKINS_HOME s3://$BUCKET_NAME/jenkins_home/ --delete

echo "Backup completed at $(date)"
EOF

# Substitute the actual bucket name in the backup script
sed -i "s|__BUCKET_NAME__|${bucket_name}|g" /usr/local/bin/jenkins_backup.sh

chmod +x /usr/local/bin/jenkins_backup.sh

# Add cron job (runs daily at 2:00 AM)
(crontab -l 2>/dev/null | grep -v jenkins_backup.sh; echo "0 2 * * * /usr/local/bin/jenkins_backup.sh > /var/log/jenkins_backup.log 2>&1") | crontab -

# Run initial backup after 30 minutes to ensure Jenkins is fully set up
echo "Scheduling initial backup in 30 minutes..."
at now + 30 minutes -f /usr/local/bin/jenkins_backup.sh

echo "Jenkins setup completed successfully at $(date)"
