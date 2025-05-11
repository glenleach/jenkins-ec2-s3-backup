#!/usr/bin/env bash

set -e

# Function to get the latest Terraform version from HashiCorp
get_latest_version() {
    curl -sL https://releases.hashicorp.com/terraform/ | grep -oP 'terraform/\K([0-9]+\.[0-9]+\.[0-9]+)' | head -1
}

# Function to get the installed Terraform version, if any
get_installed_version() {
    if command -v terraform >/dev/null 2>&1; then
        terraform version | head -1 | awk '{print $2}' | tr -d 'v'
    else
        echo ""
    fi
}

LATEST_VERSION=$(get_latest_version)
INSTALLED_VERSION=$(get_installed_version)

echo "Latest Terraform version: $LATEST_VERSION"
if [ -n "$INSTALLED_VERSION" ]; then
    echo "Installed Terraform version: $INSTALLED_VERSION"
else
    echo "Terraform is not installed."
fi

if [ "$LATEST_VERSION" = "$INSTALLED_VERSION" ]; then
    echo "Terraform is up to date. No action needed."
    exit 0
fi

echo "Installing Terraform $LATEST_VERSION..."

cd /tmp
wget -q https://releases.hashicorp.com/terraform/${LATEST_VERSION}/terraform_${LATEST_VERSION}_linux_amd64.zip
unzip -o terraform_${LATEST_VERSION}_linux_amd64.zip
chmod +x terraform
# Try to move to /usr/local/bin, fallback to ~/bin if not root
if [ "$(id -u)" -eq 0 ]; then
    mv terraform /usr/local/bin/
else
    mkdir -p "$HOME/bin"
    mv terraform "$HOME/bin/"
    export PATH="$HOME/bin:$PATH"
    echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
fi
rm terraform_${LATEST_VERSION}_linux_amd64.zip

echo "Terraform $(terraform version | head -1) installed successfully."