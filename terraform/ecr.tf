resource "aws_ecr_repository" "service1" {
  name                 = "service1"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-service1"
  }
}

resource "aws_ecr_repository" "service2" {
  name                 = "service2"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  tags = {
    Name = "${var.project_name}-service2"
  }
}
