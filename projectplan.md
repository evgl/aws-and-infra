# DevOps Assessment — Project Plan

## Architecture Overview

Before diving into tasks, here is the target architecture and key design decisions.

```
                        ┌─────────────────────────┐
                        │        Internet          │
                        └────────────┬────────────┘
                                     │
                              ┌──────▼──────┐
                              │  ALB (:80)  │
                              │  Public SG   │
                              └──┬───────┬──┘
                   ┌─────────────┘       └─────────────┐
                   │  /service1 path     /service2 path│
                   │  → TG1 (:8080)      → TG2 (:8081)│
                   ▼                                   ▼
        ┌─────────────────────┐          ┌─────────────────────┐
        │   EC2 Instance A    │          │   EC2 Instance B    │
        │   (t2.micro)        │          │   (t2.micro)        │
        │                     │          │                     │
        │  ┌───────────────┐  │          │  ┌───────────────┐  │
        │  │  service1      │  │          │  │  service1      │  │
        │  │  :8080 → :5000 │  │          │  │  :8080 → :5000 │  │
        │  └───────────────┘  │          │  └───────────────┘  │
        │  ┌───────────────┐  │          │  ┌───────────────┐  │
        │  │  service2      │  │          │  │  service2      │  │
        │  │  :8081 → :5001 │  │          │  │  :8081 → :5001 │  │
        │  └───────────────┘  │          │  └───────────────┘  │
        │   EC2 SG (private)  │          │   EC2 SG (private)  │
        └─────────────────────┘          └─────────────────────┘
                   │                                   │
                   └──────────┐       ┌────────────────┘
                              ▼       ▼
                        ┌─────────────────┐
                        │   Amazon ECR    │
                        │  service1:latest│
                        │  service2:latest│
                        └─────────────────┘
```

### Key Design Decisions

| Decision | Choice | Rationale |
|---|---|---|
| **Instance topology** | Each EC2 runs BOTH services | Enables HA — either instance can serve any request. ALB routes to both. Simplifies ASG scaling (one launch template, one compose file). |
| **Port mapping** | 8080→5000 (svc1), 8081→5001 (svc2) | Problem statement suggests 8080/8081 as external ports. Internal container ports stay native (5000/5001). |
| **ALB routing** | Path-based: `/service1` → TG1(:8080), `/service2` → TG2(:8081) | Two target groups, same instances registered in both but on different ports. |
| **VPC** | Default VPC for manual; custom VPC in Terraform | Speed for manual; best practice for IaC. |
| **ECR auth on EC2** | IAM Instance Profile with `AmazonEC2ContainerRegistryReadOnly` | Least-privilege — instances only need pull access. No long-lived credentials on disk. |
| **Docker install** | User-data script (cloud-init) | Repeatable, automatable, required for Launch Template / ASG bonus. |
| **Region** | `ap-northeast-2` (Seoul) | Problem hints at KRW reimbursement — nearest region is likely Korea. Configurable. |

---

## Checkpoint 0: Pre-Work & Local Verification

**Goal**: Confirm the starter code works locally before touching AWS.

- [ ] **0.1** Clone/review the repo structure — understand both services, Dockerfiles, and the existing local docker-compose.yml
- [ ] **0.2** Build both images locally
  - `docker build -t service1:latest ./servers/service1`
  - `docker build -t service2:latest ./servers/service2`
  - If on Apple Silicon: use `docker buildx build --platform linux/amd64` for EC2 compatibility
- [ ] **0.3** Run locally with the provided docker-compose.yml
  - `cd servers && docker compose up -d`
- [ ] **0.4** Verify both services respond
  - `curl http://localhost:5000/health` → `{"status":"healthy"}`
  - `curl http://localhost:5001/health` → `{"status":"healthy"}`
  - `curl http://localhost:5000/service1` → `{"message":"Hello from Service 1",...}`
  - `curl http://localhost:5001/service2` → `{"message":"Hello from Service 2",...}`
- [ ] **0.5** Tear down local containers: `docker compose down`

**Exit Criteria**: Both services build and respond correctly on local machine.

---

## Checkpoint 1: ECR Repository Setup & Image Push (Stage A)

**Goal**: Docker images are pushed to ECR and pullable by URI.

