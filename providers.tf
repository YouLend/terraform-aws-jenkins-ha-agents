terraform {

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.42"
    }
    cloudinit = {
      source  = "hashicorp/cloudinit"
      version = ">= 2.3.4"
    }
  }
}

provider "aws" {
  region = var.region
}
