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
cilium install \
    --version=1.16.5 \
    --set k8sServiceHost=192.168.11.100 \
    --set k8sServicePort=6443 \
    --set kubeProxyReplacement=true \
    --set operator.replicas=1 \
    --set cni.install=true \
    --set cni.exclusive=false \
    --set ipam.mode=kubernetes \
    --set ipv4NativeRoutingCIDR=10.42.0.0/16 \
    --set routingMode=native \
    --set autoDirectNodeRoutes=true \
    --set loadBalancer.algorithm=maglev \
    --set loadBalancer.mode=dsr \
    --set l2announcements.enabled=true \
    --set l2announcements.leaseDuration=15s \
    --set l2announcements.leaseRenewDeadline=5s \
    --set l2announcements.leaseRetryPeriod=2s \
    --set externalIPs.enabled=true \
    --set enableL7Proxy=true \
    --set resources.limits.cpu=2000m \
    --set resources.limits.memory=2Gi \
    --set resources.requests.cpu=100m \
    --set resources.requests.memory=512Mi \
    --set enableRuntimeDeviceDetection=true \
    --set devices=enp5s0 \
    --set hubble.enabled=false

echo "Waiting for Cilium to be ready..."
cilium status --wait

echo "Cilium installation completed successfully!"