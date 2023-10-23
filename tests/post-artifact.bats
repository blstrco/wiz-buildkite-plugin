#!/usr/bin/env bats

load "$BATS_PLUGIN_PATH/load.bash"

# Uncomment the following line to debug stub failures
export BUILDKITE_AGENT_STUB_DEBUG=/dev/tty

@test "Authenticates to wiz" {
  export BUILDKITE_PLUGIN_SCAN_TYPE="iac"
  export WIZ_DIR="$HOME/.wiz"

  stub aws 'echo test-key'
  stub docker 'echo TODO'

  run "$PWD/hooks/post-artifact"

  assert_success
  assert_output --partial "Authenticated successfully."
}
