#!/bin/bash
set -e

echo "Creating Kind cluster for NixOS..."

# Create the cluster without custom SA keys first
kind create cluster --name localdev --config ref-implementation/kind-config-nixos.yaml

echo "Cluster created successfully!"
echo "Waiting for cluster to be ready..."
sleep 10

# Verify cluster is running
kubectl cluster-info --context kind-localdev

echo ""
echo "Cluster is ready. Now you can deploy idpbuilder packages:"
echo "  cd cdk8s"
echo "  idpbuilder create -p ../ref-implementation/ -p dist/"
echo ""
echo "Note: The cluster won't have custom service account issuer configuration."
echo "This may affect workload identity features but should work for basic deployments."