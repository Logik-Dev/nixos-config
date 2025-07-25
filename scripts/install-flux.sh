#!/usr/bin/env bash

# FluxCD Installation Script for K3s Cluster
set -euo pipefail

CLUSTER_NAME="k3s"
GITHUB_USER="Logik-Dev"
REPOSITORY="nixos-config"
BRANCH="main"
PATH_PREFIX="./flux/clusters/k3s"

echo "🚀 Installing FluxCD on K3s cluster..."

# Check if kubectl is available and cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Error: kubectl is not configured or cluster is not accessible"
    echo "Make sure your kubeconfig is properly set up"
    exit 1
fi

# Check if flux CLI is installed
if ! command -v flux &> /dev/null; then
    echo "❌ Error: flux CLI is not installed"
    echo "Please install flux CLI: https://fluxcd.io/flux/installation/"
    exit 1
fi

# Check flux prerequisites
echo "🔍 Checking flux prerequisites..."
flux check --pre

# Bootstrap FluxCD
echo "🎯 Bootstrapping FluxCD..."
flux bootstrap github \
    --owner="${GITHUB_USER}" \
    --repository="${REPOSITORY}" \
    --branch="${BRANCH}" \
    --path="${PATH_PREFIX}" \
    --personal \
    --components-extra=image-reflector-controller,image-automation-controller

echo "✅ FluxCD installation completed!"

# Wait for FluxCD to be ready
echo "⏳ Waiting for FluxCD components to be ready..."
kubectl wait --for=condition=ready pod -l app=source-controller -n flux-system --timeout=300s
kubectl wait --for=condition=ready pod -l app=kustomize-controller -n flux-system --timeout=300s
kubectl wait --for=condition=ready pod -l app=helm-controller -n flux-system --timeout=300s

echo "🎉 FluxCD is ready! (Cilium is installed separately via script)"
echo ""
echo "📊 To monitor the deployment:"
echo "  kubectl get pods -n flux-system"
echo "  kubectl get pods -n kube-system"
echo "  flux get sources git"
echo "  flux get kustomizations"
echo "  flux get helmreleases"