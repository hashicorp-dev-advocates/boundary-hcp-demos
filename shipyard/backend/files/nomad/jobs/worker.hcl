job "boundary_worker" {
  datacenters = ["dc1"]

  type = "service"

  group "worker" {
    count = 1

    restart {
      # The number of attempts to run the job within the specified interval.
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    ephemeral_disk {
      size = 30
    }

    task "worker" {
      driver = "docker"

      vault {
        policies = ["boundary-worker"]
      }

      template {
        data = <<-EOF
          disable_mlock = true

          hcp_boundary_cluster_id = "739d93f9-7f1c-474d-8524-931ab199eaf8"

          listener "tcp" {
            address = "0.0.0.0:9202"
            purpose = "proxy"
          }

          worker {
            auth_storage_path="/boundary/auth_data"
            {{with secret "boundary/creds/worker" (env "NOMAD_ALLOC_ID" | printf "worker_name=%s") -}}
              controller_generated_activation_token = "{{.Data.activation_token}}"
            {{- end}}
  
            tags {
              environment   = ["nomad"]
            }
          }
        EOF

        destination = "local/config.hcl"
      }

      logs {
        max_files     = 2
        max_file_size = 10
      }

      config {
        image   = "hashicorp/boundary-worker-hcp:0.12.0-hcp"
        command = "boundary-worker"
        args = [
          "server",
          "-config",
          "local/config.hcl"
        ]
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 512 # 512MB
      }
    }
  }
}