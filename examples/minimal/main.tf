provider "aws" {
  region = "eu-west-1"
}

module "vpc" {
  source = "../../"

  name = "example-minimal"
  cidr = "10.10.0.0/16"
}
