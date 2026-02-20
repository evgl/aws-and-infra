# DevOps Interview Assessment

## Background
Your team is currently refactoring a legacy monolithic application into a modern, containerized microservices architecture. Two services have been successfully containerized and verified to work locally via Docker. Management has requested a quick proof-of-concept demonstrating your ability to:
- Package and push Docker images to a private container registry.
- Deploy the services to a basic EC2 environment.
- Expose them via a Load Balancer.
- Lay the groundwork for future auto-scaling.

This exercise simulates a realistic, time-boxed infrastructure migration and deployment task, focusing on foundational DevOps skills using AWS and Docker.

## Objective
Design and implement a minimal end-to-end deployment pipeline in AWS that lifts and shifts the containerized services from local development to a scalable cloud environment.

### Core Stages

| Stage | Task Description | Success Criteria |
|-------|-----------------|------------------|
| A. Image Push | Tag and push provided Docker images to Amazon ECR. | `docker pull <ECR-URI>` retrieves image with correct digest. |
| B. Compute Layer | Launch two t2.micro EC2 instances (Ubuntu 24.04) in the same VPC and AZ. Install Docker. | `docker info` confirms Docker is installed. `docker compose up -d` runs services. |
| C. Orchestration | Create and place a docker-compose.yml on the EC2 instances. Pull images from ECR and expose on fixed ports (e.g., 8080, 8081). | `curl http://<instance-ip>:<port>/health` returns HTTP 200. |
| D. Networking | Provision an Application Load Balancer (ALB) with two Target Groups. Forward traffic to service ports based on the path. | `curl http://<ALB-DNS>/<service-route>` returns expected service response. |
| E. Verification Script | Implement a Bash or Python script to test all endpoints and exit with non-zero status on failure. | Script exits cleanly when all checks pass. |

### Bonus (Stretch Goal) – Infrastructure as Code
Use Terraform or AWS Console to provision:
- A Launch Template that pre-installs Docker, pulls ECR images, and uploads the docker-compose.yml via EC2 user-data.
- An Auto Scaling Group (ASG) with min=2, desired=2, max=4.
- Attach ASG instances to the ALB's existing Target Groups.
- Define a scale-out policy: CPU > 40% for 5 minutes.

Success is demonstrated by ASG event history or monitoring graphs showing scale-out behavior.

## Constraints & Guidelines
- Time Limit: ~3–4 hours. Prioritize core tasks; bonus is optional.
- AWS Region: Use your nearest region for latency/performance.
- IAM: Apply least-privilege principles; if short on time, temporary use of AmazonEC2ContainerRegistryFullAccess is acceptable.
- Security Groups:
  - Inbound: Allow ports 22 (from your IP), 80/443 (public), and service-specific ports (e.g., 5000, 5001) from the ALB only.
  - Outbound: Allow all (0.0.0.0/0).

## Deliverables
Please submit the following via a public GitHub repository or a downloadable ZIP:
1. README.md: Describe architecture, AWS region used, deployment steps, and how to run the verification script. Include a diagram (hand-drawn or generated).
2. docker-compose.yml: File used on EC2 instances.
3. verify_endpoints.sh or verify_endpoints.py: Health check script.
4. Screenshots or command output showing:
   - ECR repository images
   - docker ps on both EC2 instances
   - ALB DNS + curl responses
   - (Bonus) ASG scale-out event evidence
5. Cleanup confirmation: Note stating all AWS resources have been torn down.
6. (Optional) Terraform code if infrastructure was provisioned via IaC.

Note: Partial credit will be given for near-complete solutions. Well-structured, commented Terraform code may earn additional credit within the bonus.

## Getting Started

The repository contains two containerized services. Familiarize yourself with them before proceeding:

```bash
# Build and test services locally
# (Specific commands intentionally omitted - figure out how to build and run the services)

# Verify services are working locally
# (Specific verification commands intentionally omitted)
```

## Verification Script Requirements

Your verification script should include the following tests:

```bash
# Test the endpoints
curl -s http://$ALB_DNS/service1
curl -s http://$ALB_DNS/service2

# Describe repositories
aws ecr describe-repositories --repository-names service1 --query 'repositories[0].repositoryUri' --output text
aws ecr describe-repositories --repository-names service2 --query 'repositories[0].repositoryUri' --output text
```

## Helpful Tips

- If building Docker images on macOS, you may need to use `docker buildx` to build multi-architecture images compatible with EC2:
  ```bash
  docker buildx build --platform linux/amd64 -t service1:latest .
  ```

Good luck!
