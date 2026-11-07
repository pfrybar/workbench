terraform {
  required_providers {
    coder = {
      source = "coder/coder"
    }
    docker = {
      source = "kreuzwerker/docker"
    }
  }
}

locals {
  username = data.coder_workspace_owner.me.name
}

variable "docker_socket" {
  default     = ""
  description = "(Optional) Docker socket URI"
  type        = string
}

variable "cert_path" {
  default     = ""
  description = "(Optional) Directory where Docker certs can be found"
  type        = string
}

variable "image" {
  default     = "ghcr.io/pfrybar/workbench:base"
  description = "Workspace image in a registry. Each workspace start looks up the tag's current digest and pulls that build if the host doesn't have it."
  type        = string
}

provider "docker" {
  # Defaulting to null if the variable is an empty string lets us have an optional variable without having to set our own default
  host      = var.docker_socket != "" ? var.docker_socket : null
  cert_path = var.cert_path != "" ? var.cert_path : null
}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

# Each workspace owner's own setup. Mutable, so it can change on any start.
data "coder_parameter" "mise_repo" {
  name         = "mise_repo"
  display_name = "mise repository"
  description  = "Git repository with your tools and dotfiles, which `mise bootstrap` applies on every start. Its mise config must be at the root, e.g. https://github.com/you/mise-dotfiles. Empty for none."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 1
}

data "coder_parameter" "mise_env" {
  name         = "mise_env"
  display_name = "mise environments"
  description  = "Comma-separated mise environments to apply from that repository, such as `workbench`. Empty for none."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 2
}

data "coder_parameter" "paseo" {
  name         = "paseo"
  display_name = "Start Paseo"
  description  = "Start the Paseo daemon, which runs coding agents for the Paseo app."
  type         = "bool"
  default      = "true"
  mutable      = true
  order        = 3
}

data "coder_parameter" "paseo_relay" {
  name         = "paseo_relay"
  display_name = "Paseo relay"
  description  = "host:port of a Paseo relay to connect through over TLS, e.g. relay.example.com:443. Empty leaves the daemon's relay settings as they are."
  type         = "string"
  default      = ""
  mutable      = true
  order        = 4
}

# The image starts nothing: the scripts below start Docker, apply the owner's
# mise repository and start Paseo, and stop them again.
resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  # For the scripts. Passed as variables so the values never need quoting.
  env = {
    WORKBENCH_MISE_REPO   = data.coder_parameter.mise_repo.value
    WORKBENCH_MISE_ENV    = data.coder_parameter.mise_env.value
    WORKBENCH_PASEO       = data.coder_parameter.paseo.value
    WORKBENCH_PASEO_RELAY = data.coder_parameter.paseo_relay.value
  }

  # The following metadata blocks are optional. They are used to display
  # information about your workspace in the dashboard. You can remove them
  # if you don't want to display any information.
  # For basic resources, you can use the `coder stat` command.
  # If you need more control, you can write your own script.
  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "3_home_disk"
    script       = "coder stat disk --path $${HOME}"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "4_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "5_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Load Average (Host)"
    key          = "6_load_host"
    # get load avg scaled by number of cores
    script   = <<EOT
      echo "`cat /proc/loadavg | awk '{ print $1 }'` `nproc`" | awk '{ printf "%0.2f", $1/$2 }'
    EOT
    interval = 60
    timeout  = 1
  }

  metadata {
    display_name = "Swap Usage (Host)"
    key          = "7_swap_host"
    script       = <<EOT
      free -b | awk '/^Swap/ { printf("%.1f/%.1f", $3/1024.0/1024.0/1024.0, $2/1024.0/1024.0/1024.0) }'
    EOT
    interval     = 10
    timeout      = 1
  }
}

data "coder_parameter" "git_repo" {
  name         = "git_repo"
  display_name = "(Optional) Git repository to clone"
  default      = ""
}

# See https://registry.coder.com/modules/coder/git-clone
module "git-clone" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/git-clone/coder"
  version  = "~> 2.0"
  agent_id = coder_agent.main.id
  url      = data.coder_parameter.git_repo.value
}

# Docker-in-Docker: the workspace's own daemon, which sysbox allows without
# a privileged container. Logins don't wait for it.
resource "coder_script" "docker" {
  agent_id     = coder_agent.main.id
  display_name = "Docker"
  icon         = "/icon/docker.svg"
  run_on_start = true
  timeout      = 120
  script       = <<-EOT
    sudo /etc/init.d/docker start || exit 1
    tries=0
    until docker info >/dev/null 2>&1; do
      tries=$((tries + 1))
      if [ "$tries" -gt 60 ]; then
        echo "dockerd isn't answering; see /var/log/docker.log" >&2
        exit 1
      fi
      sleep 1
    done
  EOT
}

