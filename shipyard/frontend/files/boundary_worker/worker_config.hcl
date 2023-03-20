  disable_mlock = true
  log_level = "debug"

  hcp_boundary_cluster_id = "739d93f9-7f1c-474d-8524-931ab199eaf8"

  listener "tcp" {
    address = "0.0.0.0:9202"
    purpose = "proxy"
  }

  worker {
    auth_storage_path="/boundary/auth_data"

    controller_generated_activation_token = "neslat_2Kr7PHmjwDbq7J5tXt7ANUtwgQvee6AhvaPMveCyWuqq2S3P5yUH5YaS4oknAtB9TuPrvdy97PFndTH4SFAyscBHiq5M9"
  
    tags {
      type   = ["vm"]
    }
  }
