# Image builds for `docker buildx bake`. With no platform set, each machine
# builds its own architecture (amd64 on the Coder host, arm64 on a Mac).

group "default" {
  targets = ["base"]
}

target "base" {
  context = "images/base"
  tags    = ["workbench:base"]
}
