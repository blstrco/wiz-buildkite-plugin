# Wiz Buildkite Plugin

Scans your infrastructure-as-code files or docker images for security vulnerabilities using wiz.io.

## Example

Add the following to your `pipeline.yml`, the build step must export artifacts to `cdk/*.template.json` that can either be CloudFormation files or be automatically generated via `cdk synth`:

```yml
steps:
  - command: ls
    plugins:
      - blstrco/wiz#v1.0.0:
          scan-type: 'iac'
```

## Configuration

### `image` (Optional, string)

The path to image file, if `scan-type` is `image`

## Developing

To run the tests:

```shell
docker-compose run --rm tests
```

## Contributing

1. Fork the repo
2. Make the changes
3. Run the tests
4. Commit and push your changes
5. Send a pull request