- [ ] **1.1** Create two ECR repositories
  - `aws ecr create-repository --repository-name service1 --region <REGION>`
  - `aws ecr create-repository --repository-name service2 --region <REGION>`
- [ ] **1.2** Authenticate Docker CLI to ECR
  - `aws ecr get-login-password --region <REGION> | docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com`
- [ ] **1.3** Tag local images with ECR URI
  - `docker tag service1:latest <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/service1:latest`
  - `docker tag service2:latest <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/service2:latest`
- [ ] **1.4** Push both images
  - `docker push <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/service1:latest`
  - `docker push <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/service2:latest`
- [ ] **1.5** Verify images exist in ECR
  - `aws ecr describe-images --repository-name service1`
  - `aws ecr describe-images --repository-name service2`
- [ ] **1.6** 📸 Screenshot: ECR console showing both repos with images

**Exit Criteria**: `docker pull <ECR-URI>/service1:latest` succeeds with correct digest.

---

## Checkpoint 2: Networking Foundation (Partial Stage D — done first)

**Goal**: VPC, subnets, and security groups are ready before launching instances.

> We set up networking first because EC2 instances and the ALB both depend on security groups and subnets being in place.

- [ ] **2.1** Identify or create VPC
  - Manual: use default VPC, note VPC ID
  - Terraform: create a new VPC with `10.0.0.0/16` CIDR
- [ ] **2.2** Identify/create at least 2 public subnets in the same AZ (ALB requires 2 AZs minimum)
  - Actually, ALB requires subnets in **at least 2 different AZs**
  - EC2 instances go in the **same AZ** per the problem statement
  - So: 2+ public subnets across 2+ AZs for ALB; both instances in one of those AZs
- [ ] **2.3** Ensure an Internet Gateway is attached and route tables have `0.0.0.0/0 → IGW`
- [ ] **2.4** Create **ALB Security Group** (`alb-sg`)
  - Inbound: port 80 from `0.0.0.0/0` (public HTTP)
  - Inbound: port 443 from `0.0.0.0/0` (public HTTPS, optional)
  - Outbound: all traffic
- [ ] **2.5** Create **EC2 Security Group** (`ec2-sg`)
  - Inbound: port 22 from **my IP only** (SSH)
  - Inbound: port 8080 from `alb-sg` only (service1 traffic from ALB)
  - Inbound: port 8081 from `alb-sg` only (service2 traffic from ALB)
  - Outbound: all traffic (needed for ECR pulls, apt-get, etc.)
- [ ] **2.6** Create an **IAM Role** for EC2 (`ecr-pull-role`)
  - Attach policy: `AmazonEC2ContainerRegistryReadOnly`
  - Create an Instance Profile wrapping this role
- [ ] **2.7** Create or import an **SSH Key Pair** for instance access

**Exit Criteria**: Two security groups exist with correct rules. IAM role is ready. Subnets identified.

---

## Checkpoint 3: EC2 Instances & Docker Installation (Stage B)

**Goal**: Two t2.micro instances running Docker, ready to pull from ECR.

- [ ] **3.1** Find the correct **Ubuntu 24.04 AMI ID** for the chosen region
  - `aws ec2 describe-images --owners 099720109477 --filters "Name=name,Values=ubuntu/images/hvm-ssd-amd64/ubuntu-noble-24.04*" --query 'sort_by(Images, &CreationDate)[-1].ImageId'`
- [ ] **3.2** Launch **EC2 Instance A** (t2.micro)
  - AMI: Ubuntu 24.04
  - Instance type: t2.micro
  - Subnet: chosen AZ
  - Security group: `ec2-sg`
  - IAM Instance Profile: `ecr-pull-role`
  - Key pair: from step 2.7
  - User-data script (see 3.4)
