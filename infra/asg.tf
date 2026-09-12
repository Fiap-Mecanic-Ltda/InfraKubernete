resource "aws_launch_template" "worker" {
  name_prefix   = "${var.project_name}-${var.environment}-worker-"
  image_id      = data.aws_ami.al2023.id
  instance_type = var.worker_instance_type
  key_name      = var.ec2_key_pair_name

  iam_instance_profile {
    name = aws_iam_instance_profile.worker_profile.name
  }

  vpc_security_group_ids = [aws_security_group.worker.id, aws_security_group.k3s_mesh.id]

  block_device_mappings {
    device_name = data.aws_ami.al2023.root_device_name
    ebs {
      volume_size = 30
      volume_type = "gp3"
      encrypted   = true
    }
  }

  user_data = base64encode(templatefile("${path.module}/templates/user_data_worker.sh.tpl", {
    region            = var.aws_region
    token_param_name  = "${local.ssm_path_prefix}/k3s-node-token"
    server_private_ip = aws_instance.app.private_ip
  }))

  tag_specifications {
    resource_type = "instance"
    tags = {
      Name = "${var.project_name}-${var.environment}-worker"
    }
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "worker" {
  name                = "${var.project_name}-${var.environment}-worker-asg"
  vpc_zone_identifier = [aws_subnet.public.id]
  min_size            = var.worker_min_size
  max_size            = var.worker_max_size
  desired_capacity    = var.worker_desired_capacity
  # Continua EC2 (e não ELB): o health check do target group mede a saúde do
  # pod da API, e um nó sem pod agendado no momento não é um nó doente — com
  # health_check_type = "ELB" o ASG substituiria a instância por engano.
  health_check_type = "EC2"

  # Todo worker entra no target group do ALB interno: o Service é NodePort, logo
  # qualquer nó atende a API, independente de onde o pod está.
  target_group_arns = [aws_lb_target_group.api.arn]

  launch_template {
    id      = aws_launch_template.worker.id
    version = "$Latest"
  }

  tag {
    key                 = "Name"
    value               = "${var.project_name}-${var.environment}-worker"
    propagate_at_launch = true
  }
}

resource "aws_autoscaling_policy" "worker_cpu" {
  name                   = "${var.project_name}-${var.environment}-worker-cpu-target"
  autoscaling_group_name = aws_autoscaling_group.worker.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = var.worker_asg_target_cpu
  }
}
