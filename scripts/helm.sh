#!/usr/bin/env bash

set -u

function get_version() {
  if [ -n "${VERSION-}" ]; then
    echo ${VERSION}
  elif [ -n "${BUILD_ID-}" ]; then
    echo "${npm_package_version}-${BUILD_ID}.$(git log -n 1 --pretty=format:'%h')"
  elif [ "${ENV}" == "minikube" ]; then
    echo "${npm_package_version}-minikube"
  elif [ "${ENV}" == "docker-for-desktop" ]; then
    echo "${npm_package_version}-docker"
  else
    echo "${npm_package_version}-$(git log -n 1 --pretty=format:'%h')"
  fi
}

function check_npm_var() {
  local var=$1
  if [ -z "${!var-}" ]; then
    echo "Variable $var is not set, do this using your package.json"
    exit 1
  fi
}

for var in npm_package_name npm_package_version npm_package_helm_imageRepository npm_package_helm_name npm_package_helm_repository npm_package_helm_namespace; do
  check_npm_var $var
done

if [ -z "${INIT_CWD-}" ]; then
  echo "Missing INIT_CWD variable needed to find base directory"
  exit 1
fi

if [[ $1 == "" ]]; then
  echo "Need to supply type (docker-build, docker-push, package, push, install)"
  exit 1
fi

base_dir=${INIT_CWD}
output_dir="${base_dir}/output"
helm_dir="${base_dir}/helm/${npm_package_helm_name}"

HELM_VERBOSE=""
if [ ! -z "${npm_package_helm_verbose-}" ] && [ "${npm_package_helm_verbose}" == "true" ]; then
  echo "Helm verbose mode set to true"
  HELM_VERBOSE="--debug"
fi

# HELM_EXTRA_SET can be used to inject --set to helm upgrade
helm_extra_set=${HELM_EXTRA_SET:-}

# HELM_REPOSITORY overrides repository from package.json
npm_package_helm_repository=${HELM_REPOSITORY:-${npm_package_helm_repository}}

# HELM_NAMESPACE overrides repository from package.json
npm_package_helm_namespace=${HELM_NAMESPACE:-${npm_package_helm_namespace}}

context=$(kubectl config current-context 2>/dev/null || true)
context_any=${HELM_CONTEXT_ANY:-false}
if [ "${context_any}" != "true" ]; then
  if [ "${context}" != "minikube" ] && [ "${context}" != "docker-for-desktop" ]; then
    echo "Kubernetes context needs to be set to minikube or docker-for-desktop, it's currently set to ${context}. Refusing to do anything. If you're absolutely sure you know what you're doing, you can override this using HELM_CONTEXT_ANY=true."
    exit 1
  fi
fi

case $context in
  minikube)
    echo "Context set to minikube!"
    minikube status
    if [ $? != 0 ]; then
      echo "Minikube seems offline, exiting..."
      exit 1
    fi
    eval $(minikube docker-env)
    ENV="minikube"
    ;;
  docker-for-desktop)
    echo "Context set to docker-for-desktop!"
    ENV="docker-for-desktop"
    ;;
  *)
    echo "Context set to $context"
    if [ -z "${ENV-}" ]; then
      ENV="dev"
    fi
    ;;
esac

version=$(get_version)

values=""
if test -f ${helm_dir}/values-${ENV}.yaml; then
  values="--values ${helm_dir}/values-${ENV}.yaml"
fi

echo "Using version=${version}, ENV=${ENV}, values=${values}, helm_extra_set=${helm_extra_set}"

set -u
set -e

mkdir -p ${output_dir}

cat <<EOF >${output_dir}/npm-helm-info.yaml
helm:
  version: ${version}
  name: ${npm_package_helm_name}
  file: ${npm_package_helm_name}-${version}.tgz
  dockerImage: ${npm_package_helm_imageRepository}:${version}
EOF

for type in "$@"; do
  echo "Doing $type"
  case $type in
    docker-build)
      echo "Building docker image ${npm_package_helm_imageRepository}:${version}"
      build_arg=""
      if [ -n "${GITHUB_TOKEN-}" ]; then
        build_arg="--build-arg GITHUB_TOKEN=${GITHUB_TOKEN}"
      fi
      docker build ${build_arg} --tag ${npm_package_helm_imageRepository}:${version} ${base_dir}
      echo "${npm_package_helm_imageRepository}:${version}" > ${output_dir}/docker-image.txt
      ;;

    docker-push)
      echo "Pushing docker image ${npm_package_helm_imageRepository}:${version}"
      docker push ${npm_package_helm_imageRepository}:${version}
      ;;

    package)
      echo "Creating helm chart for version ${version}"
      helm lint ${helm_dir}/
      helm package ${helm_dir}/ --destination ${output_dir} --version ${version} ${HELM_VERBOSE}
      ;;

    push)
      echo "Pushing helm chart for version ${version}"
      helm s3 push ${output_dir}/${npm_package_helm_name}-${version}.tgz ${npm_package_helm_repository}
      ;;

    install)
      helm_release_prefix=${HELM_RELEASE_PREFIX:-}
      if [ "${helm_release_prefix}" != "" ]; then
        helm_release_name="${helm_release_prefix}-${npm_package_helm_name}"
      else
        helm_release_name="${npm_package_helm_name}"
      fi

      echo "Installing helm chart with release-name=${helm_release_name}, version=${version}"
      helm upgrade --install ${helm_release_name} ${output_dir}/${npm_package_helm_name}-${version}.tgz --namespace ${npm_package_helm_namespace} --recreate-pods --force --wait ${values} --set image.repository=${npm_package_helm_imageRepository} --set image.tag=${version} ${HELM_VERBOSE} ${helm_extra_set}
      ;;

    *)
      echo "Type=${type} not supported"
      ;;
  esac
done