- [ ] **3.3** Launch **EC2 Instance B** — same config, same AZ
- [ ] **3.4** Write the **user-data bootstrap script** that runs on first boot:
  ```bash
  #!/bin/bash
  set -euxo pipefail

  # Update system
  apt-get update -y
  apt-get install -y ca-certificates curl gnupg unzip

  # Install Docker (official method)
  install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  chmod a+r /etc/apt/keyrings/docker.gpg
  echo "deb [arch=$(dpkg --print-architecture) \
    signed-by=/etc/apt/keyrings/docker.gpg] \
    https://download.docker.com/linux/ubuntu \
    $(. /etc/os-release && echo $VERSION_CODENAME) stable" \
    > /etc/apt/sources.list.d/docker.list
  apt-get update -y
  apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

  # Enable & start Docker
  systemctl enable docker
  systemctl start docker
  usermod -aG docker ubuntu

  # Install AWS CLI v2
  curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip
  unzip -q /tmp/awscliv2.zip -d /tmp
  /tmp/aws/install

  # Authenticate to ECR
  aws ecr get-login-password --region <REGION> | \
    docker login --username AWS --password-stdin <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com

  # Place docker-compose.yml
  cat > /home/ubuntu/docker-compose.yml << 'COMPOSE'
  <contents of the EC2 docker-compose.yml — see Checkpoint 4>
  COMPOSE

  # Start services
  cd /home/ubuntu
  docker compose up -d
  ```
- [ ] **3.5** SSH into both instances and verify
  - `docker info` — confirms Docker is installed
  - `docker compose version` — confirms compose plugin
- [ ] **3.6** 📸 Screenshot: `docker info` output on both instances

**Exit Criteria**: Both instances have Docker running and can authenticate to ECR.

---

## Checkpoint 4: Docker Compose on EC2 & Service Startup (Stage C)

**Goal**: Services are running on both instances and responding to health checks.

- [ ] **4.1** Create the **EC2-specific `docker-compose.yml`** (different from the local one):
  ```yaml
  version: "3.8"
  services:
    service1:
      image: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/service1:latest
      ports:
        - "8080:5000"
      environment:
        - FLASK_ENV=production
      restart: unless-stopped

    service2:
      image: <ACCOUNT_ID>.dkr.ecr.<REGION>.amazonaws.com/service2:latest
      ports:
        - "8081:5001"
      environment:
        - FLASK_ENV=production
      restart: unless-stopped
  ```
- [ ] **4.2** If not using user-data: SCP the compose file to both instances
  - `scp -i key.pem docker-compose.yml ubuntu@<IP-A>:~/`
  - `scp -i key.pem docker-compose.yml ubuntu@<IP-B>:~/`
- [ ] **4.3** On each instance, authenticate to ECR and pull images
  - `aws ecr get-login-password --region <REGION> | docker login --username AWS --password-stdin ...`
  - `docker compose pull`
- [ ] **4.4** Start services: `docker compose up -d`
- [ ] **4.5** Verify on each instance
  - `docker ps` — both containers running
  - `curl http://localhost:8080/health` → 200
  - `curl http://localhost:8081/health` → 200
  - `curl http://localhost:8080/service1` → JSON response
  - `curl http://localhost:8081/service2` → JSON response
- [ ] **4.6** Verify from outside (using public IPs, if SG temporarily allows)
  - `curl http://<INSTANCE-A-IP>:8080/health`
  - `curl http://<INSTANCE-B-IP>:8081/health`
- [ ] **4.7** 📸 Screenshot: `docker ps` on both instances

**Exit Criteria**: `curl http://<instance-ip>:<port>/health` returns HTTP 200 on both instances.

---

## Checkpoint 5: Application Load Balancer & Path-Based Routing (Stage D)

**Goal**: ALB routes `/service1` and `/service2` to the correct containers.

- [ ] **5.1** Create **Target Group 1** (`tg-service1`)
  - Protocol: HTTP
  - Port: 8080
  - Target type: instance
  - Health check path: `/health`
  - Health check port: `8080`
  - VPC: same as instances
- [ ] **5.2** Create **Target Group 2** (`tg-service2`)
  - Protocol: HTTP
  - Port: 8081
  - Target type: instance
  - Health check path: `/health`
  - Health check port: `8081`
  - VPC: same as instances
- [ ] **5.3** Register both EC2 instances in **both** target groups
  - Instance A → TG1 (port 8080) and TG2 (port 8081)
  - Instance B → TG1 (port 8080) and TG2 (port 8081)
- [ ] **5.4** Create the **Application Load Balancer**
  - Scheme: internet-facing
  - Subnets: at least 2 public subnets in different AZs
  - Security group: `alb-sg`
- [ ] **5.5** Create **HTTP Listener** on port 80
  - Default action: fixed 404 response (or forward to one TG)
