#!/usr/bin/env bash

set -u

function get_version() {
  if [ -n "${VERSION-}" ]; then
    echo ${VERSION}
  elif [ -n "${BUILD_ID-}" ]; then
    echo "${npm_package_version}-${BUILD_ID}.$(git log -n 1 --pretty=format:'%h')"
  elif [ "${ENV}" == "minikube" ]; then
    echo "${npm_package_version}-minikube"
  else
    echo "${npm_package_version}-$(git log -n 1 --pretty=format:'%h')"
  fi
}

if [ -z "${npm_package_name-}" ] || [ -z "${npm_package_version-}" ] || [ -z "${npm_package_helm_imageRepository-}" ] || [ -z "${npm_package_helm_name-}" ] ; then
  echo "Missing NPM environment variables"
  echo "You need to run this script through npm"
  exit 1
fi

if [[ $1 == "" ]]; then
  echo "Need to supply type (docker-build, docker-push, package, push, install)"
  exit 1
fi

base_dir=$(git rev-parse --show-toplevel)
output_dir="${base_dir}/output"
helm_dir="${base_dir}/helm/${npm_package_helm_name}"

context=$(kubectl config current-context 2>/dev/null || true)

case $context in
  minikube)
    eval $(minikube docker-env)
    ENV="minikube"
    echo "Running in minikube!"
    ;;
  *)
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

echo "Using version=${version}, ENV=${ENV}, values=${values}"

set -u
set -e

for type in "$@"; do
  echo "Doing $type"
  case $type in
    docker-build)
      echo "Building docker image ${npm_package_helm_imageRepository}:${version}"
      build_arg=""
      if [ -n "${npm_package_helm_tokenScope-}" ]; then
        registry="$(npm config get ${npm_package_helm_tokenScope}:registry)"
        if [ "${registry}" != "undefined" ]; then
          r=$(echo $registry | sed -e 's/^https://' -e 's/^http://')
          token=$(grep "^${r}:_authToken" ~/.npmrc | cut -d '=' -f 2)
          build_arg="--build-arg NPM_TOKEN=${token}"
        fi
      fi
      if [ -n "${NPM_TOKEN-}" ]; then
        build_arg="--build-arg NPM_TOKEN=${NPM_TOKEN}"
      fi
      docker build ${build_arg} --tag ${npm_package_helm_imageRepository}:${version} ${base_dir}
      mkdir -p ${output_dir}
      echo "${npm_package_helm_imageRepository}:${version}" > ${output_dir}/docker-image.txt
      ;;

    docker-push)
      echo "Pushing docker image ${npm_package_helm_imageRepository}:${version}"
      docker push ${npm_package_helm_imageRepository}:${version}
      ;;

    package)
      echo "Creating helm chart for version ${version}"
      helm lint ${helm_dir}/
      mkdir -p ${output_dir}
      helm package ${helm_dir}/ --destination ${output_dir} --version ${version}
      ;;

    push)
      echo "Pushing helm chart for version ${version}"
      helm s3 push ${output_dir}/${npm_package_helm_name}-${version}.tgz dazzlerjs
      ;;

    install)
      echo "Installing helm chart with version ${version}"
      helm upgrade --install ${npm_package_helm_name} ${output_dir}/${npm_package_helm_name}-${version}.tgz --namespace dazzlerjs --recreate-pods --force --wait ${values} --set image.repository=${npm_package_helm_imageRepository} --set image.tag=${version}
      ;;

    *)
      echo "Type=${type} not supported"
      ;;
  esac
done
