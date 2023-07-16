#!/usr/bin/env bash

print_usage() {
  echo "Usage: $0 -a APP_NAME [-n NAMESPACE] -k KEY -v VALUE -e ENV -c CLUSTER [-s SECRET_NAME]"
  echo "Example: $0 -a dex -k client-id -v 555555555 -e ops -c ops"
  echo
  echo "   -a   Application name"
  echo "   -n   Namespace (default is APP_NAME)"
  echo "   -k   Key"
  echo "   -v   Value"
  echo "   -e   Environment (folder)"
  echo "   -c   Cluster"
  echo "   -s   Secret name (default is APP_NAME-secrets)"
  echo "   -h   Print this help message"
  exit 1
}

if [ $# -eq 0 ]; then
    print_usage
fi

while getopts ":a:n:k:v:e:c:s:h" opt; do
  case ${opt} in
    a) 
      APP_NAME="${OPTARG}"
      NAMESPACE="${NAMESPACE:-$APP_NAME}"  # Default NAMESPACE to APP_NAME if not already set
      SECRET_NAME="${SECRET_NAME:-$APP_NAME-secrets}"  # Default SECRET_NAME to APP_NAME-secrets if not provided
      ;;
    n) NAMESPACE="${OPTARG}" ;;
    k) KEY="${OPTARG}" ;;
    v) VALUE="${OPTARG}" ;;
    e) ENV="${OPTARG}" ;;
    c) CLUSTER="${OPTARG}" ;;
    s) SECRET_NAME="${OPTARG}" ;;  # get secret name from command line
    h) print_usage ;;
    \?) echo "Invalid option -$OPTARG" >&2; print_usage ;;
    :) echo "Option -$OPTARG requires an argument" >&2; print_usage ;;
  esac
done

create_and_seal_secret() {
  echo -n "${VALUE}" | kubectl create secret generic \
    "${SECRET_NAME}" \
    --namespace "${NAMESPACE}" \
    --dry-run=client \
    --from-file="${KEY}"=/dev/stdin \
    -o yaml | kubeseal \
    --cert="${CERT_PATH}" \
    --format=yaml "$@"
}
hr() {
  printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' =
}

set -euxo pipefail
trap - SIGINT

required_vars=("APP_NAME" "NAMESPACE" "KEY" "VALUE" "ENV" "CLUSTER")

for var_name in "${required_vars[@]}"; do
    if [ -z "${!var_name}" ]; then
        echo "Missing value for ${var_name}"
        print_usage
    fi
done

hr
echo "Secrets automation!"
echo "Running as: $(id -u):$(id -g)"
hr

CERT_PATH="secrets/clusters/${CLUSTER}/pub.crt"
APP_PATH="apps/${APP_NAME}/overlays/${ENV}"
SECRET_FILE="${APP_PATH}/secrets.yaml"

echo "Input provided:
APP_NAME: ${APP_NAME}
NAMESPACE: ${NAMESPACE}
KEY: ${KEY}
VALUE: ${VALUE}
ENV: ${ENV}"
hr

if [ ! -f "${CERT_PATH}" ]; then
  echo "Cluster cert ${CERT_PATH} not found"
  exit 1
fi

if [ -f "${SECRET_FILE}" ]; then
  create_and_seal_secret --merge-into "${SECRET_FILE}"
else
  create_and_seal_secret > "${SECRET_FILE}"
fi

echo "Generated secret: ${SECRET_FILE}"
hr
git status -s "${APP_PATH}"
