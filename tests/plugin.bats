#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"
load "${BATS_TEST_DIRNAME}/../lib/plugin.bash"
load "${BATS_TEST_DIRNAME}/../lib/shared.bash"

# export DOCKER_STUB_DEBUG=/dev/tty
# export BUILDKITE_AGENT_STUB_DEBUG=/dev/tty

setup() {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export WIZ_DIR="$HOME/.wiz"
  export WIZ_CLIENT_ID="test"
  export WIZ_CLIENT_SECRET="secret"
  export WIZ_CLI_CONTAINER="wiziocli.azurecr.io/wizcli:latest"
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

@test "Validates Wiz Client Credentials" {
  run validate_wiz_client_credentials

  assert_success
}

@test "Invalid Wiz Client Credential (ID)" {
  export WIZ_CLIENT_ID=""

  run validate_wiz_client_credentials

  assert_failure
  assert_output "+++ 🚨 The following required environment variables are not set: WIZ_CLIENT_ID"
}

@test "Invalid Wiz Client Credentials (ID and Secret)" {
  export WIZ_CLIENT_ID=""
  export WIZ_CLIENT_SECRET=""

  run validate_wiz_client_credentials

  assert_failure
  assert_output "+++ 🚨 The following required environment variables are not set: WIZ_CLIENT_ID WIZ_CLIENT_SECRET"
}

@test "Successfully authenticate to Wiz" {
  mkdir -p "$WIZ_DIR"
  touch "$WIZ_DIR/key"

  stub docker \
    'run --rm -it --mount type=bind,src="$WIZ_DIR",dst=/cli,readonly -e WIZ_CLIENT_ID -e WIZ_CLIENT_SECRET "wiziocli.azurecr.io/wizcli:latest" auth: exit 0'

  run get_wiz_auth_file "$WIZ_CLI_CONTAINER" "$WIZ_DIR"

  assert_success

  unstub docker
}

@test "Fail to authenticate to Wiz" {
  stub docker \
    'run --rm -it --mount type=bind,src="$WIZ_DIR",dst=/cli,readonly -e WIZ_CLIENT_ID -e WIZ_CLIENT_SECRET "wiziocli.azurecr.io/wizcli:latest" auth: exit 0'

  run get_wiz_auth_file "$WIZ_CLI_CONTAINER" "$WIZ_DIR"

  assert_failure
  assert_output --partial "Wiz authentication failed, please confirm the credentials are set for WIZ_CLIENT_ID and WIZ_CLIENT_SECRET"

  unstub docker
}

@test "Invalid Scan Format" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_FORMAT="wrong-format"

  run build_wiz_cli_args "$BUILDKITE_PLUGIN_WIZ_SCAN_TYPE"
  
  assert_failure
  assert_output --partial "+++ 🚨 Invalid Scan Format: $BUILDKITE_PLUGIN_WIZ_SCAN_FORMAT"
}

@test "Invalid File Output Format" {
  export BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT="wrong-format"

  run build_wiz_cli_args "$BUILDKITE_PLUGIN_WIZ_SCAN_TYPE"
  
  assert_failure
  assert_output --partial "+++ 🚨 Invalid File Output Format: $BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT"
}

@test "Invalid File Output Format (multiple)" {
  export BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_0="human"
  export BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_1="wrong-format"

  run build_wiz_cli_args "$BUILDKITE_PLUGIN_WIZ_SCAN_TYPE"

  assert_failure
  assert_output --partial "+++ 🚨 Invalid File Output Format: $BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_1"
}

@test "Duplicate File Output Formats" {
  export BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_0="human"
  export BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_1="human"

  run build_wiz_cli_args "$BUILDKITE_PLUGIN_WIZ_SCAN_TYPE"

  assert_success
  assert_output --partial "+++ ⚠️  Duplicate file output format ignored: $BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_1"
}

@test "Invalid File Output Format (multiple with duplicates)" {
  export BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_0="human"
  export BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_1="human"
  export BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_2="wrong-format"
  
  run build_wiz_cli_args "$BUILDKITE_PLUGIN_WIZ_SCAN_TYPE"

  assert_failure
  assert_output --partial "+++ ⚠️  Duplicate file output format ignored: $BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_1"
  assert_output --partial "+++ 🚨 Invalid File Output Format: $BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_2"
}

@test "Valid Wiz CLI Args (default)" {
  run build_wiz_cli_args "$BUILDKITE_PLUGIN_WIZ_SCAN_TYPE"

  assert_success
  assert_output --partial "--format=human --output=/scan/result/output,human"
}

@test "Valid Wiz CLI Args (custom)" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_FORMAT="json"
  export BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_0="human"
  export BUILDKITE_PLUGIN_WIZ_FILE_OUTPUT_FORMAT_1="json"

  run build_wiz_cli_args "$BUILDKITE_PLUGIN_WIZ_SCAN_TYPE"

  assert_success
  assert_output --partial "--format=json --output=/scan/result/output,human --output=/scan/result/output-human,human --output=/scan/result/output-json,json"
}

