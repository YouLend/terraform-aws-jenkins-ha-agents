##################################################################
# AutoScaling Group
##################################################################

resource "aws_autoscaling_group" "agent_multi_deploy_asg" {

  max_size = var.agent_multi_deploy_max
  min_size = var.agent_min

  health_check_grace_period = 300
  health_check_type         = "EC2"

  name = "${var.application}-multi-deploy-agent-asg"

  vpc_zone_identifier = data.aws_subnets.private.ids

  mixed_instances_policy {

    instances_distribution {
      on_demand_percentage_above_base_capacity = (var.enable_spot_insances == 1) ? 0 : 100
      #spot_instance_pools must be at least 2, since spot_allocation_strategy defaults to "lowest-price" when not set. If we set it to anything other than "lowest-price", spot_instance_pools must be 0.
      spot_instance_pools = (var.enable_spot_insances == 1) ? length(var.agent_multi_deploy_instance_type) : 2
    }

    launch_template {
      launch_template_specification {
        launch_template_id = aws_launch_template.agent_multi_deploy_lt.id
        version            = var.agent_lt_version
      }

      override {
        instance_type = var.agent_multi_deploy_instance_type
      }

    }
  }

  dynamic "tag" {
    for_each = local.tags.agent_multi_deploy
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

resource "aws_launch_template" "agent_multi_deploy_lt" {
  name        = "${var.application}-agent-multi-deploy-lt"
  description = "${var.application} database agent launch template"

  iam_instance_profile {
    name = aws_iam_instance_profile.agent_ip.name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    no_device   = true

    ebs {
      volume_size           = var.agent_multi_deploy_volume_size
      encrypted             = true
      delete_on_termination = true
      volume_type           = "gp3"
    }
  }

  image_id      = data.aws_ami.agent_ami.id
  key_name      = var.key_name
  ebs_optimized = false

  instance_type = var.agent_multi_deploy_instance_type
  user_data     = data.cloudinit_config.agent_multi_deploy_init.rendered

  monitoring {
    enabled = true
  }

  vpc_security_group_ids = [aws_security_group.agent_sg.id]

  tag_specifications {
    resource_type = "instance"
    tags          = local.tags.agent_multi_deploy
  }

  tag_specifications {
    resource_type = "volume"
    tags          = local.tags.agent_multi_deploy
  }

  metadata_options {
    http_tokens = "required"
  }
  tags                   = merge(var.tags, { "Name" = "${var.application}-agent-multi-deploy-lt" })
  update_default_version = true
}

##################################################################
# AutoScaling Policy
##################################################################


resource "aws_autoscaling_policy" "agent_multi_deploy_scale_up_policy" {
  name                   = "${var.application}-agent-multi-deploy-up-policy"
  scaling_adjustment     = var.scale_up_number_multi_deploy
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 150
  autoscaling_group_name = aws_autoscaling_group.agent_multi_deploy_asg.name
}

resource "aws_autoscaling_policy" "agent_multi_deploy_scale_down_policy" {
  name                   = "${var.application}-agent-multi-deploy-down-policy"
  scaling_adjustment     = var.scale_down_number_multi_deploy
  adjustment_type        = "ChangeInCapacity"
  cooldown               = 180
  autoscaling_group_name = aws_autoscaling_group.agent_multi_deploy_asg.name
}

##################################################################
# Scheduled Actions
##################################################################

# Create a scheduled scaling policy to scale up the ASG during office hours
resource "aws_autoscaling_schedule" "agent_multi_deploy_asg_scale_up" {
  scheduled_action_name  = "agent-multi-deploy-asg-scale-up"
  min_size               = var.agent_min
  max_size               = var.agent_multi_deploy_max
  desired_capacity       = var.agent_multi_deploy_max
  recurrence             = "0 7 * * 1-5" # Monday-Friday at 7am UTC
  time_zone              = "Europe/London"
  autoscaling_group_name = aws_autoscaling_group.agent_multi_deploy_asg.name
}

# Create a scheduled scaling policy to scale down the ASG during out-of-office hours
resource "aws_autoscaling_schedule" "agent_multi_deploy_asg_scale_down" {
  scheduled_action_name  = "agent-multi-deploy-asg-scale-down"
  min_size               = var.agent_min
  max_size               = var.agent_min
  desired_capacity       = var.agent_min
  recurrence             = "0 23 * * *" # every day at 11pm UTC
  time_zone              = "Europe/London"
  autoscaling_group_name = aws_autoscaling_group.agent_multi_deploy_asg.name
}
