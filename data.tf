
##################################################################
# Agent User Data
##################################################################
data "cloudinit_config" "agent_init" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "agent.cfg"
    content_type = "text/cloud-config"
    content      = local.agent_write_files
  }

  part {
    content_type = "text/cloud-config"
    content      = local.agent_runcmd
  }

  part {
    content_type = "text/cloud-config"
    content      = var.extra_agent_userdata
    merge_type   = var.extra_agent_userdata_merge
  }

  part {
    content_type = "text/cloud-config"
    content      = local.agent_end
    merge_type   = "list(append)+dict(recurse_array)+str()"
  }
}

##################################################################
# QA Agent User Data
##################################################################
data "cloudinit_config" "qa_agent_init" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "qa_agent.cfg"
    content_type = "text/cloud-config"
    content      = local.qa_agent_write_files
  }

  part {
    content_type = "text/cloud-config"
    content      = local.qa_agent_runcmd
  }

  part {
    content_type = "text/cloud-config"
    content      = var.extra_agent_userdata
    merge_type   = var.extra_agent_userdata_merge
  }

  part {
    content_type = "text/cloud-config"
    content      = local.qa_agent_end
    merge_type   = "list(append)+dict(recurse_array)+str()"
  }
}

##################################################################
# Master User Data
##################################################################
data "cloudinit_config" "master_init" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "master.cfg"
    content_type = "text/cloud-config"
    content      = local.master_write_files
  }

  part {
    content_type = "text/cloud-config"
    content      = var.extra_master_write_files
    merge_type   = "list(append)+dict(recurse_array)+str()"
  }

  part {
    content_type = "text/cloud-config"
    content      = local.master_runcmd
  }

  part {
    content_type = "text/cloud-config"
    content      = var.extra_master_userdata
    merge_type   = var.extra_master_userdata_merge
  }
  part {
    content_type = "text/cloud-config"
    content      = local.master_end
    merge_type   = "list(append)+dict(recurse_array)+str()"
  }

}

resource "aws_efs_file_system" "master_efs" {
  creation_token   = "${var.application}-master-efs"
  encrypted        = true
  performance_mode = "generalPurpose"

  throughput_mode                 = var.efs_mode
  provisioned_throughput_in_mibps = var.efs_mode == "provisioned" ? var.efs_provisioned_throughput : null

  tags = merge(var.tags, { "Name" = "${var.application}-master-efs" })
}

##################################################################
# Database Agent User Data
##################################################################

data "cloudinit_config" "agent_multi_deploy_init" {
  gzip          = true
  base64_encode = true

  part {
    filename     = "agent.cfg"
    content_type = "text/cloud-config"
    content      = local.agent_multi_deploy_write_files
  }

  part {
    content_type = "text/cloud-config"
    content      = local.agent_runcmd
  }

  part {
    content_type = "text/cloud-config"
    content      = var.extra_agent_userdata
    merge_type   = var.extra_agent_userdata_merge
  }

  part {
    content_type = "text/cloud-config"
    content      = local.agent_end
    merge_type   = "list(append)+dict(recurse_array)+str()"
  }
}

##################################################################
# Other Data
##################################################################

data "aws_caller_identity" "current" {}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  tags = {
    Name = var.private_subnet_name
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.vpc.id]
  }

  tags = {
    Name = var.public_subnet_name
  }
}

data "aws_acm_certificate" "certificate" {
  domain   = var.ssl_certificate
  statuses = ["ISSUED"]
}

data "aws_iam_policy" "ssm_policy" {
  arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_route53_zone" "r53_zone" {
  name         = var.domain_name
  private_zone = true
}

data "aws_vpc" "vpc" {
  tags = {
    Name = var.vpc_name
  }
}

data "aws_ami" "amzn2_ami" {
  most_recent = true
  owners      = [var.ami_owner]

  filter {
    name   = "name"
    values = [var.ami_name]
  }
}

data "aws_kms_key" "ssm_key" {
  key_id = var.ssm_kms_key
}

