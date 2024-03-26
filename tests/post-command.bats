#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

# Uncomment the following line to debug stub failures
export BUILDKITE_AGENT_STUB_DEBUG=/dev/tty

@test "Authenticates to wiz using \$WIZ_API_SECRET" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="ubuntu:22.04"
  export WIZ_DIR="$HOME/.wiz"
  export WIZ_API_ID="test"
  export WIZ_API_SECRET="secret"

  stub docker 'echo TODO'
  mkdir -p "$WIZ_DIR"
  touch "$WIZ_DIR/key"

  run "$PWD/hooks/post-command"

  assert_output --partial "Authenticated successfully"
  #todo test docker scan
  assert_success
  #cleanup
  rm "$WIZ_DIR/key"
}

@test "Authenticates to wiz using \$BUILDKITE_PLUGIN_WIZ_API_SECRET_ENV" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="ubuntu:22.04"
  export WIZ_DIR="$HOME/.wiz"
  export WIZ_API_ID="test"
  export BUILDKITE_PLUGIN_WIZ_API_SECRET_ENV="CUSTOM_WIZ_API_SECRET_ENV"
  export CUSTOM_WIZ_API_SECRET_ENV="secret"

  stub docker 'echo TODO'
  mkdir -p "$WIZ_DIR"
  touch "$WIZ_DIR/key"

  run "$PWD/hooks/post-command"

  assert_output --partial "Authenticated successfully"
  #todo test docker scan
  assert_success
  #cleanup
  rm "$WIZ_DIR/key"
}

@test "No Wiz API Secret password found in \$WIZ_API_SECRET" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="ubuntu:22.04"
  export WIZ_API_ID="test"
  export WIZ_API_SECRET=""

  run "$PWD/hooks/post-command"

  assert_output --partial "No Wiz API Secret password found in $WIZ_API_SECRET"
  assert_failure
}

@test "No Wiz API Secret password found in \$CUSTOM_WIZ_API_SECRET_ENV" {
  export BUILDKITE_PLUGIN_WIZ_SCAN_TYPE="docker"
  export BUILDKITE_PLUGIN_WIZ_IMAGE_ADDRESS="ubuntu:22.04"
  export WIZ_API_ID="test"
  export BUILDKITE_PLUGIN_WIZ_API_SECRET_ENV="CUSTOM_WIZ_API_SECRET_ENV"
  export CUSTOM_WIZ_API_SECRET_ENV=""

  run "$PWD/hooks/post-command"

  assert_output --partial "No Wiz API Secret password found in $CUSTOM_WIZ_API_SECRET_ENV"
  assert_failure
}