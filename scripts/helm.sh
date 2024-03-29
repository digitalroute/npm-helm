#!/usr/bin/env bash

set -u

function get_version() {
  local git_describe
  git_describe=$(git describe --abbrev=9 --tag --match 'v*' 2>/dev/null | sed 's/^v//')

  local suffix
  suffix=$(get_suffix)

  if [[ "${npm_package_config_helm_version}" != "" ]]; then
    echo "${npm_package_config_helm_version}"
  elif [[ ! "${npm_package_version}" =~ "semantically-released" ]]; then
    # If the version field in package.json contains a real version
    # then use that
    echo "${npm_package_version}${suffix}"
  elif [ "${git_describe}" != "" ] ; then
    # If we could describe with a tag, lets use that as version.
    # Examples:
    #   v1.3.0-development.5 - when there is a tag on HEAD
    #   v1.3.0-development.4-1-g76e8032 - tag is one commit behind HEAD
    echo "${git_describe}${suffix}"
  else
    echo "${npm_package_version//-semantically-released/}-g$(git rev-parse --short=9 HEAD)${suffix}"
  fi
}

function get_docker_tag() {
  echo "$(git rev-parse --short=9 HEAD)$(get_suffix)"
}

function get_suffix() {
  if [[ ${npm_package_config_helm_buildId} != "" ]]; then
    echo "-${npm_package_config_helm_buildId}"
  else
    if [[ "${npm_package_config_helm_ci}" != "true" ]]; then
      echo "-local"
    fi
  fi
}

function write_package_info() {
  mkdir -p "${output_dir}"
  cat <<EOF >"${output_dir}"/npm-helm-info.yaml
helm:
  version: ${version}
  name: ${npm_package_config_helm_name}
  file: ${npm_package_config_helm_name}-${version}.tgz
  dockerImage: ${npm_package_config_helm_imageRepository}
  dockerTag: ${docker_tag}
EOF
}

function check_npm_var() {
  local var=$1
  if [ -z "${!var-}" ]; then
    echo "Variable $var is not set, do this using your package.json"
    exit 1
  fi
}

for var in npm_package_name npm_package_version; do
  check_npm_var $var
done

if [ -z "${INIT_CWD-}" ]; then
  echo "Missing INIT_CWD variable needed to find base directory"
  exit 1
fi

if [ -z "${1-}" ]; then
  echo "Need to supply type. Choose from the following..."
  echo "docker-build: Build docker image"
  echo "docker-verify: Check if needed docker image is present on host"
  echo "docker-push: Push the docker image to the registry (needs docker login)"
  echo "package: Create the helm package in the output folder"
  echo "push: Pushes the helm chart to the S3 bucket (needs AWS keys)"
  echo "install: Install the helm chart into kubernetes (needs KUBECONFIG)"
  echo
  echo "Maybe you're looking for the old 'npm run helm'? Please try 'npm run helm-install' instead."
  exit 1
fi

if [ -v npm_package_config_helm_name ]; then
  echo "helm config is inside the config block in package.json"
  echo

  for var in npm_package_config_helm_name npm_package_config_helm_repository npm_package_config_helm_namespace npm_package_config_helm_imageRepository; do
    check_npm_var $var
  done

  npm_package_config_helm_repository=${NPM_HELM_REPOSITORY:-${npm_package_config_helm_repository}}
  npm_package_config_helm_namespace=${NPM_HELM_NAMESPACE:-${npm_package_config_helm_namespace}}
  npm_package_config_helm_imageRepository=${NPM_HELM_IMAGE_REPOSITORY:-${npm_package_config_helm_imageRepository}}

  npm_package_config_helm_binary=${NPM_HELM_BINARY:-${npm_package_config_helm_binary:-helm}}
  npm_package_config_helm_verbose=${NPM_HELM_VERBOSE:-${npm_package_config_helm_verbose:-false}}
  npm_package_config_helm_debug=${NPM_HELM_DEBUG:-${npm_package_config_helm_debug:-false}}
  npm_package_config_helm_context_any=${NPM_HELM_CONTEXT_ANY:-${npm_package_config_helm_context_any:-false}}
  npm_package_config_helm_releasePrefix=${NPM_HELM_RELEASE_PREFIX:-${npm_package_config_helm_releasePrefix:-}}
  npm_package_config_helm_values=${NPM_HELM_VALUES:-${npm_package_config_helm_values:-}}
  npm_package_config_helm_push_docker_tag=${NPM_HELM_PUSH_DOCKER_TAG:-${npm_package_config_helm_push_docker_tag:-false}}
  npm_package_config_helm_ci=${NPM_HELM_CI:-${npm_package_config_helm_ci:-false}}
  npm_package_config_helm_version=${NPM_HELM_VERSION:-${npm_package_config_helm_version:-}}
  npm_package_config_helm_buildId=${NPM_HELM_BUILD_ID:-${npm_package_config_helm_buildId:-}}
