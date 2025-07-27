#!/usr/bin/env bash

# Bootstrap Age Key for FluxCD SOPS Decryption
set -euo pipefail

NAMESPACE="flux-system"
SECRET_NAME="sops-age"
KEY_NAME="age.agekey"

echo "🔐 Bootstrapping age key for FluxCD SOPS decryption..."

# Check if kubectl is available and cluster is accessible
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Error: kubectl is not configured or cluster is not accessible"
    echo "Make sure your kubeconfig is properly set up"
    exit 1
fi

# Check if pass command is available
if ! command -v pass &> /dev/null; then
    echo "❌ Error: pass (password-store) is not installed"
    echo "Please install pass: https://www.passwordstore.org/"
    exit 1
fi

# Retrieve age key from password store
echo "🔑 Retrieving age key from password store..."
if ! AGE_KEY=$(pass k3s/agekey 2>/dev/null); then
    echo "❌ Error: Could not retrieve age key from 'k3s/agekey'"
    echo "Make sure the key exists in your password store"
    exit 1
fi

# Check if the key looks like a valid age key
if [[ ! "$AGE_KEY" =~ ^AGE-SECRET-KEY-1[A-Z0-9]{58}$ ]]; then
    echo "❌ Error: Retrieved key does not appear to be a valid age secret key"
    echo "Age keys should start with 'AGE-SECRET-KEY-1' and be 64 characters total"
    exit 1
fi

# Create flux-system namespace if it doesn't exist
echo "🏗️  Ensuring flux-system namespace exists..."
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Delete existing secret if it exists
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "🗑️  Removing existing age key secret..."
    kubectl delete secret "$SECRET_NAME" -n "$NAMESPACE"
fi

# Create the secret with the age key
echo "📝 Creating age key secret in Kubernetes..."
kubectl create secret generic "$SECRET_NAME" \
    --from-literal="$KEY_NAME=$AGE_KEY" \
    --namespace="$NAMESPACE"

# Verify the secret was created successfully
if kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" &> /dev/null; then
    echo "✅ Age key secret created successfully!"
    echo ""
    echo "📊 Secret details:"
    kubectl describe secret "$SECRET_NAME" -n "$NAMESPACE"
    echo ""
    echo "🎯 FluxCD can now decrypt SOPS-encrypted secrets using this age key"
else
    echo "❌ Error: Failed to create age key secret"
    exit 1
fi