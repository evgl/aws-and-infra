resource "aws_launch_template" "main" {
  name_prefix   = "${var.project_name}-lt-"
  image_id      = data.aws_ami.ubuntu.id
  instance_type = var.instance_type
  key_name      = var.key_name != "" ? var.key_name : null

  iam_instance_profile {
    name = aws_iam_instance_profile.ec2.name
  }

  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.ec2.id]
  }

  monitoring {
    enabled = true
  }

  # Bootstrap: install Docker, pull images from ECR, start services
  user_data = base64encode(templatefile("${path.module}/userdata.sh.tpl", {
    aws_region       = var.aws_region
    aws_account_id   = var.aws_account_id
    ecr_uri_service1 = aws_ecr_repository.service1.repository_url
    ecr_uri_service2 = aws_ecr_repository.service2.repository_url
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-instance"
    }
  }

  tag_specifications {
    resource_type = "volume"
    tags = {
      Name = "${var.project_name}-volume"
    }
  }

  tags = {
    Name = "${var.project_name}-launch-template"
  }

  lifecycle {
    create_before_destroy = true
  }
}