else
  echo "helm config is on the root level in package.json (DEPRECATED, please move it to the config block)"
  echo

  for var in npm_package_helm_name npm_package_helm_repository npm_package_helm_namespace npm_package_helm_imageRepository; do
    check_npm_var $var
  done

  npm_package_config_helm_name=${npm_package_helm_name-}

  npm_package_config_helm_repository=${NPM_HELM_REPOSITORY:-${npm_package_helm_repository}}
  npm_package_config_helm_namespace=${NPM_HELM_NAMESPACE:-${npm_package_helm_namespace}}
  npm_package_config_helm_imageRepository=${NPM_HELM_IMAGE_REPOSITORY:-${npm_package_helm_imageRepository}}

  npm_package_config_helm_binary=${NPM_HELM_BINARY:-${npm_package_helm_binary:-helm}}
  npm_package_config_helm_verbose=${NPM_HELM_VERBOSE:-${npm_package_helm_verbose:-false}}
  npm_package_config_helm_debug=${NPM_HELM_DEBUG:-${npm_package_helm_debug:-false}}
  npm_package_config_helm_context_any=${NPM_HELM_CONTEXT_ANY:-${npm_package_helm_context_any:-false}}
  npm_package_config_helm_releasePrefix=${NPM_HELM_RELEASE_PREFIX:-${npm_package_helm_releasePrefix:-}}
  npm_package_config_helm_values=${NPM_HELM_VALUES:-${npm_package_helm_values:-}}
  npm_package_config_helm_push_docker_tag=${NPM_HELM_PUSH_DOCKER_TAG:-${npm_package_helm_push_docker_tag:-false}}
  npm_package_config_helm_ci=${NPM_HELM_CI:-${npm_package_helm_ci:-false}}
  npm_package_config_helm_version=${NPM_HELM_VERSION:-${npm_package_helm_version:-}}
  npm_package_config_helm_buildId=${NPM_HELM_BUILD_ID:-${npm_package_helm_buildId:-}}
fi

base_dir=${INIT_CWD}
output_dir="${base_dir}/output"
helm_dir="${base_dir}/helm/${npm_package_config_helm_name:?}"

if [ "${npm_package_config_helm_debug}" == "true" ]; then
  echo "NPM Helm debug set to true which does set -x in shell"
  set -x
fi

context=$(kubectl config current-context 2>/dev/null || true)

if [ "${npm_package_config_helm_ci}" == "true" ]; then
  npm_package_config_helm_context_any="true"
fi

if [ "${npm_package_config_helm_context_any}" != "true" ]; then
  if [ "${context}" != "minikube" ] && [ "${context}" != "minikube-on-aws" ]; then
    echo "Kubernetes context needs to be set to minikube or minikube-on-aws, it's currently set to ${context}. Refusing to do anything. If you're absolutely sure you know what you're doing, you can override this using NPM_HELM_CONTEXT_ANY=true."
    exit 1
  fi
fi

# The helm --value files that we need to use, in order of importance since helm overrides from left -> right for the command line args
value_files=()

case $context in
  minikube)
    echo "Context set to minikube!"
    if ! minikube status; then
      echo "Minikube seems offline, exiting..."
      exit 1
    fi
    eval "$(minikube docker-env)"
    value_files=('values-minikube.yaml')
    ;;
  minikube-on-aws)
    echo "Context set to minikube-on-aws"
    export DOCKER_HOST="ssh://ubuntu@docker.dazzler.minikube"
    value_files=('values-minikube.yaml' 'values-minikube-on-aws.yaml')
    ;;
  *)
    echo "Context set to $context"
    ;;
esac

version=$(get_version)
docker_tag=$(get_docker_tag)

set -u
set -e

mkdir -p "${output_dir}"

if [ "${npm_package_config_helm_verbose}" == "true" ]; then
  cat <<EOF

