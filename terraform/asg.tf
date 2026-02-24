resource "aws_autoscaling_group" "main" {
  name                = "${var.project_name}-asg"
  vpc_zone_identifier = aws_subnet.public[*].id

  min_size         = 2
  desired_capacity = 2
  max_size         = 4

  # Use ELB health checks so unhealthy instances are replaced by ASG
  health_check_type         = "ELB"
  health_check_grace_period = 300

  launch_template {
    id      = aws_launch_template.main.id
    version = "$Latest"
  }

  # Register instances in both target groups
  target_group_arns = [
    aws_lb_target_group.service1.arn,
    aws_lb_target_group.service2.arn,
  ]

  tag {
    key                 = "Name"
    value               = "${var.project_name}-asg-instance"
    propagate_at_launch = true
  }
}

# Scale-out policy: CPU > 40% sustained → add instances
# estimated_instance_warmup=300 aligns with the "5 minutes" scale-out threshold
resource "aws_autoscaling_policy" "cpu_target_tracking" {
  name                      = "${var.project_name}-cpu-target-tracking"
  autoscaling_group_name    = aws_autoscaling_group.main.name
  policy_type               = "TargetTrackingScaling"
  estimated_instance_warmup = 300

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 40.0
  }
}
