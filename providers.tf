terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region                   = "us-east-1"
  shared_config_files      = ["C:/Users/Asus/.aws/config"]
  shared_credentials_files = ["C:/Users/Asus/.aws/credentials"]
}
