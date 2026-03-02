#!/bin/sh
# Download the config from the current cluster to the kubectl config
# area on the current workstation
set -e
mkdir -p "${HOME}/.kube"
scp "ubuntu@$(tofu output -raw bastion):.kube/config" "${HOME}/.kube/config"
sed -i.orig "s/https:.*$/https:\/\/$(tofu output -raw master):6443/" "${HOME}/.kube/config"
rm "${HOME}/.kube/config.orig"