@test "Get Wiz CLI Container Image (amd64)" {
  stub uname "-m : echo 'x86_64'"

  run detect_wiz_cli_container

  assert_success
  assert_output --partial "wiziocli.azurecr.io/wizcli:latest-amd64"

  unstub uname
}

@test "Get Wiz CLI Container Image (arm64)" {
  stub uname "-m : echo 'arm64'"

  run detect_wiz_cli_container

  assert_success
  assert_output --partial "wiziocli.azurecr.io/wizcli:latest-arm64"

  unstub uname
}

@test "Get Wiz CLI Container Image (unknown architecture)" {
  stub uname "-m : echo 'unknown'"

  run detect_wiz_cli_container

  assert_success
  assert_output --partial "wiziocli.azurecr.io/wizcli:latest"

  unstub uname
}

@test "Build Annotations (no findings)" {
  
  run build_annotation "docker" "ubuntu:latest" true "result/output"

  assert_success

  assert_output --partial "<summary>Wiz Docker Image Scan for ubuntu:latest meets policy requirements.</summary>"
}

@test "Build Annotations (findings)" {

  run build_annotation "docker" "ubuntu:latest" false "result/output"

  assert_success

  assert_output --partial "<summary>Wiz Docker Image Scan for ubuntu:latest does not meet policy requirements.</summary>"
}

@test "Docker Scan (success)" {
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="ubuntu:latest"
  export cli_args=("--format=human" "--output=/scan/result/output,human")

  mkdir -p "$WIZ_DIR"

  mkdir -p "result"
  touch "result/output"

  stub docker \
    'pull "ubuntu:latest" : exit 0' \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli,readonly --mount type=bind,src=/plugin,dst=/scan --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock,readonly wiziocli.azurecr.io/wizcli:latest docker scan --image ubuntu:latest --policy-hits-only --format=human --output=/scan/result/output,human : echo "Docker image scanned without policy hits"'

  stub buildkite-agent \
    'annotate --append --context 'ctx-wiz-docker-success' --style 'success' : echo "Annotated Build"'

  run docker_image_scan "${WIZ_CLI_CONTAINER}" "${WIZ_DIR}" "${BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS}" "${cli_args[@]}"

  assert_success

  assert_output --partial "Docker image scanned without policy hits"
  assert_output --partial "Annotated Build"

  unstub docker
  unstub buildkite-agent
}

@test "Docker Scan (failure)" {
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="ubuntu:latest"
  export cli_args=("--format=human" "--output=/scan/result/output,human")

  mkdir -p "$WIZ_DIR"

  mkdir -p "result"
  touch "result/output"

  stub docker \
    'pull "ubuntu:latest" : exit 0' \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli,readonly --mount type=bind,src=/plugin,dst=/scan --mount type=bind,src=/var/run/docker.sock,dst=/var/run/docker.sock,readonly wiziocli.azurecr.io/wizcli:latest docker scan --image ubuntu:latest --policy-hits-only --format=human --output=/scan/result/output,human : echo "Docker image scanned with policy hits"; exit 1'
  
  stub buildkite-agent \
    'annotate --append --context 'ctx-wiz-docker-warning' --style 'warning' : echo "Annotated Build"'

  run docker_image_scan "${WIZ_CLI_CONTAINER}" "${WIZ_DIR}" "${BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS}" "${cli_args[@]}"

  assert_failure
  
  assert_output --partial "Docker image scanned with policy hits"
  assert_output --partial "Annotated Build"

  unstub docker
  unstub buildkite-agent
}

@test "IaC Scan (success)" {
  export BUILDKITE_JOB_ID="1234-abcd"
  export BUILDKITE_BUILD_ID="1234-abcd"
  export BUILDKITE_LABEL="iac-scan"
  export FILE_PATH="iac/to/scan"
  export cli_args=("--format=human" "--output=/scan/result/output,human")

  mkdir -p "$WIZ_DIR"

  mkdir -p "result"
  touch "result/output"

  stub docker \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli,readonly --mount type=bind,src=/plugin,dst=/scan wiziocli.azurecr.io/wizcli:latest iac scan --name 1234-abcd --path /scan/iac/to/scan --format=human --output=/scan/result/output,human : echo "IaC scanned without policy hits"'

  stub buildkite-agent \
    'annotate --append --context 'ctx-wiz-iac-success' --style 'success' : echo "Annotated Build"' \
    'artifact upload check-file : echo "Uploaded check-file"'

  run iac_scan "${WIZ_CLI_CONTAINER}" "${WIZ_DIR}" "${FILE_PATH}" "${cli_args[@]}"

  assert_success

  assert_output --partial "IaC scanned without policy hits"
  assert_output --partial "Annotated Build"
  assert_output --partial "Uploaded check-file"

  unstub docker
  unstub buildkite-agent
}

