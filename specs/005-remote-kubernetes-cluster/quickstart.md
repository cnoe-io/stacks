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

**Test Date**: 2025-10-13 20:29 EDT
**Test Platform**: MacBook Pro via Tailscale SSH (Mac bash 3.2)
**Cluster**: kind-localdev on Hetzner NixOS host

### User Story 1: kubectl Access

**Setup**:
- Tailscale operator hostname: `kind-operator-13.tail286401.ts.net`
- Tailscale IP: `100.104.62.112`
- Kubeconfig: Generated via `generate-kubeconfig.sh`

**First Connection (T021)**:
```bash
kubectl --kubeconfig=/Users/vinodpittampalli/remote-kubeconfig.yaml get nodes --request-timeout=60s
```
- **Result**: ✅ SUCCESS
- **Response**: Retrieved node list successfully
- **Certificate**: Tailscale HTTPS (Let's Encrypt) - initial cert validation warning expected
- **Output**: `localdev-control-plane   Ready    control-plane   2d7h    v1.33.1`

**Subsequent Command Speed (T022)**:
```bash
time kubectl --kubeconfig=/Users/vinodpittampalli/remote-kubeconfig.yaml get pods -A
```
- **Result**: ✅ SUCCESS - Well under 2 second target
- **Real time**: `0.469s` (469ms)
- **User time**: `0.108s`
- **Sys time**: `0.030s`
- **Pods listed**: 80+ pods across all namespaces
- **Certificate**: No errors on subsequent connections

**Authentication & RBAC (T023)**:
```bash
kubectl --kubeconfig=/Users/vinodpittampalli/remote-kubeconfig.yaml auth whoami
```
- **Result**: ✅ SUCCESS
- **Username**: `vpittamp@github`
- **Groups**: `system:masters`, `system:authenticated`
- **Privileges**: Cluster-admin (via system:masters)

### Performance Summary

| Metric | Target | Actual | Status |
|--------|--------|--------|--------|
| First connection | <60s (cert provisioning) | ~15s | ✅ PASS |
| Subsequent commands | <2s | 0.469s | ✅ PASS |
| Authentication | Works | vpittamp@github | ✅ PASS |
| TLS validation | Valid after provisioning | Let's Encrypt | ✅ PASS |

### Known Issues

1. **Hostname suffix**: Tailscale operator appends `-13` to hostname (`kind-operator-13` instead of `kind-operator`)
   - **Impact**: Kubeconfig must use full hostname
   - **Resolution**: Use actual hostname from operator logs or Tailscale admin console

2. **First connection delay**: Initial TLS handshake may timeout once before succeeding
   - **Cause**: Let's Encrypt certificate provisioning for MagicDNS hostname
   - **Resolution**: Retry once if first attempt times out

3. **Certificate warning on first attempt**: `x509: certificate is not standards compliant`
   - **Cause**: Certificate provisioning in progress
   - **Resolution**: Automatically resolves on subsequent attempts
