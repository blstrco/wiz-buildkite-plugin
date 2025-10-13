#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"
load "${BATS_TEST_DIRNAME}/../lib/plugin.bash"
load "${BATS_TEST_DIRNAME}/../lib/shared.bash"

# Uncomment the following line to debug stub failures
# export DOCKER_STUB_DEBUG=/dev/tty
# export BUILDKITE_AGENT_STUB_DEBUG=/dev/tty

setup() {
  export WIZ_DIR="$HOME/.wiz"
  export WIZ_CLIENT_ID="test"
  export WIZ_CLIENT_SECRET="secret"
  export BUILDKITE_JOB_ID="1234-abcd"
  export BUILDKITE_BUILD_ID="1234-abcd"
  export BUILDKITE_LABEL="iac-scan"
}

teardown() {
  if [ -d "$WIZ_DIR" ]; then
    rm -rf "$WIZ_DIR"
  fi

  if [ -d result ]; then
    rm -rf result
  fi

  # shellcheck disable=SC2144
  if [ -a *-annotation.md ]; then
    rm *-annotation.md
  fi

  if [ -a check-file ]; then
    rm check-file
  fi
}

@test "Missing scan type" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE=""

  run "$PWD/hooks/post-command"

  assert_failure
  assert_output "+++ 🚨 Missing scan type. Possible values: 'iac', 'docker', 'dir'"
}

@test "Docker Scan without BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  unset BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS

  run "$PWD/hooks/post-command"
  assert_output "+++ 🚨 Missing image address, docker scans require an address to pull the image"

  assert_failure
}

@test "Docker Scan" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="ubuntu:22.04"

  stub uname "-m : echo 'unknown'"

  mkdir -p "$WIZ_DIR"
  touch "$WIZ_DIR/key"

  stub docker \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli -e WIZ_CLIENT_ID -e WIZ_CLIENT_SECRET wiziocli.azurecr.io/wizcli:latest auth : exit 0' \
    'pull "ubuntu:22.04" : exit 0' \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli,readonly --mount type=bind,src=/plugin,dst=/scan --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock,readonly wiziocli.azurecr.io/wizcli:latest docker scan --image ubuntu:22.04 --policy-hits-only --format=human --output=/scan/result/output,human : echo "Docker image scanned without policy hits"'
  
  stub buildkite-agent \
    'annotate --append --context 'ctx-wiz-docker-success' --style 'success' : echo "Annotated Build"'

  run "$PWD/hooks/post-command"
  
  assert_success

  assert_output --partial "Authenticated successfully"
  assert_output --partial "Docker image scanned without policy hits"
  assert_output --partial "Annotated Build"

  unstub uname
  unstub docker
  unstub buildkite-agent
}

@test "IaC Scan" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="iac"
  export BUILDKITE_PLUGIN_WIZ_PATH="iac/to/scan"

  stub uname "-m : echo 'unknown'"

  mkdir -p "$WIZ_DIR"
  touch "$WIZ_DIR/key"

  stub docker \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli -e WIZ_CLIENT_ID -e WIZ_CLIENT_SECRET wiziocli.azurecr.io/wizcli:latest auth : exit 0' \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli,readonly --mount type=bind,src=/plugin,dst=/scan wiziocli.azurecr.io/wizcli:latest iac scan --name 1234-abcd --path /scan/iac/to/scan --format=human --output=/scan/result/output,human : echo "IaC scanned without policy hits"'
  
  stub buildkite-agent \
    'annotate --append --context 'ctx-wiz-iac-success' --style 'success' : echo "Annotated Build"' \
    'artifact upload check-file : echo "Uploaded check-file"'

  run "$PWD/hooks/post-command"
  
  assert_success

  assert_output --partial "Authenticated successfully"
  assert_output --partial "IaC scanned without policy hits"
  assert_output --partial "Annotated Build"
  assert_output --partial "Uploaded check-file"

  unstub uname
  unstub docker
  unstub buildkite-agent
}

@test "Directory Scan" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="dir"
  export BUILDKITE_PLUGIN_WIZ_PATH="dir/to/scan"

  stub uname "-m : echo 'unknown'"

  mkdir -p "$WIZ_DIR"
  touch "$WIZ_DIR/key"

  stub docker \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli -e WIZ_CLIENT_ID -e WIZ_CLIENT_SECRET wiziocli.azurecr.io/wizcli:latest auth : exit 0' \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli,readonly --mount type=bind,src=/plugin,dst=/scan wiziocli.azurecr.io/wizcli:latest dir scan --name 1234-abcd --path /scan/dir/to/scan --format=human --output=/scan/result/output,human : echo "Directory scanned without policy hits"'
  
  stub buildkite-agent \
    'annotate --append --context 'ctx-wiz-dir-success' --style 'success' : echo "Annotated Build"' \
    'artifact upload check-file : echo "Uploaded check-file"'

  run "$PWD/hooks/post-command"
  
  assert_success

  assert_output --partial "Authenticated successfully"
  assert_output --partial "Directory scanned without policy hits"
  assert_output --partial "Annotated Build"
  assert_output --partial "Uploaded check-file"

  unstub uname
  unstub docker
  unstub buildkite-agent
}

@test "Directory Scan with Invalid Scan Format" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="dir"
  export BUILDKITE_PLUGIN_WIZ_PATH="dir/to/scan"
  export BUILDKITE_PLUGIN_WIZ_SCAN_FORMAT="invalid"

  run "$PWD/hooks/post-command"
  
  assert_failure

  assert_output --partial "+++ 🚨 Invalid Scan Format: invalid"
  assert_output --partial "Valid Formats: human json sarif"
}

@test "Directory Scan with Invalid Output Format" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="dir"
  export BUILDKITE_PLUGIN_WIZ_PATH="dir/to/scan"
  export BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT="invalid"

  run "$PWD/hooks/post-command"
  
  assert_failure

  assert_output --partial "+++ 🚨 Invalid File Output Format: invalid"
  assert_output --partial "Valid Formats: human json sarif csv-zip"
}

@test "Directory Scan with unset Wiz Credentials" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="dir"
  export BUILDKITE_PLUGIN_WIZ_PATH="dir/to/scan"
  unset WIZ_CLIENT_ID
  unset WIZ_CLIENT_SECRET

  run "$PWD/hooks/post-command"
  
  assert_failure

  assert_output --partial "+++ 🚨 The following required environment variables are not set: WIZ_CLIENT_ID WIZ_CLIENT_SECRET"
}

@test "Docker Scan with Custom Annotation Command" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="ubuntu:22.04"
  export BUILDKITE_PLUGIN_WIZ_ANNOTATION_COMMAND="echo 'Custom annotation:' && cat"

  stub uname "-m : echo 'unknown'"

  mkdir -p "$WIZ_DIR"
  touch "$WIZ_DIR/key"

  stub docker \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli -e WIZ_CLIENT_ID -e WIZ_CLIENT_SECRET wiziocli.azurecr.io/wizcli:latest auth : exit 0' \
    'pull "ubuntu:22.04" : exit 0' \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli,readonly --mount type=bind,src=/plugin,dst=/scan --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock,readonly wiziocli.azurecr.io/wizcli:latest docker scan --image ubuntu:22.04 --policy-hits-only --format=human --output=/scan/result/output,human : echo "Docker image scanned without policy hits"'

  run "$PWD/hooks/post-command"
  
  assert_success

  assert_output --partial "Authenticated successfully"
  assert_output --partial "Docker image scanned without policy hits"
  assert_output --partial "Custom annotation:"

  unstub uname
  unstub docker
}
