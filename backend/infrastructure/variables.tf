# input variables stored in terraform.tfvars
variable "marketmate_db_pass" {
  type = string
  # hides the value in console outputs
  sensitive = true
}

variable "marketmate_db_user" {
  type = string
}

variable "marketmate_db_name" {
  type = string
}

variable "jwt_secret_key" {
  type      = string
  sensitive = true
}