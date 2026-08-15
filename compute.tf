# ==========================================
# 1. Application Load Balancers & Target Groups
# ==========================================

# External ALB (Internet Facing)
resource "aws_lb" "ext_alb" {
  name               = "ext-web-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.ext_alb_sg.id]
  subnets            = [aws_subnet.public_a.id, aws_subnet.public_b.id]
  tags               = { Name = "External-ALB" }
}

resource "aws_lb_target_group" "web_tg" {
  name     = "web-tier-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 10
  }
}

resource "aws_lb_listener" "ext_listener" {
  load_balancer_arn = aws_lb.ext_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_tg.arn
  }
}

# Internal ALB (Facing App Tier)
resource "aws_lb" "internal_alb" {
  name               = "int-app-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.int_alb_sg.id]
  subnets            = [aws_subnet.web_private_a.id, aws_subnet.web_private_b.id] 
  tags               = { Name = "Internal-ALB" }
}

resource "aws_lb_target_group" "app_tg" {
  name     = "app-tier-tg"
  port     = 4000 # Default port for the backend in this workshop
  protocol = "HTTP"
  vpc_id   = aws_vpc.main.id
  health_check {
    path                = "/health"
    healthy_threshold   = 2
    unhealthy_threshold = 5
    timeout             = 5
    interval            = 10
  }
}

resource "aws_lb_listener" "int_listener" {
  load_balancer_arn = aws_lb.internal_alb.arn
  port              = "80"
  protocol          = "HTTP"
  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

# ==========================================
# 2. Data Sources & Launch Templates
# ==========================================

# Fetch latest Amazon Linux 2023 AMI
data "aws_ami" "amazon_linux" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# App Tier Launch Template (Backend)
resource "aws_launch_template" "app_lt" {
  name_prefix   = "app-tier-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "m7i-flex.large"
  
  network_interfaces {
    security_groups = [aws_security_group.app_tier_sg.id]
  }

  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y git nodejs

    # Clone Repo
    git clone https://github.com/aws-samples/aws-three-tier-web-architecture-workshop.git
    cd aws-three-tier-web-architecture-workshop/application-code/app-tier

    # Install dependencies and start Backend
    npm install
    npm install -g pm2
    pm2 start index.js
    pm2 startup
    pm2 save
  EOF
  )
}

# Web Tier Launch Template (Frontend + Nginx)
resource "aws_launch_template" "web_lt" {
  name_prefix   = "web-tier-lt-"
  image_id      = data.aws_ami.amazon_linux.id
  instance_type = "m7i-flex.large"

  network_interfaces {
    security_groups = [aws_security_group.web_tier_sg.id]
  }

  # Passing Internal ALB DNS to the Web User Data
  user_data = base64encode(<<-EOF
    #!/bin/bash
    dnf update -y
    dnf install -y git nodejs nginx
    
    # Clone Repo
    git clone https://github.com/aws-samples/aws-three-tier-web-architecture-workshop.git
    cd aws-three-tier-web-architecture-workshop/application-code/web-tier
    
    # Install and Build Frontend
    npm install
    npm run build
    
    # Setup Nginx
    rm /usr/share/nginx/html/*
    cp -r build/* /usr/share/nginx/html/
    
    # Inject Internal ALB DNS into Nginx Config
    cd ../..
    sed -i "s/\[INTERNAL-LOADBALANCER-DNS\]/${aws_lb.internal_alb.dns_name}/g" application-code/nginx.conf
    cp application-code/nginx.conf /etc/nginx/nginx.conf
    
    # Start Nginx
    systemctl enable nginx
    systemctl start nginx
  EOF
  )
}

# ==========================================
# 3. Auto Scaling Groups & Policies
# ==========================================

# App Tier ASG
resource "aws_autoscaling_group" "app_asg" {
  name                = "app-tier-asg"
  vpc_zone_identifier = [aws_subnet.app_private_a.id, aws_subnet.app_private_b.id]
  min_size            = 2
  max_size            = 10
  desired_capacity    = 2
  target_group_arns   = [aws_lb_target_group.app_tg.arn]

  launch_template {
    id      = aws_launch_template.app_lt.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90
    }
  }
}

# App Tier Scaling Policy (Target Tracking 60% CPU)
resource "aws_autoscaling_policy" "app_cpu_policy" {
  name                   = "app-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.app_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}

# Web Tier ASG
resource "aws_autoscaling_group" "web_asg" {
  name                = "web-tier-asg"
  vpc_zone_identifier = [aws_subnet.web_private_a.id, aws_subnet.web_private_b.id]
  min_size            = 2
  max_size            = 10
  desired_capacity    = 2
  target_group_arns   = [aws_lb_target_group.web_tg.arn]

  launch_template {
    id      = aws_launch_template.web_lt.id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 90
    }
  }
}

# Web Tier Scaling Policy (Target Tracking 60% CPU)
resource "aws_autoscaling_policy" "web_cpu_policy" {
  name                   = "web-cpu-target-tracking"
  autoscaling_group_name = aws_autoscaling_group.web_asg.name
  policy_type            = "TargetTrackingScaling"

  target_tracking_configuration {
    predefined_metric_specification {
      predefined_metric_type = "ASGAverageCPUUtilization"
    }
    target_value = 60.0
  }
}