terraform {
  backend "s3" {
    bucket       = "ecommerce-tf-state-mgmt"
    key          = "projects/snowflake-privatelink/network-policy/terraform.tfstate"
    region       = "af-south-1"
    use_lockfile = true
    encrypt      = true
  }
}
