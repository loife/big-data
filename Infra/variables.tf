variable "region" {
  type        = string
  default     = "eu-central-1"
}

variable "allowed_cidrs" {
  type        = list(string)
}

variable "instance_type" {
  type        = string
  default     = "t3.micro"
}

variable "key_name" {
  type        = string
  default     = ""
}

variable "db_user" {
  description = "Korisnicko ime PostgreSQL baze"
  type        = string
  default     = "superset_user"
}

variable "db_password" {
  description = "Lozinka PostgreSQL baze"
  type        = string
  sensitive   = true
}

variable "superset_secret_key" {
  type        = string
  sensitive   = true
}

variable "superset_admin_password" {
  description = "Lozinka za 'admin' nalog u Superset web UI"
  type        = string
  sensitive   = true
}
