##################################################################
# Instance Profile
##################################################################
resource "aws_iam_instance_profile" "master_ip" {
  name = "${var.application}-master-ip"
  path = "/"
  role = aws_iam_role.master_iam_role.name
}


##################################################################
# IAM ROLE
##################################################################

resource "aws_iam_role" "master_iam_role" {
  name = "${var.application}-master-iam-role"
  path = "/"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF

  tags = merge(var.tags, { "Name" = "${var.application}-master-iam-role" })
}

resource "aws_iam_role_policy" "master_inline_policy" {
  name = "${var.application}-master-inline-policy"
  role = aws_iam_role.master_iam_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": [
        "cloudwatch:PutMetricData"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
        "ec2:DescribeInstances",
        "ec2:DescribeTags",
        "ec2:AttachVolume",
        "s3:GetObject",
        "s3:GetObjectAcl",
        "s3:PutObject",
        "autoscaling:DescribeAutoScalingGroups"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
        "logs:PutLogEvents",
        "logs:PutRetentionPolicy"
      ],
      "Effect": "Allow",
      "Resource": "${aws_cloudwatch_log_group.master_logs.arn}:*"
    },
    {
      "Action": [
        "sts:AssumeRole"
      ],
      "Effect": "Allow",
      "Resource": "*"
    },
    {
      "Action": "ssm:PutParameter",
      "Effect": "Allow",
      "Resource": [
        "arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter${var.ssm_parameter}${var.api_ssm_parameter}"
      ]
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "master_secret_manager_inline_policy" {
  name = "jenkins-secrets-manager-credentials-provider"
  role = aws_iam_role.master_iam_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Sid": "AllowGetSecretValue",
          "Effect": "Allow",
          "Action": "secretsmanager:GetSecretValue",
          "Resource": "arn:aws:secretsmanager:${var.region}:${data.aws_caller_identity.current.account_id}:secret:*",
          "Condition":{
            "ForAllValues:StringEquals":{
                "aws:TagKeys": "jenkins:credentials:type"
            }
          }
      },
      {
          "Sid": "AllowListSecretValue",
          "Effect": "Allow",
          "Action": "secretsmanager:ListSecrets",
          "Resource": [
            "*"
          ]
      }
  ]
}
EOF
}

resource "aws_iam_role_policy" "master_kms_decrypt_allow_inline_policy" {
  name = "decrypt-kms-key-for-ssm-sessions"
  role = aws_iam_role.master_iam_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
      {
          "Sid": "kmsKeyAccess",
          "Effect": "Allow",
          "Action": [
              "kms:Decrypt"
          ],
          "Resource": [
              "${data.aws_kms_key.ssm_key.arn}"
          ]
      }
  ]
}
EOF
}


resource "aws_iam_role_policy_attachment" "master_policy_attachment" {
  role       = aws_iam_role.master_iam_role.name
  policy_arn = data.aws_iam_policy.ssm_policy.arn
}


##################################################################
# Load Balancer
##################################################################

resource "aws_lb_target_group" "master_tg" {
  name = "${var.application}-master-tg"

  port                 = 8080
  protocol             = "HTTP"
  vpc_id               = data.aws_vpc.vpc.id
  deregistration_delay = 30

  health_check {
    port                = "traffic-port"
    path                = "/login"
    timeout             = 120
    healthy_threshold   = 2
    unhealthy_threshold = 10
    matcher             = "200-299"
    interval            = 300
  }

  tags = merge(var.tags, { "Name" = "${var.application}-master-tg" })
}

resource "aws_lb_listener" "master_lb_listener" {
  load_balancer_arn = aws_lb.private_lb.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS-1-2-2017-01"
  certificate_arn   = data.aws_acm_certificate.certificate.arn

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.master_tg.arn
  }
}

resource "aws_lb_listener" "master_http_listener" {
  load_balancer_arn = aws_lb.private_lb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}


##################################################################
# Autoscaling Group
##################################################################