- [ ] **5.6** Add **Listener Rules** for path-based routing
  - Rule 1: If path is `/service1` → forward to `tg-service1`
  - Rule 2: If path is `/service2` → forward to `tg-service2`
  - (Optional) Rule 3: `/health` → forward to either TG (for overall health)
- [ ] **5.7** Wait for target groups to report healthy
  - Check ALB console or `aws elbv2 describe-target-health`
- [ ] **5.8** Test ALB endpoints
  - `curl http://<ALB-DNS>/service1` → `{"message":"Hello from Service 1",...}`
  - `curl http://<ALB-DNS>/service2` → `{"message":"Hello from Service 2",...}`
- [ ] **5.9** 📸 Screenshot: ALB DNS curl responses

**Exit Criteria**: `curl http://<ALB-DNS>/service1` and `/service2` return expected JSON.

---

## Checkpoint 6: Verification Script (Stage E)

**Goal**: Automated script tests all endpoints and reports pass/fail.

- [ ] **6.1** Create `verify_endpoints.sh` (Bash) with the following checks:
  - **ECR checks**:
    - `aws ecr describe-repositories --repository-names service1` succeeds
    - `aws ecr describe-repositories --repository-names service2` succeeds
    - `aws ecr describe-images --repository-name service1` returns at least 1 image
    - `aws ecr describe-images --repository-name service2` returns at least 1 image
  - **ALB endpoint checks**:
    - `curl -sf http://<ALB-DNS>/service1` returns HTTP 200 and expected JSON
    - `curl -sf http://<ALB-DNS>/service2` returns HTTP 200 and expected JSON
  - **Health check verification**:
    - `curl -sf http://<ALB-DNS>/service1` body contains `"Hello from Service 1"`
    - `curl -sf http://<ALB-DNS>/service2` body contains `"Hello from Service 2"`
  - **Optional: Direct instance checks** (if IPs are known):
    - `curl -sf http://<INSTANCE-A>:8080/health` returns 200
    - `curl -sf http://<INSTANCE-B>:8081/health` returns 200
- [ ] **6.2** Script design requirements:
  - Accept ALB DNS as argument or environment variable
  - Print clear PASS/FAIL for each check
  - Count failures
  - Exit 0 if all pass, exit 1 if any fail
  - Use colors for readability (green PASS, red FAIL)
- [ ] **6.3** Test the script against the live environment
- [ ] **6.4** Ensure script is executable: `chmod +x verify_endpoints.sh`

**Exit Criteria**: Script exits 0 when all checks pass; exits non-zero when any fail.

---

## Checkpoint 7: Terraform Infrastructure as Code (Bonus)

**Goal**: Entire infrastructure provisioned via Terraform, including ASG with scaling.

### File Structure
```
terraform/
├── main.tf              # Provider config, data sources
├── variables.tf         # Input variables
├── outputs.tf           # ALB DNS, ECR URIs, etc.
├── vpc.tf               # VPC, subnets, IGW, route tables
├── ecr.tf               # ECR repositories
├── iam.tf               # IAM role + instance profile for EC2
├── security_groups.tf   # ALB SG, EC2 SG
├── alb.tf               # ALB, target groups, listener, rules
├── launch_template.tf   # Launch template with user-data
├── asg.tf               # ASG + scaling policies
├── userdata.sh.tpl      # Templated user-data script
└── terraform.tfvars     # (gitignored) Actual variable values
```

### Sub-Tasks

- [ ] **7.1** `main.tf` — Provider & Data Sources
  - AWS provider with region variable
  - Data source for Ubuntu 24.04 AMI
  - Data source for available AZs
- [ ] **7.2** `variables.tf` — Define all inputs
  - `aws_region`, `vpc_cidr`, `public_subnet_cidrs`
  - `instance_type` (default: t2.micro)
  - `ecr_account_id`, `ecr_region` (for image URIs)
  - `my_ip` (for SSH access)
  - `key_pair_name`
  - `asg_min`, `asg_desired`, `asg_max` (defaults: 2, 2, 4)
  - `cpu_scale_threshold` (default: 40)
- [ ] **7.3** `vpc.tf` — Networking
  - VPC with DNS support enabled
  - 2 public subnets in different AZs
  - Internet Gateway
  - Route table with `0.0.0.0/0 → IGW`
  - Route table associations
