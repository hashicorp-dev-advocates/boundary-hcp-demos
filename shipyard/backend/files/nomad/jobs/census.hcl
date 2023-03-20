job "census" {
  datacenters = ["dc1"]

  type = "service"

  group "census" {
    count = 1

    restart {
      # The number of attempts to run the job within the specified interval.
      attempts = 2
      interval = "30m"
      delay    = "15s"
      mode     = "fail"
    }

    network {
      port "census" {
        static = 3000
      }
    }

    ephemeral_disk {
      size = 30
    }

    task "census" {
      driver = "docker"

      vault {
        policies = ["boundary-census"]
      }

      template {
        data = <<-EOF
          {{ with secret "secret/data/census" }}
          config "controller" {
            nomad {
              address = "http://{{ env "NOMAD_IP_census" }}:4646"
            }

            boundary {
              enterprise = "true"
              username = "{{.Data.data.boundary_username}}"
              password = "{{.Data.data.boundary_password}}"
              address  = "https://739d93f9-7f1c-474d-8524-931ab199eaf8.boundary.hashicorp.cloud"

              org_id          = "{{.Data.data.boundary_org_id}}"
              auth_method_id  = "{{.Data.data.boundary_auth_method_id}}"
              default_project = "Boundary Demo"
              default_groups  = ["developers"]
              default_egress_filter = <<EOT
              "nomad" in "/tags/environment"
              EOT
            }
          }
          {{end}}
        EOF

        destination = "local/config.hcl"
      }

      logs {
        max_files     = 2
        max_file_size = 10
      }

      config {
        image = "nicholasjackson/census:e3651dac"
        args = [
          "-config",
          "local/config.hcl"
        ]
      }

      resources {
        cpu    = 500 # 500 MHz
        memory = 256 # 256MB
      }
    }
  }
}