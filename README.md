# npm-helm
Helm helper module for nodejs

## Usage
Like usual:

```
npm install github:digitalroute/npm-helm#v0.3.0 --save-dev
```

And add the following parts to your package.json

```
  "helm": {
    "name": "stuff",
    "repository": "dazzlerjs",
    "namespace": "dazzlerjs",
    "imageRepository": "1234567890.dkr.ecr.eu-west-1.amazonaws.com/repo/stuff",
    "verbose": "true"
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

