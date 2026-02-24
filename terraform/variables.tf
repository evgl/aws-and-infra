variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "ap-northeast-2"
}

variable "aws_account_id" {
  description = "AWS account ID (used for ECR URI construction in user-data)"
  type        = string
}

variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "microservice"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidrs" {
  description = "CIDR blocks for the two public subnets (must be in different AZs)"
  type        = list(string)
  default     = ["10.0.1.0/24", "10.0.2.0/24"]
}

variable "instance_type" {
  description = "EC2 instance type for ASG instances"
  type        = string
  default     = "t2.micro"
}

variable "my_ip" {
  description = "Your public IP in CIDR notation for SSH access (e.g. 1.2.3.4/32). Defaults to 0.0.0.0/0 — restrict for security."
  type        = string
  default     = "0.0.0.0/0"
}

variable "key_name" {
  description = "EC2 key pair name for SSH access. Leave empty to skip SSH key attachment."
  type        = string
  default     = ""
}
