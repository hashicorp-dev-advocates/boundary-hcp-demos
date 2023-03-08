module "frontend" {
  disabled = !var.frontend_enabled

  source = "./frontend"
}

module "backend" {
  disabled = !var.backend_enabled

  source = "./backend"
}

module "vault" {
  source = "./vault"
}

variable "frontend_enabled" {
  default = true
}

variable "backend_enabled" {
  default = true
}