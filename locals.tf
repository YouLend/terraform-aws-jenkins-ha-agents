locals {
  tags = {
    agent              = merge(var.tags, { "Name" = "${var.application}-agent" }),
    agent_multi_deploy = merge(var.tags, { "Name" = "${var.application}-agent-multi-deploy" }),
    agent_qa           = merge(var.tags, { "Name" = "${var.application}-agent-qa" }),
    master             = merge(var.tags, { "Name" = "${var.application}-master" })
  }

  agent_write_files = templatefile("${path.module}/init/agent-write-files.cfg", {
    swarm_label      = "swarm-eu" #All Labels you want Agent to have must be separated with space
    agent_logs       = aws_cloudwatch_log_group.agent_logs.name
    aws_region       = var.region
    executors        = var.executors
    swarm_version    = var.swarm_version
    jenkins_username = var.jenkins_username
  })
  agent_runcmd      = templatefile("${path.module}/init/agent-runcmd.cfg", {
    api_ssm_parameter = "${var.ssm_parameter}${var.api_ssm_parameter}"
    aws_master_region = var.aws_master_region
    master_asg        = aws_autoscaling_group.master_asg.name
    swarm_version     = var.swarm_version
  })
  agent_end         = templatefile("${path.module}/init/agent-end.cfg", {})

  agent_multi_deploy_write_files = templatefile("${path.module}/init/agent-write-files.cfg", {
    swarm_label      = "swarm-multi-deploy"
    agent_logs       = aws_cloudwatch_log_group.agent_logs.name
    aws_region       = var.region
    executors        = var.executors
    swarm_version    = var.swarm_version
    jenkins_username = var.jenkins_username
  })

  qa_agent_write_files = templatefile("${path.module}/init/qa-agent-write-files.cfg", {
    swarm_label      = "swarm-qa" #All Labels you want Agent to have must be separated with space
    agent_logs       = aws_cloudwatch_log_group.agent_logs.name
    aws_region       = var.region
    executors        = var.executors
    swarm_version    = var.swarm_version
    jenkins_username = var.jenkins_username
  })
  qa_agent_runcmd      = templatefile("${path.module}/init/qa-agent-runcmd.cfg", {
    api_ssm_parameter = "${var.ssm_parameter}${var.api_ssm_parameter}"
    aws_master_region = var.aws_master_region
    master_asg        = aws_autoscaling_group.master_asg.name
    swarm_version     = var.swarm_version
  })
  qa_agent_end         = templatefile("${path.module}/init/qa-agent-end.cfg", {})

  master_write_files = templatefile("${path.module}/init/master-write-files.cfg", {
    admin_password           = var.admin_password
    api_ssm_parameter        = "${var.ssm_parameter}${var.api_ssm_parameter}"
    application              = var.application
    auto_update_plugins_cron = var.auto_update_plugins_cron
    aws_region               = var.region
    executors_min            = var.agent_min * var.executors
    master_logs              = aws_cloudwatch_log_group.master_logs.name
    jenkins_name             = var.jenkins_name
  })
  master_runcmd      = templatefile("${path.module}/init/master-runcmd.cfg", {
    admin_password  = var.admin_password
    aws_region      = var.region
    jenkins_version = var.jenkins_version
    master_storage  = aws_efs_file_system.master_efs.id
    env_name        = var.env_name

  })
  master_end         = templatefile("${path.module}/init/master-end.cfg", {})
}