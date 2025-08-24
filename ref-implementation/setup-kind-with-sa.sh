#!/bin/bash
set -e

echo "Creating Kind cluster..."
kind create cluster --name localdev --config kind-config-with-sa-args.yaml

echo "Waiting for cluster to be ready..."
kubectl wait --for=condition=ready node --all --timeout=60s

echo "Copying SA keys into the container..."
docker cp /home/vpittamp/stacks/ref-implementation/keys/sa.key localdev-control-plane:/etc/kubernetes/pki/sa-custom.key
docker cp /home/vpittamp/stacks/ref-implementation/keys/sa.pub localdev-control-plane:/etc/kubernetes/pki/sa-custom.pub

echo "Setting correct permissions on SA keys..."
docker exec localdev-control-plane chmod 600 /etc/kubernetes/pki/sa-custom.key
docker exec localdev-control-plane chmod 644 /etc/kubernetes/pki/sa-custom.pub

echo "Restarting kube-apiserver and kube-controller-manager..."
docker exec localdev-control-plane sh -c 'kill $(pgrep kube-apiserver) || true'
docker exec localdev-control-plane sh -c 'kill $(pgrep kube-controller) || true'

echo "Waiting for API server to come back up..."
sleep 10
kubectl wait --for=condition=ready node --all --timeout=60s

echo "Cluster created successfully with custom SA keys!"
kubectl get nodes