- [ ] **7.4** `ecr.tf` — Container Registry
  - Two ECR repositories: `service1`, `service2`
  - Image tag mutability: MUTABLE (for `:latest`)
  - Optional: lifecycle policy to keep last N images
- [ ] **7.5** `iam.tf` — Permissions
  - IAM Role with EC2 assume-role trust policy
  - Attach `AmazonEC2ContainerRegistryReadOnly` managed policy
  - Attach `AmazonSSMManagedInstanceCore` (optional, for SSM access)
  - Instance Profile wrapping the role
- [ ] **7.6** `security_groups.tf` — Firewall Rules
  - `alb-sg`: inbound 80 from `0.0.0.0/0`, outbound all
  - `ec2-sg`: inbound 22 from `var.my_ip`, inbound 8080+8081 from `alb-sg`, outbound all
- [ ] **7.7** `alb.tf` — Load Balancer
  - ALB (internet-facing) in public subnets with `alb-sg`
  - Target Group 1: port 8080, health check `/health`
  - Target Group 2: port 8081, health check `/health`
  - HTTP Listener on port 80
  - Listener Rule: `/service1*` → TG1
  - Listener Rule: `/service2*` → TG2
  - Default action: fixed 404 response
- [ ] **7.8** `userdata.sh.tpl` — Templated Bootstrap
  - Template variables: `${ecr_uri_service1}`, `${ecr_uri_service2}`, `${aws_region}`
  - Install Docker, AWS CLI
  - ECR login
  - Write docker-compose.yml with injected ECR URIs
  - `docker compose up -d`
- [ ] **7.9** `launch_template.tf` — EC2 Template
  - AMI: Ubuntu 24.04 (from data source)
  - Instance type: from variable
  - Key pair, security group, IAM instance profile
  - User-data: rendered from template
  - Tag: `Name = "devops-assessment-instance"`
- [ ] **7.10** `asg.tf` — Auto Scaling
  - Auto Scaling Group
    - min_size: 2, desired_capacity: 2, max_size: 4
    - Launch template reference (latest version)
    - VPC zone identifier: public subnets
    - Target group attachments: BOTH TGs
    - Health check type: ELB
    - Health check grace period: 300s
  - Scaling Policy (Target Tracking)
    - Metric: `ASGAverageCPUUtilization`
    - Target value: 40.0
    - Cooldown: 300s
  - OR Step Scaling Policy + CloudWatch Alarm
    - Alarm: CPU > 40% for 5 minutes (period=60, evaluation_periods=5)
    - Alarm action: scale out +1
- [ ] **7.11** `outputs.tf` — Key outputs
  - ALB DNS name
  - ECR repository URIs
  - Security group IDs
  - ASG name (for inspecting events)
- [ ] **7.12** Test Terraform
  - `terraform init`
  - `terraform plan` — review
  - `terraform apply`
  - Verify ALB endpoints work
- [ ] **7.13** 📸 Screenshot: ASG event history / CloudWatch showing scale behavior

**Exit Criteria**: `terraform apply` provisions entire stack. ALB endpoints respond. ASG has 2 running instances.

---

## Checkpoint 8: Documentation & Deliverables

**Goal**: All required deliverables are polished and ready for submission.

- [ ] **8.1** Update **README.md** with:
  - Architecture description (the diagram from this plan, cleaned up)
  - AWS region used
  - Step-by-step deployment instructions (manual path)
  - How to run `verify_endpoints.sh`
  - Terraform usage instructions (if applicable)
  - Cleanup instructions
- [ ] **8.2** Create ASCII or Mermaid **architecture diagram** in the README
- [ ] **8.3** Collect all **screenshots**:
  - ECR repositories with images
  - `docker ps` on both EC2 instances
  - ALB DNS + curl responses showing service1 and service2 JSON
  - (Bonus) ASG events or CloudWatch graphs
