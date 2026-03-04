# set up load balancer
# the load balancer is the entry point
# - looks at the request path and decides what to do with the incoming traffic
#   according to matching listener rules and their priority

resource "aws_lb" "load_balancer" {
  name               = "marketmate-app-lb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.public_subnet_1a.id, aws_subnet.public_subnet_1b.id]
  security_groups    = [aws_security_group.load_balancer_sg.id]
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.load_balancer.arn
  port              = 80
  protocol          = "HTTP"
  # By default, return a simple 404 page
  default_action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "404: page not found"
      status_code  = 404
    }
  }
}

resource "aws_lb_listener_rule" "instances" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 100
  condition {
    path_pattern {
      values = ["*"]
    }
  }
  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.web_app_tg.arn
  }
}

# block list part 1
resource "aws_lb_listener_rule" "block_list_1" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 1

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  condition {
    path_pattern {
      values = ["*.php", "/vendor/*", "/.env*", "/.git*", "/wp-admin*"]
    }
  }
}

# block list part 2
resource "aws_lb_listener_rule" "block_list_2" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 2

  action {
    type = "fixed-response"
    fixed_response {
      content_type = "text/plain"
      message_body = "Not Found"
      status_code  = "404"
    }
  }

  condition {
    path_pattern {
      values = ["/wp-login*", "/config.php*", "/cgi-bin/*", "/.aws/*", "/.ssh/*"]
    }
  }
}

resource "aws_lb_target_group" "web_app_tg" {
  name     = "marketmate-app-tg"
  port     = 5000
  protocol = "HTTP"
  vpc_id   = aws_vpc.marketmate_vpc.id

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 60
    timeout             = 3
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_lb_target_group_attachment" "docker_host_1" {
  target_group_arn = aws_lb_target_group.web_app_tg.arn
  target_id        = aws_instance.docker_host_1.id
  port             = 5000
}

resource "aws_lb_target_group_attachment" "docker_host_2" {
  target_group_arn = aws_lb_target_group.web_app_tg.arn
  target_id        = aws_instance.docker_host_2.id
  port             = 5000
}

resource "aws_security_group" "load_balancer_sg" {
  name   = "marketmate-lb-sg"
  vpc_id = aws_vpc.marketmate_vpc.id

  # allow public HTTP (no HTTPS, because no DNS) 
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
