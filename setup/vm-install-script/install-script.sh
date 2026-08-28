#!/bin/bash
set -euo pipefail

# Validate that the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "ERROR: This script must be run as root (sudo ./install-script.sh)"
  exit 1
fi

echo ".........----------------#################._.-.-INSTALL-.-._.#################----------------........."
PS1='\[\e[01;36m\]\u\[\e[01;37m\]@\[\e[01;33m\]\H\[\e[01;37m\]:\[\e[01;32m\]\w\[\e[01;37m\]\$\[\033[0;37m\] '
echo "PS1='\[\e[01;36m\]\u\[\e[01;37m\]@\[\e[01;33m\]\H\[\e[01;37m\]:\[\e[01;32m\]\w\[\e[01;37m\]\$\[\033[0;37m\] '" >> ~/.bashrc
sed -i '1s/^/force_color_prompt=yes\n/' ~/.bashrc

# Clean up packages that are no longer needed
apt-get autoremove -y
systemctl daemon-reload

# Create keyrings directory for GPG keys
mkdir -p /etc/apt/keyrings

# Remove old repository files and GPG keys from previous runs
rm -f /etc/apt/sources.list.d/kubernetes.list
rm -f /etc/apt/sources.list.d/jenkins.list
rm -f /usr/share/keyrings/kubernetes-archive-keyring.gpg
rm -f /etc/apt/keyrings/kubernetes-apt-keyring.gpg
rm -f /etc/apt/keyrings/jenkins.gpg

# Add Kubernetes v1.30 repository with modern GPG keyring method
curl -fsSL https://pkgs.kubernetes.io/core:/stable:/v1.30/deb/Release.key | gpg --dearmor --batch --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
deb [trusted=yes] https://pkgs.kubernetes.io/core:/stable:/v1.30/deb/ /
EOF

# Install Kubernetes components, Docker, and required tools
KUBE_VERSION=1.30.9
apt-get update
apt-get install -y docker.io vim build-essential jq python3-pip kubelet=${KUBE_VERSION}-1.1 kubectl=${KUBE_VERSION}-1.1 kubernetes-cni=1.4.0-1.1 kubeadm=${KUBE_VERSION}-1.1 cri-tools=1.30.1-1.1
pip3 install --break-system-packages jc

# Configure Docker with systemd cgroup driver (required by Kubernetes)
cat > /etc/docker/daemon.json <<EOF
{
  "exec-opts": ["native.cgroupdriver=systemd"],
  "log-driver": "json-file",
  "storage-driver": "overlay2"
}
EOF
mkdir -p /etc/systemd/system/docker.service.d

# Restart and enable Docker and kubelet services
systemctl daemon-reload
systemctl restart docker
systemctl enable docker
systemctl enable kubelet
systemctl start kubelet

echo ".........----------------#################._.-.-KUBERNETES-.-._.#################----------------........."
# Clean up previous cluster configuration
[ -f /root/.kube/config ] && rm /root/.kube/config
kubeadm reset -f

# Initialize the Kubernetes control plane
kubeadm init --kubernetes-version=${KUBE_VERSION} --skip-token-print

# Configure kubectl for root user
mkdir -p ~/.kube
cp -i /etc/kubernetes/admin.conf ~/.kube/config

# Wait for the API server to become available
echo "Waiting for the API server to be ready..."
until kubectl get nodes &>/dev/null; do
  sleep 2
done

# Install Weave Net CNI plugin for pod networking
echo "Installing Weave Net..."
kubectl apply -f https://github.com/weaveworks/weave/releases/download/v2.8.1/weave-daemonset-k8s.yaml --validate=false || true

# Wait for the node to become Ready (may take 2-3 minutes)
echo "Waiting for the node to be Ready (this may take 2-3 minutes)..."
for i in $(seq 1 60); do
  STATUS=$(kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || true)
  if echo "$STATUS" | grep -q "True"; then
    echo "Node is Ready!"
    break
  fi
  echo "  Waiting... ($i/60)"
  sleep 5
done
kubectl get nodes -o wide

# Remove control plane taints to allow scheduling pods on the master node
echo "Removing control plane taints..."
kubectl taint node $(kubectl get nodes -o=jsonpath='{.items[].metadata.name}') node.kubernetes.io/not-ready:NoSchedule- || true
kubectl taint node $(kubectl get nodes -o=jsonpath='{.items[].metadata.name}') node-role.kubernetes.io/control-plane:NoSchedule- || true
kubectl get node -o wide


echo ".........----------------#################._.-.-Java and MAVEN-.-._.#################----------------........."
apt install openjdk-11-jdk -y
java -version
apt install -y maven
mvn -v


echo ".........----------------#################._.-.-JENKINS-.-._.#################----------------........."
# Add Jenkins repository with GPG key
rm -f /etc/apt/sources.list.d/jenkins.list
curl -fsSL https://pkg.jenkins.io/debian-stable/jenkins.io.key | gpg --dearmor --batch --yes -o /etc/apt/keyrings/jenkins.gpg
echo "deb [trusted=yes] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
apt-get update
apt-get install -y jenkins

# Enable and start Jenkins service
systemctl enable jenkins
systemctl start jenkins

# Grant Jenkins user access to Docker and sudo without password
usermod -a -G docker jenkins
echo "jenkins ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

echo ".........----------------#################._.-.-COMPLETED-.-._.#################----------------........."
