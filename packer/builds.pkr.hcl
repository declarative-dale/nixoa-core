build {
  name    = "nixoa"
  sources = ["xenserver-iso.nixoa"]

  provisioner "file" {
    source      = var.operator_public_key_file
    destination = "/tmp/nixoa-operator.pub"
  }

  provisioner "shell" {
    environment_vars = [
      "NIXOA_REPO_URL=${var.repo_url}",
      "NIXOA_REPO_BRANCH=${var.repo_branch}",
    ]
    script            = "${path.root}/scripts/install-template.sh"
    expect_disconnect = true
  }

  provisioner "shell" {
    execute_command = "sudo -n env XO_READINESS_GRACE_SECONDS=240 bash '{{ .Path }}'"
    script          = "${path.root}/scripts/verify-template.sh"
  }

  provisioner "shell" {
    execute_command   = "sudo -n bash '{{ .Path }}'"
    inline            = ["systemctl reboot"]
    expect_disconnect = true
  }

  provisioner "shell" {
    execute_command = "sudo -n bash '{{ .Path }}'"
    script          = "${path.root}/scripts/verify-template.sh"
  }

  provisioner "shell" {
    execute_command = "sudo -n bash '{{ .Path }}'"
    script          = "${path.root}/scripts/seal-template.sh"
  }
}
