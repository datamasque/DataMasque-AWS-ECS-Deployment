resource "aws_lb" "this" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name               = "${each.key}-dm-alb"
  internal           = true
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg[each.key].id]
  subnets            = values(local.common_env_config.subnets)
  xff_header_processing_mode = "remove"
}


resource "aws_lb_target_group" "this" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  name     = "${each.key}-dm-tg"
  port     = 8443
  protocol = "HTTPS"
  vpc_id   = local.common_env_config.vpcid
  target_type = "ip"

  health_check {
    path                = "/login"
    interval            = 10
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
    matcher             = "200"
    protocol = "HTTPS"
  }
}

resource "aws_lb_listener" "this" {
  for_each = lookup(local.ecs_config["ecs"], "clusters", {})
  load_balancer_arn = aws_lb.this[each.key].arn
  port              = 443
  protocol          = "HTTPS"
  certificate_arn = "arn:aws:acm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:certificate/${each.value["albCertificate"]}"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this[each.key].arn
  }
}