resource "aws_autoscaling_group" "master_asg" {
  max_size = 1
  min_size = 1

  health_check_grace_period = 600
  health_check_type         = "ELB"

  name = "${var.application}-master-asg"

  vpc_zone_identifier = data.aws_subnets.private.ids

  target_group_arns = [aws_lb_target_group.master_tg.arn, var.jks_eks_target_group_arn]

  mixed_instances_policy {

    instances_distribution {
      on_demand_percentage_above_base_capacity = 100
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.master_lt.id
        version            = var.master_lt_version
      }

      override {
        instance_type = var.master_instance_type
      }

    }
  }

  dynamic "tag" {
    for_each = local.tags.master
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

##################################################################
# Launch Template
##################################################################

resource "aws_launch_template" "master_lt" {
  name        = "${var.application}-master-lt"
  description = "${var.application} master launch template"

  iam_instance_profile {
    name = aws_iam_instance_profile.master_ip.name
  }

  credit_specification {
    cpu_credits = "standard"
  }

  image_id      = data.aws_ami.master_ami.id
  key_name      = var.key_name
  ebs_optimized = false

  instance_type = var.master_instance_type
  user_data     = data.cloudinit_config.master_init.rendered

  monitoring {
    enabled = true
  }

  vpc_security_group_ids = [aws_security_group.master_sg.id]

  tag_specifications {
    resource_type = "instance"
    tags          = local.tags.master
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.tags.master
  }
  metadata_options {
    http_tokens = "required"
  }
  tags = merge(var.tags, { "Name" = "${var.application}-master-lt" })

  update_default_version = true
}

#tfsec:ignore:aws-ec2-no-public-egress-sgr tfsec:ignore:aws-ec2-no-public-ingress-sgr tfsec:ignore:aws-vpc-no-public-egress-sgr tfsec:ignore:aws-vpc-no-public-ingress-sgr
resource "aws_security_group" "master_sg" {
  name        = "${var.application}-master-sg"
  description = "${var.application}-master-sg"
  vpc_id      = data.aws_vpc.vpc.id

  ingress {
    from_port       = 8080
    to_port         = 8080
    protocol        = "tcp"
    security_groups = [aws_security_group.lb_sg.id, aws_security_group.agent_sg.id]
    self            = false
    description     = "Allow traffic from Agent"
  }

  ingress {
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [var.bastion_sg_id]
    self            = false
    description     = "Allow SSH traffic Bastion security group"
  }

  ingress {
    from_port       = 49817
    to_port         = 49817
    protocol        = "tcp"
    security_groups = [aws_security_group.agent_sg.id, var.jks_eks_nlb_sg_id]
    self            = false
    description     = "Allow Connection to Agent"
  }

  ingress {
    from_port   = 34981
    to_port     = 34981
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    self        = false
    description = "Jenkins cli"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All protocols"
  }

  tags = merge(var.tags, { "Name" = "${var.application}-master-sg" })
}

#tfsec:ignore:aws-ec2-no-public-egress-sgr tfsec:ignore:aws-ec2-no-public-ingress-sgr tfsec:ignore:aws-vpc-no-public-egress-sgr
resource "aws_security_group" "master_storage_sg" {
  name        = "${var.application}-master-storage-sg"
  description = "${var.application}-master-storage-sg"
  vpc_id      = data.aws_vpc.vpc.id

  ingress {
    from_port       = 2049
    to_port         = 2049
    protocol        = "tcp"
    security_groups = [aws_security_group.master_sg.id]
    self            = false
    description     = "Allow nfs connection to master"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All protocols"
  }

  tags = merge(var.tags, { "Name" = "${var.application}-master-storage-sg" })
}

resource "aws_efs_mount_target" "mount_targets" {
  for_each        = toset(data.aws_subnets.private.ids)
  file_system_id  = aws_efs_file_system.master_efs.id
  subnet_id       = each.key
  security_groups = [aws_security_group.master_storage_sg.id]
}

resource "aws_ssm_parameter" "admin_password" {
  name        = "${var.ssm_parameter}${var.password_ssm_parameter}"
  description = "${var.application}-admin-password"
  type        = "SecureString"
  value       = var.admin_password
}

#tfsec:ignore:aws-cloudwatch-log-group-customer-key
resource "aws_cloudwatch_log_group" "master_logs" {
  name              = "${var.application}-master-logs"
  retention_in_days = var.retention_in_days
  tags              = merge(var.tags, { "Name" = "${var.application}-master-logs" })
}

##################################################################
# Route 53
##################################################################

resource "aws_route53_record" "r53_record" {
  zone_id = data.aws_route53_zone.r53_zone.zone_id
  name    = var.r53_record
  type    = "A"

  alias {
    name                   = "dualstack.${aws_lb.private_lb.dns_name}"
    zone_id                = aws_lb.private_lb.zone_id
    evaluate_target_health = false
  }
}

##################################################################
# Load Balancer
##################################################################

#tfsec:ignore:aws-elb-alb-not-public
resource "aws_lb" "private_lb" {
  name                       = "${var.application}-lb"
  idle_timeout               = 60
  internal                   = true
  security_groups            = [aws_security_group.lb_sg.id]
  subnets                    = data.aws_subnets.private.ids
  enable_deletion_protection = false

  tags                       = merge(var.tags, { "Name" = "${var.application}-private-lb" })
  drop_invalid_header_fields = true
}

#tfsec:ignore:aws-ec2-no-public-egress-sgr tfsec:ignore:aws-ec2-no-public-ingress-sgr tfsec:ignore:aws-vpc-no-public-ingress-sgr tfsec:ignore:aws-vpc-no-public-egress-sgr
resource "aws_security_group" "lb_sg" {
  name        = "${var.application}-lb-sg"
  description = "${var.application}-lb-sg"
  vpc_id      = data.aws_vpc.vpc.id

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = var.cidr_ingress
    description = "HTTPS-443-TCP"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = var.cidr_ingress
    description = "HTTP-80-TCP"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All protocols"
  }

  tags = merge(var.tags, { "Name" = "${var.application}-lb-sg" })
}

