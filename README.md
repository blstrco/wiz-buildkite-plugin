# Wiz Buildkite Plugin

![Wiz logo image](https://github.com/buildkite-plugins/wiz-buildkite-plugin/blob/main/wiz-logo.png)

Scans your infrastructure-as-code Cloudformation stacks or docker images for security vulnerabilities using [wiz](https://www.wiz.io/)

This plugin is forked from [blstrco/wiz-buildkite-plugin](https://github.com/blstrco/wiz-buildkite-plugin).

## Requirements

In order to use this plugin, you will need to have the following installed on your buildkite agent:

- Docker

And the following environment variables exported in the job (e.g. via an Agent hook or Plugin):

- WIZ_CLIENT_ID (Wiz service account's client ID)
- WIZ_CLIENT_SECRET (Wiz service account's secret)

Check out [Buildkite's documentation](https://buildkite.com/docs/pipelines/security/secrets/managing) for more information on how to manage secrets in Buildkite.

## Examples

### Docker Scanning

Add the following to your `pipeline.yml`, the plugin will pull the image, scan it using wiz and create a buildkite annotation with the results.

```yml
steps:
  - command: ls
    plugins:
      - wiz#v2.0.0:
          scan-type: 'docker'
          image-address: "<image-address-to-pull-and-scan>"
```

If you are using the [AWS Assume Role Plugin](https://github.com/cultureamp/aws-assume-role-buildkite-plugin), you might have trouble getting your secret key from `aws secretsmanager` if the role you assumed doesn't have the necessary access rights. To restore your role, you can use the [AWS Restore Role Buildkite Plugin](https://github.com/franklin-ross/aws-restore-role-buildkite-plugin) before the wiz plugin.

```yml
  plugins:
      - franklin-ross/aws-restore-role#HEAD
      - wiz#v2.0.0:
        scan-type: 'docker'
```

### AWS `cdk diff` Scanning

To avoid adding build time overhead, you can add IaC scanning to your `cdk diff` step. You will need to mount/export the `cdk.out` folder and pass its path to the plugin. The plugin will then scan each Cloudformation stack in the folder and create a buildkite annotation with the results.

```yml
steps:
  - command: ls
    plugins:
      - docker-compose#v4.16.0:
        # to get the output of CDK diff, mount the volume in cdk diff stage
        - volumes:
          - './infrastructure/cdk.out:/app/infrastructure/cdk.out'
      - wiz#v2.0.0:
          scan-type: 'iac'
          path: "infrastructure/cdk.out"
```

### CloudFormation templates Scanning

Add the following to your `pipeline.yml`, the plugin will scan a specific CloudFormation template and related Parameter file.

```yaml
steps:
  - label: "Scan CloudFormation template file"
    command: ls
    plugins:
      - wiz#v2.0.0:
          scan-type: 'iac'
          iac-type: 'Cloudformation'
          path: 'cf-template.yaml'
          parameter-files: 'params.json'
```

This can also be used to scan CloudFormation templates that have been synthesized via the AWS CDK e.g., `cdk synth > example.yaml`

### Terraform Files Scanning

Add the following to your `pipeline.yml`, the plugin will scan a specific Terraform File and related Parameter file.

```yaml
steps:
  - label: "Scan Terraform File"
    command: ls *.tf
    plugins:
      - wiz#v2.0.0:
          scan-type: 'iac'
          iac-type: 'Terraform'
          path: 'main.tf'
          parameter-files: 'variables.tf'
```

By default, `path` parameter will be the root of your repository, and scan all Terraform files in the directory.
To change the directory, add the following to your `pipeline.yml`, the plugin will scan the chosen directory.

```yaml
steps:
  - label: "Scan Terraform Files in Directory"
    command: ls my-terraform-dir/*.tf
    plugins:
      - wiz#v2.0.0:
          scan-type: 'iac'
          iac-type: 'Terraform'
          path: 'my-terraform-dir'
```

### Terraform Plan Scanning

Add the following to your `pipeline.yml`, the plugin will scan a Terraform Plan.

```yaml
steps:
  - label: "Scan Terraform Plan"
    command: terraform plan -out plan.tfplan && terraform show -json plan.tfplan | jq -er . > plan.tfplanjson
    plugins:
      - wiz#v2.0.0:
          scan-type: 'iac'
          iac-type: 'Terraform'
          path: 'plan.tfplanjson'
```

### Directory Scanning

Add the following to your `pipeline.yml`, the plugin will scan a directory.

```yaml
steps:
  - label: "Scan Directory"
    command: ls .
    plugins:
      - wiz#v2.0.0:
          scan-type: 'dir'
          path: 'main.tf'
```

By default, `path` parameter will be the root of your repository, and scan all files in the local directory.
To change the directory, add the following to your `pipeline.yml`, the plugin will scan the chosen directory.

```yaml
steps:
  - label: "Scan Files in different Directory"
    command: ls my-dir
    plugins:
      - wiz#v2.0.0:
          scan-type: 'dir'
          path: 'my-dir'
```

### Custom Annotation Command

You can override the default `buildkite-agent annotate` command with your own custom annotation handler. This is useful if you want to send annotations to a different system, format them differently, or use grouped annotations.

```yaml
steps:
  - command: ls
    plugins:
      - wiz#v2.0.0:
          scan-type: 'docker'
          image-address: "myapp:latest"
          annotation-command: "./.buildkite/scripts/grouped-annotation.sh"
```

Your custom annotation script will receive:
- **stdin**: The annotation content (HTML/Markdown formatted)
- **`WIZ_ANNOTATION_CONTEXT`**: The annotation context (e.g., 'ctx-wiz-docker-success', 'ctx-wiz-docker-warning')
- **`WIZ_ANNOTATION_STYLE`**: The annotation style (e.g., 'success', 'warning')

#### Example: Using grouped-annotation.sh

If your custom script supports reading from stdin and environment variables, it will work seamlessly:

```bash
#!/bin/bash
# Your script can read the message from stdin
MESSAGE=$(cat)

# And use the environment variables
STYLE="${WIZ_ANNOTATION_STYLE:-info}"
CONTEXT="${WIZ_ANNOTATION_CONTEXT:-default}"

# Process and create your annotation
echo "$MESSAGE" | buildkite-agent annotate --style "$STYLE" --context "$CONTEXT"
```

#### Example: Simple custom handler

```bash
#!/bin/bash
# Read the annotation content from stdin
ANNOTATION_CONTENT=$(cat)

# Access the context and style from environment variables
echo "Context: ${WIZ_ANNOTATION_CONTEXT}"
echo "Style: ${WIZ_ANNOTATION_STYLE}"
echo "Content: ${ANNOTATION_CONTENT}"

# Send to your own annotation system
buildkite-agent annotate --append \
  --context "${WIZ_ANNOTATION_CONTEXT}" \
  --style "${WIZ_ANNOTATION_STYLE}" \
  <<< "${ANNOTATION_CONTENT}"
```

## Configuration

### `scan-type` (Required, string) : `dir | docker | iac'

The type of resource to be scanned.

### `iac-type` (Optional, string): `Ansible | AzureResourceManager | Cloudformation | Dockerfile | GoogleCloudDeploymentManager | Kubernetes | Terraform`

Narrow down the scan to specific type.
Used when `scan-type` is `iac`.

### `image-address` (Optional, string)

The path to image file, if the `scan-type` is `docker`.

### `scan-format` (Optional, string): `human | json | sarif`

Scans output format.
Defaults to: `human`

### `file-output-format` (Optional, string or array): `human | json | sarif | csv-zip`

Generates an additional output file with the specified format.

### `parameter-files` (Optional, string)

Comma separated list of globs of external parameter files to include while scanning e.g., `variables.tf`
Used when `scan-type` is `iac`.

### `path` (Optional, string)

The file or directory to scan, defaults to the root directory of repository.
Used when `scan-type` is `dir` or `iac`.

### `show-secret-snippets` (Optional, bool)

Enable snippets in secrets.
Defaults to: `false`

### `annotation-command` (Optional, string)

Custom command to use for creating annotations instead of the default `buildkite-agent annotate`.
The annotation content will be passed via stdin, and the following environment variables will be available:
- `WIZ_ANNOTATION_CONTEXT`: The annotation context (e.g., 'ctx-wiz-docker-success')
- `WIZ_ANNOTATION_STYLE`: The annotation style (e.g., 'success', 'warning')

Example:
```yaml
steps:
  - command: ls
    plugins:
      - wiz#v2.0.0:
          scan-type: 'docker'
          image-address: "ubuntu:22.04"
          annotation-command: "my-custom-annotate-script.sh"
```

The custom script will receive the annotation content via stdin and can use the environment variables to determine context and style.

## Developing

To run the tests:

```shell
docker compose run --rm tests
```

## Contributing

1. Fork the repo
2. Make the changes
3. Run the tests
4. Commit and push your changes
5. Send a pull request