# The owner's tools and dotfiles, then Paseo. One script, so Paseo starts
# after the agents it runs are installed; Paseo still starts if mise fails.
# It gets Coder's user secrets as environment variables, and so do the
# agents Paseo starts.
resource "coder_script" "setup" {
  agent_id           = coder_agent.main.id
  display_name       = "Tools and Paseo"
  icon               = "/icon/terminal.svg"
  run_on_start       = true
  start_blocks_login = true
  timeout            = 1800
  script             = <<-EOT
    result=0

    if [ -n "$WORKBENCH_MISE_REPO" ]; then
      # --save-env keeps the environments active for every later mise command.
      if [ -n "$WORKBENCH_MISE_ENV" ]; then
        set -- --env "$WORKBENCH_MISE_ENV" --save-env
      fi
      echo "Applying $WORKBENCH_MISE_REPO"
      mise bootstrap --from "$WORKBENCH_MISE_REPO" --from-dir "$HOME/.dotfiles" \
        --config-dir . --update --yes "$@" || result=1
    fi

    if [ "$WORKBENCH_PASEO" = true ]; then
      if [ -n "$WORKBENCH_PASEO_RELAY" ]; then
        for key in endpoint publicEndpoint; do
          paseo daemon config set "daemon.relay.$key" "$WORKBENCH_PASEO_RELAY" >/dev/null || result=1
        done
        for key in enabled useTls publicUseTls; do
          paseo daemon config set "daemon.relay.$key" true >/dev/null || result=1
        done
      fi
      paseo daemon start || result=1
    fi

    exit "$result"
  EOT
}

# Runs when the agent gets SIGTERM, which destroy_grace_seconds on the
# container makes Docker send before removing it.
resource "coder_script" "shutdown" {
  agent_id     = coder_agent.main.id
  display_name = "Shut down"
  icon         = "/icon/terminal.svg"
  run_on_stop  = true
  timeout      = 25
  script       = <<-EOT
    result=0
    paseo daemon stop || result=1
    if pgrep -x dockerd >/dev/null; then
      sudo /etc/init.d/docker stop || result=1
    fi
    exit "$result"
  EOT
}

# See https://registry.coder.com/modules/coder/code-server
module "code-server" {
  count  = data.coder_workspace.me.start_count
  source = "registry.coder.com/coder/code-server/coder"

  # This ensures that the latest non-breaking version of the module gets downloaded, you can also pin the module version to prevent breaking changes in production.
  version = "~> 1.0"

  agent_id = coder_agent.main.id
  order    = 1
}

# Looks up the tag's current digest when a workspace starts. Only on start:
# stopping a workspace doesn't need the registry.
data "docker_registry_image" "workbench" {
  count = data.coder_workspace.me.start_count
  name  = var.image
}

locals {
  # var.image without its tag or digest, e.g. ghcr.io/pfrybar/workbench.
  image_repository = replace(replace(var.image, "/@.*$/", ""), "/:[^:/]+$/", "")
}

resource "docker_image" "workbench" {
  count = data.coder_workspace.me.start_count
  # By digest, not tag: the provider uses any local image with the same name
  # without pulling, so a tag would stay on whichever build the host pulled
  # first. A new build has a digest the host hasn't seen, so it gets pulled.
  name = "${local.image_repository}@${data.docker_registry_image.workbench[0].sha256_digest}"
  # Other workspaces may still be running the previous build.
  keep_locally = true
}

resource "docker_volume" "home_volume" {
  name = "coder-${data.coder_workspace.me.id}-home"
  # Protect the volume from being deleted due to changes in attributes.
  lifecycle {
    ignore_changes = all
  }
  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  # This field becomes outdated if the workspace is renamed but can
  # be useful for debugging or cleaning out dangling volumes.
  labels {
    label = "coder.workspace_name_at_creation"
    value = data.coder_workspace.me.name
  }
}

resource "docker_container" "workspace" {
  count = data.coder_workspace.me.start_count
  image = docker_image.workbench[0].image_id
  # Uses lower() to avoid Docker restriction on container names.
  name = "coder-${data.coder_workspace_owner.me.name}-${lower(data.coder_workspace.me.name)}"
  # Hostname makes the shell more user friendly: dev@my-workspace:~$
  hostname = data.coder_workspace.me.name
  # A command rather than an entrypoint, so the image's entrypoint (tini) runs
  # the agent and passes it SIGTERM when the container stops.
  # Use the docker gateway if the access URL is 127.0.0.1
  command = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env     = ["CODER_AGENT_TOKEN=${coder_agent.main.token}"]
  runtime = "sysbox-runc"
  # SIGTERM first, so the agent's stop script can stop Paseo and dockerd.
  # Without it, the container is removed at once.
  destroy_grace_seconds = 30
  host {
    host = "host.docker.internal"
    ip   = "host-gateway"
  }
  volumes {
    container_path = "/home/dev"
    volume_name    = docker_volume.home_volume.name
    read_only      = false
  }
  networks_advanced {
    name = "coder-workspaces"
  }

  # Add labels in Docker to keep track of orphan resources.
  labels {
    label = "coder.owner"
    value = data.coder_workspace_owner.me.name
  }
  labels {
    label = "coder.owner_id"
    value = data.coder_workspace_owner.me.id
  }
  labels {
    label = "coder.workspace_id"
    value = data.coder_workspace.me.id
  }
  labels {
    label = "coder.workspace_name"
    value = data.coder_workspace.me.name
  }
}
