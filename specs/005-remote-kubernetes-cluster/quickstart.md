# Quickstart: Remote Kubernetes Cluster Access via Tailscale

**Feature**: 005-remote-kubernetes-cluster
**Status**: In Progress

## Quick Start Guide

This quickstart will guide you through setting up remote access to your Kubernetes cluster via Tailscale.

## Prerequisites

- Tailscale account and network (tailnet)
- kubectl installed locally
- Access to the Kubernetes cluster host

## Setup Steps

Documentation will be populated as implementation progresses.

## User Story Validations

### User Story 1: Remote kubectl Access
- Test: `kubectl --kubeconfig=remote-kubeconfig.yaml get nodes`
- Expected: List of cluster nodes, response time <2 seconds

### User Story 2: Port Forwarding
- Test: `kubectl port-forward -n argocd svc/argocd-server 8080:443`
- Expected: Access ArgoCD at http://localhost:8080, latency <500ms

### User Story 3: Web UI Access
- Test: Navigate to https://argocd.cnoe.localtest.me:8443
- Expected: ArgoCD login page loads within 3 seconds

## Performance Benchmarks

Results will be recorded during implementation testing.
