#!/bin/bash

set -u

function get_version() {
  if [ -n "${VERSION-}" ]; then
    echo "${VERSION}"
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

for var in npm_package_name npm_package_version npm_package_helm_name npm_package_helm_repository npm_package_helm_namespace; do
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

npm_package_helm_binary=${HELM_BINARY:-${npm_package_helm_binary:-helm}}

npm_package_helm_verbose=${HELM_VERBOSE:-${npm_package_helm_verbose:-false}}

if [ -n "${npm_package_helm_internalDebug-}" ] && [ "${npm_package_helm_internalDebug}" == "true" ]; then
  echo "NPM Helm debug set to true which does set -x in shell"
  set -x
fi

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
    eval "$(minikube docker-env)"
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

docker_image=""
declare -a alternative_docker_images

if [ -n "${npm_package_helm_imageRepositories_0+x}" ]; then
  docker_image="${npm_package_helm_imageRepositories_0}:${version}"
  # Loop and try to find elements from helm.imageRepositories.[] in packages.json
  for i in 1 2 3 4 5; do
    var="npm_package_helm_imageRepositories_${i}"
    if [ -z ${!var+x} ]; then
      # No more variables found, from the packages.json array
      break
    fi
    alternative_docker_images+=("${!var}:${version}")
  done

elif [ -n "${npm_package_helm_imageRepository+x}" ]; then
  docker_image="${npm_package_helm_imageRepository}:${version}"

else
  echo "Missing helm docker image repository in package.json"
  exit 1
fi

set -u
set -e

mkdir -p "${output_dir}"

alternativeDockerImages=""
if [ -n "${alternative_docker_images+x}" ] && [ ${#alternative_docker_images[@]} -gt 0 ]; then
  for i in "${alternative_docker_images[@]}"; do alternativeDockerImages+="$i,"; done
fi

cat <<EOF >"${output_dir}"/npm-helm-info.yaml
helm:
  version: ${version}
  name: ${npm_package_helm_name}
  file: ${npm_package_helm_name}-${version}.tgz
  dockerImage: ${docker_image}
  alternativeDockerImages: ${alternativeDockerImages}
EOF

if [ "${npm_package_helm_verbose}" == "true" ]; then
  cat <<EOF

------ Configuration for npm-helm ------
npm_package_helm_binary: ${npm_package_helm_binary}
npm_package_helm_verbose: ${npm_package_helm_verbose}
npm_package_helm_repository: ${npm_package_helm_repository}
npm_package_helm_namespace: ${npm_package_helm_namespace}
output_dir: ${output_dir}
helm_dir: ${helm_dir}
context: ${context}
ENV: ${ENV}
docker_image: ${docker_image}
alternativeDockerImages: ${alternativeDockerImages}
version: ${version}

EOF
fi

for type in "$@"; do
  echo "Doing $type"
  case $type in
    docker-build)
      echo "Building docker image ${docker_image}"
      docker_build_arguments=("--tag" "${docker_image}")
      if [ -n "${GITHUB_TOKEN-}" ]; then
        echo "Found GITHUB_TOKEN"
        docker_build_arguments+=("--build-arg")
        docker_build_arguments+=("GITHUB_TOKEN=${GITHUB_TOKEN}")
      fi
      if [ -n "${BITBUCKET_SSH_KEY-}" ]; then
        echo "Found BITBUCKET_SSH_KEY"
        docker_build_arguments+=("--build-arg")
        docker_build_arguments+=("BITBUCKET_SSH_KEY=${BITBUCKET_SSH_KEY}")
      fi
      if [ -n "${PATH_TO_BITBUCKET_SSH_KEY-}" ]; then
        if test -f "${PATH_TO_BITBUCKET_SSH_KEY-}"; then
          echo "Found PATH_TO_BITBUCKET_SSH_KEY=${PATH_TO_BITBUCKET_SSH_KEY}"
          BITBUCKET_SSH_KEY=$(base64 "${PATH_TO_BITBUCKET_SSH_KEY}")
          docker_build_arguments+=("--build-arg")
          docker_build_arguments+=("BITBUCKET_SSH_KEY=${BITBUCKET_SSH_KEY}")
        else
          echo "Error: PATH_TO_BITBUCKET_SSH_KEY=${PATH_TO_BITBUCKET_SSH_KEY} is not a valid file"
          exit 1
        fi
      fi
      docker build "${docker_build_arguments[@]}" "${base_dir}"
      echo "${docker_image}:${version}" > "${output_dir}/docker-image.txt"

      # Create additional docker image tags if defined
      if [ -n "${alternative_docker_images+x}" ] && [ ${#alternative_docker_images[@]} -gt 0 ]; then
        for i in "${alternative_docker_images[@]}"; do
          docker tag "${docker_image}" "$i"
        done
      fi
      ;;

    docker-push)
      echo "Pushing docker image ${docker_image}"
      docker push "${docker_image}"

      # Push additional docker image tags if defined
      if [ -n "${alternative_docker_images+x}" ] && [ ${#alternative_docker_images[@]} -gt 0 ]; then
        for i in "${alternative_docker_images[@]}"; do
          docker push "$i"
        done
      fi
      ;;

    package)
      debug=""
      if [ "${npm_package_helm_verbose}" == "true" ]; then
        debug="--debug"
      fi

      echo "Creating helm chart for version ${version}"
      $npm_package_helm_binary $debug lint "${helm_dir}"/
      $npm_package_helm_binary $debug package "${helm_dir}"/ --destination "${output_dir}" --version "${version}"
      ;;

    push)
      debug=""
      if [ "${npm_package_helm_verbose}" == "true" ]; then
        debug="--debug"
      fi

      echo "Pushing helm chart for version ${version}"
      $npm_package_helm_binary $debug s3 push "${output_dir}"/"${npm_package_helm_name}"-"${version}".tgz "${npm_package_helm_repository}"
      ;;

    install)
      helm_release_prefix=${HELM_RELEASE_PREFIX:-}
      if [ "${helm_release_prefix}" != "" ]; then
        helm_release_name="${helm_release_prefix}-${npm_package_helm_name}"
      else
        helm_release_name="${npm_package_helm_name}"
      fi

      helm_args=()
      if [ "${npm_package_helm_verbose}" == "true" ]; then
        helm_args+=("--debug")
      fi

      if test -f "${helm_dir}"/values-${ENV}.yaml; then
        helm_args+=(--values "${helm_dir}/values-${ENV}.yaml")
      fi

      helm_args+=("--set" "image.repository=${npm_package_helm_imageRepository}" "--set" "image.tag=${version}")

      echo "Installing helm chart with release-name=${helm_release_name}, version=${version}, extra arguments:" "${helm_args[@]}"
      $npm_package_helm_binary upgrade --install "${helm_release_name}" "${output_dir}"/"${npm_package_helm_name}"-"${version}".tgz --namespace "${npm_package_helm_namespace}" --atomic "${helm_args[@]}"
      ;;

    *)
      echo "Type=${type} not supported"
      ;;
  esac
done
