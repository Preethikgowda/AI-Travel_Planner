#!/bin/bash
# User Data Script for Backend EC2 Instance
# Deploys the AI Travel Planner backend via Docker with full observability
# NOTE: We intentionally do NOT use "set -e" so the script can recover from transient errors
#       and we always get CloudWatch logs for debugging.

exec > >(tee /var/log/user-data.log) 2>&1

echo "========================================"
echo "Starting backend deployment at $(date)"
echo "Environment: ${environment}"
echo "Instance ID: $(curl -s http://169.254.169.254/latest/meta-data/instance-id || echo 'unknown')"
echo "========================================"

# ── System Updates ──
echo "[1/8] Updating system packages..."
yum update -y || echo "WARN: yum update had non-zero exit (often harmless)"

echo "[2/8] Installing required packages..."
yum install -y git docker jq || { echo "FATAL: Failed to install required packages"; exit 1; }

# Install CloudWatch agent (may already be present on AL2023)
yum install -y amazon-cloudwatch-agent || echo "WARN: CW agent install returned non-zero (may be pre-installed)"

# ── Start Docker ──
echo "[3/8] Starting Docker..."
systemctl start docker || { echo "FATAL: Failed to start Docker"; exit 1; }
systemctl enable docker
usermod -aG docker ec2-user

# ── Ensure SSM Agent is running ──
echo "[3.5/8] Starting SSM Agent..."
systemctl enable amazon-ssm-agent 2>/dev/null || true
systemctl start amazon-ssm-agent 2>/dev/null || true

# ── CloudWatch Agent Configuration ──
echo "[4/8] Configuring CloudWatch Agent..."
mkdir -p /opt/aws/amazon-cloudwatch-agent/etc
cat > /opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json <<'CWCONFIG'
{
  "agent": {
    "metrics_collection_interval": 60,
    "run_as_user": "root"
  },
  "logs": {
    "logs_collected": {
      "files": {
        "collect_list": [
          {
            "file_path": "/var/log/user-data.log",
            "log_group_name": "/aws/ec2/${project_name}-${environment}-backend",
            "log_stream_name": "{instance_id}/user-data",
            "retention_in_days": 7
          },
          {
            "file_path": "/var/log/backend-app.log",
            "log_group_name": "/aws/ec2/${project_name}-${environment}-backend",
            "log_stream_name": "{instance_id}/application",
            "retention_in_days": 7
          }
        ]
      }
    }
  },
  "metrics": {
    "namespace": "${project_name}-${environment}",
    "metrics_collected": {
      "disk": {
        "measurement": ["used_percent"],
        "resources": ["*"]
      },
      "mem": {
        "measurement": ["mem_used_percent"]
      }
    }
  }
}
CWCONFIG

/opt/aws/amazon-cloudwatch-agent/bin/amazon-cloudwatch-agent-ctl \
  -a fetch-config -m ec2 \
  -c file:/opt/aws/amazon-cloudwatch-agent/etc/amazon-cloudwatch-agent.json -s || echo "WARN: CW agent config failed"

echo "[4.5/8] CloudWatch agent started. Logs should now appear in CloudWatch."

# ── Clone Repository ──
echo "[5/8] Cloning repository..."
cd /opt
if [ -d "AI-Travel_Planner" ]; then
  cd AI-Travel_Planner && git pull
else
  git clone https://github.com/Preethikgowda/AI-Travel_Planner.git || { echo "FATAL: git clone failed"; exit 1; }
  cd AI-Travel_Planner
fi

echo "Current directory: $(pwd)"
echo "Repository contents:"
ls -la

# ── Create Environment File ──
echo "[6/8] Creating .env file..."
cat > backend/.env << 'ENVEOF'
%{ for key, value in environment_variables ~}
${key}=${value}
%{ endfor ~}
ENVEOF

echo "--- .env file contents (keys only) ---"
grep -oP '^[A-Z_]+' backend/.env || echo "WARN: Could not parse .env keys"
echo "--- end .env ---"

# ── Build Docker Container ──
echo "[7/8] Building Docker image..."
echo "Dockerfile contents:"
cat backend/Dockerfile
echo "---"
docker build -t ai-travel-backend:latest ./backend 2>&1
BUILD_EXIT=$?
if [ $BUILD_EXIT -ne 0 ]; then
  echo "FATAL: Docker build failed with exit code $BUILD_EXIT"
  exit 1
fi
echo "Docker build completed successfully."

# Stop existing container if running
docker stop ai-travel-backend 2>/dev/null || true
docker rm ai-travel-backend 2>/dev/null || true

# ── Run Container ──
# Use json-file log driver instead of awslogs to avoid IAM/network issues blocking container start.
# The CloudWatch agent above will pick up /var/log/backend-app.log instead.
echo "[8/8] Starting backend container..."
docker run -d \
  --name ai-travel-backend \
  --restart always \
  -p 8000:8000 \
  --log-driver=json-file \
  --log-opt max-size=50m \
  --log-opt max-file=3 \
  --env-file backend/.env \
  ai-travel-backend:latest

DOCKER_EXIT=$?
if [ $DOCKER_EXIT -ne 0 ]; then
  echo "FATAL: docker run failed with exit code $DOCKER_EXIT"
  exit 1
fi

echo "Container started. Checking initial logs..."
sleep 5
docker logs ai-travel-backend 2>&1 | tail -50

# Pipe docker logs to a file for CloudWatch Agent to pick up (background process)
docker logs -f ai-travel-backend >> /var/log/backend-app.log 2>&1 &

# ── Health Check with Retry ──
echo "Waiting for backend health check..."
MAX_RETRIES=60
RETRY_COUNT=0
until curl -sf http://localhost:8000/health > /dev/null 2>&1; do
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
    echo "ERROR: Backend failed to start after $MAX_RETRIES attempts"
    echo "--- Container status ---"
    docker ps -a
    echo "--- Container logs (last 100 lines) ---"
    docker logs --tail 100 ai-travel-backend 2>&1
    echo "--- Container inspect ---"
    docker inspect ai-travel-backend 2>&1 | jq '.[0].State'
    exit 1
  fi
  if [ $((RETRY_COUNT % 6)) -eq 0 ]; then
    echo "  Attempt $RETRY_COUNT/$MAX_RETRIES — still waiting ($(docker inspect --format='{{.State.Status}}' ai-travel-backend 2>/dev/null || echo 'unknown'))..."
    docker logs --tail 5 ai-travel-backend 2>&1
  fi
  sleep 5
done

echo "========================================"
echo "Backend successfully started at $(date)"
echo "Health check: $(curl -s http://localhost:8000/health)"
echo "========================================"
