#!/bin/bash
set -euxo pipefail

# ── System update & prerequisites ──────────────────────────────────────────
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release unzip

# ── Install Docker CE ───────────────────────────────────────────────────────
curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
  | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] \
https://download.docker.com/linux/ubuntu $$(lsb_release -cs) stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

systemctl enable docker
systemctl start docker

# ── Install AWS CLI v2 ──────────────────────────────────────────────────────
curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
unzip -q /tmp/awscliv2.zip -d /tmp/
/tmp/aws/install
rm -rf /tmp/aws /tmp/awscliv2.zip

# ── Authenticate Docker with ECR ────────────────────────────────────────────
aws ecr get-login-password --region ${aws_region} \
  | docker login --username AWS --password-stdin \
      ${aws_account_id}.dkr.ecr.${aws_region}.amazonaws.com

# ── Write docker-compose.yml ────────────────────────────────────────────────
mkdir -p /home/ubuntu

cat > /home/ubuntu/docker-compose.yml <<'COMPOSE_EOF'
version: "3.8"
services:
  service1:
    image: ${ecr_uri_service1}:latest
    ports:
      - "8080:5000"
    environment:
      - FLASK_ENV=production
    restart: unless-stopped
  service2:
    image: ${ecr_uri_service2}:latest
    ports:
      - "8081:5001"
    environment:
      - FLASK_ENV=production
    restart: unless-stopped
COMPOSE_EOF

chown ubuntu:ubuntu /home/ubuntu/docker-compose.yml

# ── Start services ──────────────────────────────────────────────────────────
cd /home/ubuntu
docker compose up -d
