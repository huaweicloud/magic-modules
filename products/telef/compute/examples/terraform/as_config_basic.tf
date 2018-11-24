resource "telefonicaopencloud_compute_keypair_v2" "keypair" {
  name = "terraform_compute_keypair_test_env-val"
}

resource "telefonicaopencloud_compute_as_config" "config" {
  name = "terraform_compute_as_config_test_env-val"
  config =
    image = "env-OS_IMAGE_ID"
    flavor = "s1.medium"
    disk =
      - size = 40
        volume_type = "SATA"
        disk_type = "SYS"
    key_name = "${telefonicaopencloud_compute_keypair_v2.keypair.name}"
}