@test "IaC Scan (failure)" {
  export BUILDKITE_JOB_ID="1234-abcd"
  export BUILDKITE_BUILD_ID="1234-abcd"
  export BUILDKITE_LABEL="iac-scan"
  export FILE_PATH="iac/to/scan"
  export cli_args=("--format=human" "--output=/scan/result/output,human")

  mkdir -p "$WIZ_DIR"

  mkdir -p "result"
  touch "result/output"

  stub docker \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli,readonly --mount type=bind,src=/plugin,dst=/scan wiziocli.azurecr.io/wizcli:latest iac scan --name 1234-abcd --path /scan/iac/to/scan --format=human --output=/scan/result/output,human : echo "IaC scanned with policy hits"; exit 1'

  stub buildkite-agent \
    'annotate --append --context 'ctx-wiz-iac-warning' --style 'warning' : echo "Annotated Build"' \
    'artifact upload check-file : echo "Uploaded check-file"'

  run iac_scan "${WIZ_CLI_CONTAINER}" "${WIZ_DIR}" "${FILE_PATH}" "${cli_args[@]}"

  assert_failure

  assert_output --partial "IaC scanned with policy hits"
  assert_output --partial "Annotated Build"
  assert_output --partial "Uploaded check-file"

  unstub docker
  unstub buildkite-agent
}

@test "Directory Scan (success)" {
  export BUILDKITE_JOB_ID="1234-abcd"
  export BUILDKITE_BUILD_ID="1234-abcd"
  export BUILDKITE_LABEL="iac-scan"
  export FILE_PATH="dir/to/scan"
  export cli_args=("--format=human" "--output=/scan/result/output,human")

  mkdir -p "$WIZ_DIR"

  mkdir -p "result"
  touch "result/output"

  stub docker \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli,readonly --mount type=bind,src=/plugin,dst=/scan wiziocli.azurecr.io/wizcli:latest dir scan --name 1234-abcd --path /scan/dir/to/scan --format=human --output=/scan/result/output,human : echo "Directory scanned without policy hits"'

  stub buildkite-agent \
    'annotate --append --context 'ctx-wiz-dir-success' --style 'success' : echo "Annotated Build"' \
    'artifact upload check-file : echo "Uploaded check-file"'

  run dir_scan "${WIZ_CLI_CONTAINER}" "${WIZ_DIR}" "${FILE_PATH}" "${cli_args[@]}"

  assert_success

  assert_output --partial "Directory scanned without policy hits"
  assert_output --partial "Annotated Build"
  assert_output --partial "Uploaded check-file"

  unstub docker
  unstub buildkite-agent
}

@test "Directory Scan (failure)" {
  export BUILDKITE_JOB_ID="1234-abcd"
  export BUILDKITE_BUILD_ID="1234-abcd"
  export BUILDKITE_LABEL="iac-scan"
  export FILE_PATH="dir/to/scan"
  export cli_args=("--format=human" "--output=/scan/result/output,human")

  mkdir -p "$WIZ_DIR"

  mkdir -p "result"
  touch "result/output"

  stub docker \
    'run --rm --mount type=bind,src=/root/.wiz,dst=/cli,readonly --mount type=bind,src=/plugin,dst=/scan wiziocli.azurecr.io/wizcli:latest dir scan --name 1234-abcd --path /scan/dir/to/scan --format=human --output=/scan/result/output,human : echo "Directory scanned with policy hits"; exit 1'
  
  stub buildkite-agent \
    'annotate --append --context 'ctx-wiz-dir-warning' --style 'warning' : echo "Annotated Build"' \
    'artifact upload check-file : echo "Uploaded check-file"'
  
  run dir_scan "${WIZ_CLI_CONTAINER}" "${WIZ_DIR}" "${FILE_PATH}" "${cli_args[@]}"
  
  assert_failure
  
  assert_output --partial "Directory scanned with policy hits"
  assert_output --partial "Annotated Build"
  assert_output --partial "Uploaded check-file"
  
  unstub docker
  unstub buildkite-agent
}

@test "Custom Annotation Command" {
  export BUILDKITE_PLUGIN_WIZ_ANNOTATION_COMMAND="echo 'Custom annotation called with context:' \$WIZ_ANNOTATION_CONTEXT 'and style:' \$WIZ_ANNOTATION_STYLE"

  mkdir -p "result"
  echo "Test output" > "result/output"

  run execute_annotation "test-context" "info"

  assert_success
  assert_output --partial "Custom annotation called with context: test-context and style: info"
}

@test "Default Annotation Command when no custom command provided" {
  unset BUILDKITE_PLUGIN_WIZ_ANNOTATION_COMMAND

  mkdir -p "result"
  echo "Test output" > "result/output"

  stub buildkite-agent \
    'annotate --append --context test-context --style info : echo "Default annotation called"'

  echo "Test annotation" | run execute_annotation "test-context" "info"

  assert_success
  assert_output --partial "Default annotation called"

  unstub buildkite-agent
}

