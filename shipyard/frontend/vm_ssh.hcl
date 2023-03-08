container "vm" {
  network {
    name = "network.frontend"
  }

  image {
    name = "nicholasjackson/ubuntu_ssh:v0.0.1"
  }

  volume {
    source      = "./files/vm/supervisor.conf"
    destination = "/etc/supervisor/conf.d/ssh.conf"
  }

  volume {
    source      = data("temp")
    destination = "/init"
  }

  port {
    host   = 2222
    local  = 22
    remote = 22
  }
}

template "vm_init" {
  source = <<-EOF
    #! /bin/bash
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    echo "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQC51FmWnibF0gLoYejflMbTWXjY6620EmQ34Mo7LudLFGoQFVE8GqP6x1DCLtXl00TcZdZ/1wVYgD1VjSv08gHKLtRA1+SdbEVOTRov2PZkPHSYx9tEl/sdPPPFHl8869kFvSgbVzfi2PY4CHKd+lpCrxjvimxedavwsB9fVLdYw5EqCe5/3KUiWLFJhOH2lz506J/l1t7rdGpZiCW3A/k0HiZR11kek1kBvqjWbGdaaZTHBoaS8vdqP3XHRrxSBz8NhcV9dYqBKoFG//ni/VQyK39rT8gTHkGL6bkF7F08gwlN7tg3IRp3dSgT9jhNuOPv8MtxaTamnm0BgVdLjkefa7VlaDW79WCqCDoIUUDPz1/jTb8lwctyOrrVmp2N4xNI6Nvw0y84oyVS+zTSraV2hvysSqrif6uwYZGiA6QY/Cv5eqnJE+S891JNn7mIytGfQFQH+fVUxb3Yw4qFzmMHM+4MGXjO2DPlfs2yFJ2GdkbJ1wWIzA5ehrV6hd2ySyaxX5Sh0ZZUSf1j4Xm+L2TP1W6bcCsNbZSERx7/byFsbGgkdfhksYtQVztOKSvWUkCPnqUaYdJUQLlMk7NqVvpBPyIs05cQpPZsPg1xhDa4bAd2FCOST2VBO28wr96tFvs0uciRfyJYCUENKlvveDJ4CYGpEDnQ6mSwn1zjVwWNKQ== nicj@WINDOZE" >> ~/.ssh/authorized_keys
    chmod 600 ~/.ssh/authorized_keys
  EOF

  destination = "${data("temp")}/init.sh"
}

exec_remote "vm_init" {
  depends_on = ["template.vm_init"]
  target     = "container.vm"

  cmd = "/bin/bash"
  args = [
    "/init/init.sh"
  ]
}
