#! /bin/bash

set -eu

vcluster_app_names=$(kubectl get application -A -l cnoe.io/applicationName=vcluster-package,cnoe.io/stackName=vcluster-multi-env --no-headers -o custom-columns=":metadata.name")
environments=$(echo "$vcluster_app_names" | cut -f 1 -d '-')

for env in $environments; do
    cluster_name=$env

    echo "Checking readiness for ${cluster_name} vcluster..."

    until kubectl get secret -n ${cluster_name}-vcluster vc-${cluster_name}-vcluster-helm &> /dev/null; do
      echo "Waiting for ${cluster_name} vcluster secret to be ready..."
      sleep 10
    done

    echo "${cluster_name} vcluster is ready. Retrieving credentials..."
    client_key=$(kubectl get secret -n ${cluster_name}-vcluster vc-${cluster_name}-vcluster-helm --template='{{index .data "client-key" }}')
    client_certificate=$(kubectl get secret -n ${cluster_name}-vcluster vc-${cluster_name}-vcluster-helm --template='{{index .data "client-certificate" }}')
    certificate_authority=$(kubectl get secret -n ${cluster_name}-vcluster vc-${cluster_name}-vcluster-helm --template='{{index .data "certificate-authority" }}')

    kubectl apply -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${cluster_name}-vcluster-secret
  namespace: argocd
  labels:
    argocd.argoproj.io/secret-type: cluster
    vcluster.cnoe.io/clusterClass: "app-runtime"
    vcluster.cnoe.io/clusterName: "${cluster_name}"
type: Opaque
stringData:
  name: ${cluster_name}-vcluster
  server: https://${cluster_name}-vcluster.cnoe.localtest.me:443
  config: |
    {
      "tlsClientConfig": {
        "insecure": false,
        "caData": "${certificate_authority}",
        "certData": "${client_certificate}",
        "keyData": "${client_key}"
      }
    }
EOF

done
