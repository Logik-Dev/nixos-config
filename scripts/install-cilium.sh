#!/usr/bin/env bash
set -euo pipefail

echo "Starting Cilium installation..."

# Check if Cilium CLI is installed
if ! command -v cilium &> /dev/null; then
    echo "Installing Cilium CLI..."
    CILIUM_CLI_VERSION="v0.16.26"
    curl -L --fail --remote-name-all "https://github.com/cilium/cilium-cli/releases/download/${CILIUM_CLI_VERSION}/cilium-linux-amd64.tar.gz{,.sha256sum}"
    sha256sum --check cilium-linux-amd64.tar.gz.sha256sum
    sudo tar xzvfC cilium-linux-amd64.tar.gz /usr/local/bin
    rm cilium-linux-amd64.tar.gz{,.sha256sum}
fi

# Wait for K3s API server to be ready
echo "Waiting for K3s API server to be ready..."
timeout=300
while ! kubectl get nodes --request-timeout=5s >/dev/null 2>&1; do
    echo "Waiting for K3s API server..."
    sleep 5
    timeout=$((timeout - 5))
    if [ $timeout -le 0 ]; then
        echo "Timeout waiting for K3s API server"
        exit 1
    fi
done

echo "K3s API server is ready, installing Cilium..."

# Install Cilium with L2 announcement configuration
cilium install --version 1.17.6 \
    --set=ipam.operator.clusterPoolIPv4PodCIDRList="10.42.0.0/16" \
    --set kubeProxyReplacement=true \
    --set k8sServiceHost=192.168.11.100 \
    --set k8sServicePort=6443 \
    --set l2announcements.enabled=true \
    --set l2announcements.interfaces="enp6s0" \
    --set devices="enp5s0"

echo "Waiting for Cilium to be ready..."
cilium status --wait

echo "Cilium installation completed successfully!"
