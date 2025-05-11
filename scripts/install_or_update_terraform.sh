#!/usr/bin/env bash

set -e

# Enable debug mode if DEBUG=true
if [ "${DEBUG:-false}" = "true" ]; then
    set -x
fi

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Install jq if not present (needed for API parsing)
install_jq_if_needed() {
    if ! command_exists jq; then
        echo "Installing jq..."
        if command_exists apt-get; then
            sudo apt-get update && sudo apt-get install -y jq
        elif command_exists yum; then
            sudo yum install -y jq
        elif command_exists brew; then
            brew install jq
        else
            echo "ERROR: Cannot install jq. Please install it manually and try again."
            exit 1
        fi
    fi
}

# Function to get the latest Terraform version from HashiCorp API
get_latest_version() {
    if command_exists jq; then
        # Use the official HashiCorp API
        curl -s https://checkpoint-api.hashicorp.com/v1/check/terraform | jq -r .current_version
    else
        # Fallback to parsing the releases page
        curl -sL https://releases.hashicorp.com/terraform/ | grep -oP 'terraform/\K([0-9]+\.[0-9]+\.[0-9]+)' | head -1
    fi
}

# Function to get the installed Terraform version, if any
get_installed_version() {
    if command_exists terraform; then
        terraform version | head -1 | awk '{print $2}' | tr -d 'v'
    else
        echo ""
    fi
}

# Try to install jq for better version detection
install_jq_if_needed

# Get versions with error handling
echo "Checking for latest Terraform version..."
LATEST_VERSION=$(get_latest_version)
if [ -z "$LATEST_VERSION" ]; then
    echo "ERROR: Failed to determine latest Terraform version. Check your internet connection."
    exit 1
fi

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

# Create temp directory and clean it on exit
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$TMP_DIR"

# Download with progress and error handling
echo "Downloading Terraform ${LATEST_VERSION}..."
DOWNLOAD_URL="https://releases.hashicorp.com/terraform/${LATEST_VERSION}/terraform_${LATEST_VERSION}_linux_amd64.zip"
if ! wget -O "terraform_${LATEST_VERSION}_linux_amd64.zip" "$DOWNLOAD_URL"; then
    echo "ERROR: Failed to download Terraform. Check your internet connection."
    exit 1
fi

# Verify download
echo "Verifying download..."
if ! file "terraform_${LATEST_VERSION}_linux_amd64.zip" | grep -q "Zip archive data"; then
    echo "ERROR: Downloaded file is not a valid zip archive."
    exit 1
fi

# Extract and install
echo "Extracting Terraform..."
if ! unzip -o "terraform_${LATEST_VERSION}_linux_amd64.zip"; then
    echo "ERROR: Failed to extract Terraform."
    exit 1
fi

chmod +x terraform

# Try to move to /usr/local/bin, fallback to ~/bin if not root
echo "Installing Terraform binary..."
if [ "$(id -u)" -eq 0 ]; then
    mv terraform /usr/local/bin/
else
    # Try with sudo first
    if command_exists sudo && sudo -n true 2>/dev/null; then
        sudo mv terraform /usr/local/bin/
    else
        # Fallback to user's bin directory
        mkdir -p "$HOME/bin"
        mv terraform "$HOME/bin/"
        export PATH="$HOME/bin:$PATH"
        
        # Add to PATH if not already there
        if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc"; then
            echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
            echo "Added $HOME/bin to your PATH in .bashrc"
        fi
    fi
fi

# Verify installation
if ! command_exists terraform; then
    echo "ERROR: Terraform installation failed. Please check permissions and try again."
    exit 1
fi

echo "Terraform $(terraform version | head -1) installed successfully!"
echo "You may need to restart your shell or run 'source ~/.bashrc' to use Terraform."