- [ ] **8.4** Add **cleanup confirmation** statement to README
- [ ] **8.5** Organize repo structure:
  ```
  .
  ├── README.md                    # Updated with architecture + instructions
  ├── projectplan.md               # This file
  ├── docker-compose.yml           # EC2-specific compose file (deliverable)
  ├── verify_endpoints.sh          # Verification script (deliverable)
  ├── servers/
  │   ├── docker-compose.yml       # Original local dev compose (reference)
  │   ├── service1/
  │   └── service2/
  ├── terraform/                   # Bonus IaC (deliverable)
  │   ├── main.tf
  │   ├── ...
  │   └── userdata.sh.tpl
  ├── screenshots/                 # Evidence (deliverable)
  │   ├── ecr-repos.png
  │   ├── docker-ps-instance-a.png
  │   ├── docker-ps-instance-b.png
  │   ├── alb-curl-service1.png
  │   ├── alb-curl-service2.png
  │   └── asg-events.png          # Bonus
  └── .gitignore
  ```
- [ ] **8.6** Review `.gitignore` — ensure no secrets, .tfstate, or .terraform/ are committed

**Exit Criteria**: Repo is clean, all deliverables present, README is comprehensive.

---

## Checkpoint 9: Cleanup & Cost Control

**Goal**: All AWS resources torn down, no ongoing charges.

- [ ] **9.1** If using Terraform: `terraform destroy`
- [ ] **9.2** If manual, tear down in reverse order:
  - Delete ALB + listeners
  - Delete Target Groups
  - Terminate EC2 instances
  - Delete Security Groups
  - Delete IAM Role + Instance Profile
  - Delete ECR repositories (and images)
  - Delete Key Pair
  - (If created) Delete VPC, subnets, IGW, route tables
- [ ] **9.3** Verify in AWS Console: no running resources
- [ ] **9.4** Check AWS Cost Explorer for any charges
- [ ] **9.5** 📸 Screenshot: Billing/usage if claiming reimbursement
- [ ] **9.6** Add cleanup confirmation note to README

**Exit Criteria**: AWS account has no lingering resources from this project.

---

## Execution Order & Dependencies

```
Checkpoint 0 (Local Verify)
    │
    ▼
Checkpoint 1 (ECR Push) ──────────────────────┐
    │                                          │
    ▼                                          │
Checkpoint 2 (Networking Foundation)           │
    │                                          │
    ▼                                          │
Checkpoint 3 (EC2 + Docker) ◄──────────────────┘
    │                           (needs ECR URIs)
    ▼
Checkpoint 4 (Compose + Services)
    │
    ▼
Checkpoint 5 (ALB + Routing)
    │
    ▼
Checkpoint 6 (Verification Script)
    │
    ├─── Core Complete ✅
    │
    ▼
Checkpoint 7 (Terraform — Bonus)
    │
    ▼
Checkpoint 8 (Documentation)
    │
    ▼
Checkpoint 9 (Cleanup)
```

## Time Estimates

| Checkpoint | Estimated Time | Cumulative |
|---|---|---|
| 0. Local Verify | 10 min | 10 min |
| 1. ECR Push | 15 min | 25 min |
| 2. Networking | 20 min | 45 min |
| 3. EC2 + Docker | 25 min | 1h 10m |
| 4. Compose + Services | 15 min | 1h 25m |
| 5. ALB + Routing | 25 min | 1h 50m |
| 6. Verification Script | 20 min | 2h 10m |
| 7. Terraform (Bonus) | 60 min | 3h 10m |
| 8. Documentation | 25 min | 3h 35m |
| 9. Cleanup | 10 min | 3h 45m |

**Total**: ~3h 45m (within the 3–4 hour window)

## Risk & Gotchas

| Risk | Mitigation |
|---|---|
| Apple Silicon builds → `exec format error` on EC2 | Always build with `--platform linux/amd64` |
| ALB health checks failing | Ensure SG allows ALB → EC2 on ports 8080/8081. Check health check path is exactly `/health`. |
| ECR auth token expires (12 hours) | Refresh before compose pull if instance has been up a while. For ASG, user-data runs on launch so it's always fresh. |
| ALB requires 2 AZs but problem says "same AZ" for EC2 | ALB spans 2 AZs for redundancy; EC2 instances can be in one of them. |
| User-data script failures are silent | Check `/var/log/cloud-init-output.log` on the instance for debugging. |
| t2.micro CPU credits | Burstable instance; CPU stress test for ASG demo may exhaust credits. Monitor. |
| Terraform state management | Use local state for this assessment (no remote backend needed). Add `.terraform/` and `*.tfstate*` to `.gitignore`. |
