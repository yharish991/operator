#!/bin/bash
set -eou pipefail

namespace=${1:-operators}
delete=${2-install}
ns=${3-no}

if [ "$delete" != delete ]; then
  echo "Installing Halkyon in namespace ${namespace}"
  if [ "$ns" == yes ]; then
    echo "Creating namespace"
    kubectl create ns "${namespace}"
  fi
  kubectl apply -f deploy/cluster-wide
  kubectl apply -n "${namespace}" -f deploy/namespaced
else
  echo "Deleting Halkyon from namespace ${namespace}"
  kubectl apply -f deploy/cluster-wide
  kubectl apply -n "${namespace}" -f deploy/namespaced
  if [ "$ns" == yes ]; then
    echo "Deleting namespace"
    kubectl delete ns "${namespace}"
  fi
fi
