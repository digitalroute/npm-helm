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
    "name": "stuff",
    "repository": "dazzlerjs",
    "namespace": "dazzlerjs",
    // the old imageRepository is also supported but imageRepositories will take precedence
    "imageRepositories": [
      // support for multiple repositories, will push to all of them
      "1234567890.dkr.ecr.eu-west-1.amazonaws.com/repo/stuff"
    ],
  },
  "scripts": {
    "helm": "npm-helm docker-build package install",
    "helm:docker-build": "npm-helm docker-build",
    "helm:docker-push": "npm-helm docker-push",
    "helm:package": "npm-helm package",
    "helm:install": "npm-helm install",
    "helm:push": "npm-helm push"
  },
```
