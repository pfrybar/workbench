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
  description = "Workspace image in a registry. A workspace start pulls a new build whenever the tag has moved."
  type        = string
}

variable "dotfiles_uri" {
  default     = "https://github.com/pfrybar/dotfiles"
  description = "Dotfiles repository the image applies on every start, e.g. https://github.com/you/dotfiles. Empty for none."
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

# The image's entrypoint starts Docker and prepares $HOME, so there's no startup_script.
resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

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

# Shows the image's startup log (dotfiles, Claude Code, Codex, pi, asdf
# plugins) in the dashboard, and holds logins until it's finished.
resource "coder_script" "workbench_setup" {
  agent_id           = coder_agent.main.id
  display_name       = "Workbench setup"
  run_on_start       = true
  start_blocks_login = true
  timeout            = 600
  script             = <<-EOT
    # workbench-init writes this once its background part is done.
    state=$HOME/.cache/workbench/setup-status
    while [ ! -f "$state" ]; do sleep 1; done
    # Print this start's section of the log.
    awk '/^== /{run=""} {run=run $0 "\n"} END{printf "%s", run}' "$HOME/.cache/workbench/setup.log"
    [ "$(cat "$state")" = ok ]
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

# Looks up the tag's current digest when a workspace starts, so a new build of
# the tag gets pulled. Only on start: stopping a workspace doesn't need the
# registry.
data "docker_registry_image" "workbench" {
  count = data.coder_workspace.me.start_count
  name  = var.image
}

resource "docker_image" "workbench" {
  count         = data.coder_workspace.me.start_count
  name          = data.docker_registry_image.workbench[0].name
  pull_triggers = [data.docker_registry_image.workbench[0].sha256_digest]
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
  # A command rather than an entrypoint, so the image's entrypoint (which starts
  # Docker) runs first and then starts the agent.
  # Use the docker gateway if the access URL is 127.0.0.1
  command = ["sh", "-c", replace(coder_agent.main.init_script, "/localhost|127\\.0\\.0\\.1/", "host.docker.internal")]
  env = [
    "CODER_AGENT_TOKEN=${coder_agent.main.token}",
    "WORKBENCH_DOTFILES_REPO=${var.dotfiles_uri}",
  ]
  runtime = "sysbox-runc"
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
