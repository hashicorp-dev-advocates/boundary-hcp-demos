container "boundary_worker_frontend" {
  network {
    name = "network.frontend"
  }

  image {
    name = "nicholasjackson/boundary-worker-hcp:v0.12.0"
  }

  command = ["tail", "-f", "/dev/null"]

  volume {
    source      = "./files/boundary_worker"
    destination = "/boundary"
  }

  env {
    key   = "worker_name"
    value = "frontend"
  }

  env {
    key   = "cluster_id"
    value = var.boundary_cluster_id
  }

  env {
    key   = "username"
    value = var.boundary_username
  }

  env {
    key   = "password"
    value = var.boundary_password
  }

  env {
    key   = "auth_method_id"
    value = var.boundary_auth_method_id
  }
}