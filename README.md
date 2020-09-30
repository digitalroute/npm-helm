# npm-helm

Helm helper module for nodejs

## Usage

Like usual:

```bash
npm install @digitalroute/npm-helm --save-dev
```

And add the following parts to your package.json

```jsonc
  "helm": {
    "name": "<name-of-service>",
    "repository": "<helm-repo-name>",
    "namespace": "<kubernetes-namespace>",
    "imageRepository": "<docker-registry-for-image>",
    "binary": "<helm-binary-to-use>"
  },

  "scripts": {
    "helm": "npm-helm",
    "helm-install": "npm-helm docker-build package install",
  },
```

## Configuration

You can put sensible defaults in your `package.json` file and then override where apropriate with environment variables, like in CI/CD pipelines or for local development. The `package.json` means inside the helm configuration.

| Environment variable      | package.json    | Default   | Description                                                                       |
| ------------------------- | --------------- | --------- | --------------------------------------------------------------------------------- |
| NPM_HELM_NAME             | name            | undefined | Name of service (mandatory)                                                       |
| NPM_HELM_REPOSITORY       | repository      | undefined | Helm repository (mandatory)                                                       |
| NPM_HELM_NAMESPACE        | namespace       | undefined | Kubernetes namespace (mandatory)                                                  |
| NPM_HELM_BINARY           | binary          | helm      | Which helm binary to use, typically helm or helm3                                 |
| NPM_HELM_VERBOSE          | verbose         | false     | Use verbose flags where possible when running helm or other things                |
| NPM_HELM_DEBUG            | debug           | false     | Turn on `set -x` for bash to get some shell debug                                 |
| NPM_HELM_CONTEXT_ANY      | contextAny      | false     | If set to true npm-helm will ignore kubernetes context                            |
| NPM_HELM_RELEASE_PREFIX   | releasePrefix   | undefined | Set a prefix for the installed helm chart, like prefix-name                       |
| NPM_HELM_VALUES           | values          | undefined | Add a values file to helm install/upgrade                                         |
| NPM_HELM_CI               | ci              | false     | If set to true it will treat things like it is doing a proper release             |
| NPM_HELM_VERSION          | version         | false     | Override the version inside `package.json` if needed                              |
| NPM_HELM_IMAGE_REPOSITORY | imageRepository | undefined | Override the docker image repository                                              |
