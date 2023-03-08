  disable_mlock = true
  log_level = "debug"

  hcp_boundary_cluster_id = "739d93f9-7f1c-474d-8524-931ab199eaf8"

  listener "tcp" {
    address = "0.0.0.0:9202"
    purpose = "proxy"
  }

  worker {
    auth_storage_path="/boundary/auth_data"

    controller_generated_activation_token = "{"kind":"InvalidArgument","message":"Invalid request. Request attempted to make second resource with the same field value that must be unique."}"
  
    tags {
      type   = ["vault"]
    }
  }