------ Configuration for npm-helm ------
npm_package_config_helm_name: ${npm_package_config_helm_name}
npm_package_config_helm_binary: ${npm_package_config_helm_binary}
npm_package_config_helm_verbose: ${npm_package_config_helm_verbose}
npm_package_config_helm_debug: ${npm_package_config_helm_debug}
npm_package_config_helm_context_any: ${npm_package_config_helm_context_any}
npm_package_config_helm_repository: ${npm_package_config_helm_repository}
npm_package_config_helm_namespace: ${npm_package_config_helm_namespace}
output_dir: ${output_dir}
helm_dir: ${helm_dir}
context: ${context}
docker_image: ${npm_package_config_helm_imageRepository}
docker_tag: ${docker_tag}
version: ${version}

EOF
fi

for type in "$@"; do
  echo "Doing $type"
  case $type in
    docker-build)
      echo "Building docker image ${npm_package_config_helm_imageRepository}:${docker_tag}"
      docker_build_arguments=("--tag" "${npm_package_config_helm_imageRepository}:${docker_tag}")
      if [ -n "${GITHUB_TOKEN-}" ]; then
        echo "Found GITHUB_TOKEN - adding to build args"
        docker_build_arguments+=("--build-arg")
        docker_build_arguments+=("GITHUB_TOKEN=${GITHUB_TOKEN}")
      fi
      if [ -n "${CODEARTIFACT_AUTH_TOKEN-}" ]; then
        echo "Found CODEARTIFACT_AUTH_TOKEN - adding to build args"
        docker_build_arguments+=("--build-arg")
        docker_build_arguments+=("CODEARTIFACT_AUTH_TOKEN=${CODEARTIFACT_AUTH_TOKEN}")
      fi
      if [ -n "${NPM_CONFIG_REGISTRY-}" ]; then
        echo "Found NPM_CONFIG_REGISTRY - adding to build args"
        docker_build_arguments+=("--build-arg")
        docker_build_arguments+=("NPM_CONFIG_REGISTRY=${NPM_CONFIG_REGISTRY}")
      fi
      if [ -n "${BITBUCKET_SSH_KEY-}" ]; then
        echo "Found BITBUCKET_SSH_KEY - adding to build args"
        docker_build_arguments+=("--build-arg")
        docker_build_arguments+=("BITBUCKET_SSH_KEY=${BITBUCKET_SSH_KEY}")
      fi
      if [ -n "${PATH_TO_BITBUCKET_SSH_KEY-}" ]; then
        if test -f "${PATH_TO_BITBUCKET_SSH_KEY-}"; then
          echo "Found PATH_TO_BITBUCKET_SSH_KEY=${PATH_TO_BITBUCKET_SSH_KEY} - adding to build args"
          BITBUCKET_SSH_KEY=$(base64 "${PATH_TO_BITBUCKET_SSH_KEY}")
          docker_build_arguments+=("--build-arg")
          docker_build_arguments+=("BITBUCKET_SSH_KEY=${BITBUCKET_SSH_KEY}")
        else
          echo "Error: PATH_TO_BITBUCKET_SSH_KEY=${PATH_TO_BITBUCKET_SSH_KEY} is not a valid file"
          exit 1
        fi
      fi
      if [ -n "${NODE_VERSION-}" ]; then
        echo "Found NODE_VERSION=${NODE_VERSION} - adding to build args"
        docker_build_arguments+=("--build-arg")
        docker_build_arguments+=("NODE_VERSION=${NODE_VERSION}")
      fi
      docker build "${docker_build_arguments[@]}" "${base_dir}"
      ;;

    docker-verify)
      echo "Checking for docker image: ${npm_package_config_helm_imageRepository}:${docker_tag}"
      if ! [[ $(docker images -q "${npm_package_config_helm_imageRepository}":"${docker_tag}") ]]; then
        exit 1
      fi
      ;;

    docker-push)
      if [ "${npm_package_config_helm_push_docker_tag}" == true ]; then
        echo "Pushing priginal docker image tag ${npm_package_config_helm_imageRepository}:${docker_tag}"
        docker push "${npm_package_config_helm_imageRepository}:${docker_tag}"
      else
        echo "Tagging docker image: ${npm_package_config_helm_imageRepository}:${docker_tag} -> ${npm_package_config_helm_imageRepository}:${version}"
        docker tag "${npm_package_config_helm_imageRepository}:${docker_tag}" "${npm_package_config_helm_imageRepository}:${version}"

        echo "Pushing docker image ${npm_package_config_helm_imageRepository}:${version}"
        docker push "${npm_package_config_helm_imageRepository}:${version}"
      fi
      ;;

    ecr-login)
      aws_cli_version=$(aws --version 2>&1 | grep '^aws-cli/' | sed -e 's/^aws-cli\///' -e 's/ Python.*//')
      if [ "${aws_cli_version}" == "" ]; then
        echo "Could not parse aws cli, is it installed? we should support v1 and v2"
        exit 1
      fi

      aws_cli_version_major=$(echo "${aws_cli_version}" | cut -d '.' -f 1)
      aws_cli_version_minor=$(echo "${aws_cli_version}" | cut -d '.' -f 2)
      if [ "${aws_cli_version_major}" -eq 1 ] && [ "${aws_cli_version_minor}" -le 17 ]; then
        echo "Found legacy aws cli, v${aws_cli_version}, doing docker login in the old way"
        eval "aws ecr get-login --no-include-email"
      else
        region=$(echo "${npm_package_config_helm_imageRepository}" | cut -d '.' -f 4)
        server=$(echo "${npm_package_config_helm_imageRepository}" | cut -d '/' -f 1)
        echo "Found newer aws cli, v${aws_cli_version}, doing docker login the new way. Parsed region=${region}, server=${server}"
        docker login --username AWS --password "$(aws ecr get-login-password --region ${region})" "${server}"
      fi
      ;;

    write-package-info)
      echo "Writing package info for version ${version}"
      write_package_info
      ;;

    package)
      debug=""
      if [ "${npm_package_config_helm_verbose}" == "true" ]; then
        debug="--debug"
      fi

      echo "Creating helm chart for version ${version}"
      $npm_package_config_helm_binary $debug package "${helm_dir}"/ --destination "${output_dir}" --version "${version}" --app-version "${version}"
      write_package_info
      ;;

    lint)
      debug=""
      if [ "${npm_package_config_helm_verbose}" == "true" ]; then
        debug="--debug"
      fi

      echo "Running helm lint for version ${version}"
      $npm_package_config_helm_binary $debug lint "${helm_dir}"/
      ;;

    push)
      debug=""
      if [ "${npm_package_config_helm_verbose}" == "true" ]; then
        debug="--debug"
      fi

      echo "Pushing helm chart for version ${version}"
      $npm_package_config_helm_binary $debug s3 push "${output_dir}"/"${npm_package_config_helm_name}"-"${version}".tgz "${npm_package_config_helm_repository}"
      ;;

    install)
      helm_release_name="${npm_package_config_helm_name}"
      if [ "${npm_package_config_helm_releasePrefix}" != "" ]; then
        helm_release_name="${npm_package_config_helm_releasePrefix}-${npm_package_config_helm_name}"
      fi

      helm_args=()
      if [ "${npm_package_config_helm_verbose}" == "true" ]; then
        helm_args+=("--debug")
      fi

      for values_file in "${value_files[@]}"; do
        if test -f "${helm_dir}/${values_file}"; then
          echo "Adding $values_file as --values argument"
          helm_args+=(--values "${helm_dir}/${values_file}")
        fi
      done

      if [ "${npm_package_config_helm_values}" != "" ]; then
        helm_args+=(--values "${npm_package_config_helm_values}")
      fi

      if [ "${npm_package_config_helm_ci}" != "true" ]; then
        helm_args+=("--set" "image.repository=${npm_package_config_helm_imageRepository}" "--set" "image.tag=${docker_tag}")
      fi

      echo "Installing helm chart with release-name=${helm_release_name}, version=${version}, extra arguments:" "${helm_args[@]}"
      $npm_package_config_helm_binary upgrade --install "${helm_release_name}" "${output_dir}"/"${npm_package_config_helm_name}"-"${version}".tgz --namespace "${npm_package_config_helm_namespace}" --atomic "${helm_args[@]}"
      ;;

    cache-node-modules)
      add_to_build_dir="${base_dir}/add-to-build"
      mkdir -p "$add_to_build_dir"

      version_found=$(git describe --tags --abbrev=0 | sed 's/^v//')
      echo "Pulling image: ${npm_package_config_helm_imageRepository}:${version_found}"
      docker pull "${npm_package_config_helm_imageRepository}":"${version_found}"
      docker run --rm "${npm_package_config_helm_imageRepository}":"${version_found}" tar --create --verbose --gzip --file - node_modules/ > "${add_to_build_dir}"/node_modules.tar.gz
      ;;

    *)
      echo "Type=${type} not supported"
      ;;
  esac
done
