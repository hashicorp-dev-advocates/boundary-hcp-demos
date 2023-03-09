hcp_boundary_cluster_id = "my_cluster_id"

listener "tcp" {
  address = "0.0.0.0:9202"
  purpose = "proxy"
}

worker {
  auth_storage_path = "/boundary/auth_data"

  controller_generated_activation_token = "my_token"

  tags {
    type = ["frontend"]
  }
}