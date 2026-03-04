# input variables stored in terraform.tfvars
variable "postgres_password" {
  type = string
  # hides the value in console outputs
  sensitive = true
}

variable "jwt_secret_key" {
  type      = string
  sensitive = true
}

variable "marketmate_db_user" {
  type = string
}

variable "marketmate_db_name" {
  type = string
}
