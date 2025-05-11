#!/usr/bin/env bash
set -euo pipefail

# Enable debug mode if DEBUG=true
if [[ "${DEBUG:-false}" == "true" ]]; then
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

# Try to install jq for better version detection
install_jq_if_needed

echo "Checking for latest Terraform version..."

# Use GitHub API to get the latest stable release tag
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo "ERROR: GITHUB_TOKEN environment variable not set. Please provide a GitHub token to avoid API rate limits."
    exit 1
fi

AUTH_HEADER="Authorization: token $GITHUB_TOKEN"

# Try up to 3 times to get the latest version
MAX_RETRIES=3
RETRY_COUNT=0
LATEST_VERSION=""

while [[ -z "$LATEST_VERSION" && $RETRY_COUNT -lt $MAX_RETRIES ]]; do
    LATEST_VERSION=$(curl -sH "$AUTH_HEADER" "https://api.github.com/repos/hashicorp/terraform/releases" | \
        jq -r '[.[] | select(.prerelease == false and .draft == false) | .tag_name | select(test("^v?[0-9]+\\.[0-9]+\\.[0-9]+$"))] | map(ltrimstr("v")) | sort_by(split(".") | map(tonumber)) | last')
    
    if [[ -z "$LATEST_VERSION" ]]; then
        RETRY_COUNT=$((RETRY_COUNT + 1))
        echo "Attempt $RETRY_COUNT failed. Retrying in 5 seconds..."
        sleep 5
    fi
done

if [[ -z "$LATEST_VERSION" ]]; then
    echo "ERROR: Failed to determine latest Terraform version from GitHub API after $MAX_RETRIES attempts."
    exit 1
fi

# Get installed version (if any)
if command_exists terraform; then
    INSTALLED_VERSION=$(terraform version | head -1 | awk '{print $2}' | tr -d 'v')
else
    INSTALLED_VERSION=""
fi

echo "Latest Terraform version: $LATEST_VERSION"
if [ -n "$INSTALLED_VERSION" ]; then
    echo "Installed Terraform version: $INSTALLED_VERSION"
else
    echo "Terraform is not installed."
fi

if [[ "$LATEST_VERSION" == "$INSTALLED_VERSION" ]]; then
    echo "Terraform is up to date. No action needed."
    exit 0
fi

echo "Installing Terraform $LATEST_VERSION..."

# Create temp directory and clean it on exit
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT

cd "$TMP_DIR"

# Determine OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Map architecture to Terraform's naming convention
case "$ARCH" in
    x86_64)
        TERRAFORM_ARCH="amd64"
        ;;
    arm64|aarch64)
        TERRAFORM_ARCH="arm64"
        ;;
    386|i386)
        TERRAFORM_ARCH="386"
        ;;
    *)
        echo "ERROR: Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

# Download with error handling
ZIP_FILE="terraform_${LATEST_VERSION}_${OS}_${TERRAFORM_ARCH}.zip"
DOWNLOAD_URL="https://releases.hashicorp.com/terraform/${LATEST_VERSION}/${ZIP_FILE}"

echo "Downloading Terraform ${LATEST_VERSION} for ${OS}_${TERRAFORM_ARCH}..."
MAX_DOWNLOAD_ATTEMPTS=3
DOWNLOAD_ATTEMPT=1

while [[ $DOWNLOAD_ATTEMPT -le $MAX_DOWNLOAD_ATTEMPTS ]]; do
    if curl -fsSL -o "$ZIP_FILE" "$DOWNLOAD_URL"; then
        break
    else
        echo "Download attempt $DOWNLOAD_ATTEMPT failed."
        if [[ $DOWNLOAD_ATTEMPT -lt $MAX_DOWNLOAD_ATTEMPTS ]]; then
            echo "Retrying in 5 seconds..."
            sleep 5
        else
            echo "ERROR: Failed to download Terraform after $MAX_DOWNLOAD_ATTEMPTS attempts."
            exit 1
        fi
        DOWNLOAD_ATTEMPT=$((DOWNLOAD_ATTEMPT + 1))
    fi
done

# Verify download
echo "Verifying download..."
if command_exists file; then
    FILE_TYPE=$(file "$ZIP_FILE")
    echo "$ZIP_FILE: $FILE_TYPE"
    if [[ "$FILE_TYPE" != *"Zip archive data"* ]]; then
        echo "ERROR: Downloaded file is not a valid zip archive."
        exit 1
    fi
fi

# Extract and install
echo "Extracting Terraform..."
if ! unzip -o "$ZIP_FILE"; then
    echo "ERROR: Failed to extract Terraform."
    exit 1
fi

chmod +x terraform

# Try to move to /usr/local/bin, fallback to ~/bin if not root
echo "Installing Terraform binary..."
if [[ "$(id -u)" -eq 0 ]]; then
    mv terraform /usr/local/bin/
elif command_exists sudo && sudo -n true 2>/dev/null; then
    sudo mv terraform /usr/local/bin/
else
    # Fallback to user's bin directory
    mkdir -p "$HOME/bin"
    mv terraform "$HOME/bin/"
    export PATH="$HOME/bin:$PATH"
    
    # Add to PATH if not already there
    if ! grep -q 'export PATH="$HOME/bin:$PATH"' "$HOME/.bashrc" 2>/dev/null; then
        echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
        echo "Added $HOME/bin to your PATH in .bashrc"
    fi
fi

# Verify installation
if ! command_exists terraform; then
    echo "ERROR: Terraform installation failed. Please check permissions and try again."
    exit 1
fi

# Verify the installed version matches what we expected
VERIFIED_VERSION=$(terraform version | head -1 | awk '{print $2}' | tr -d 'v')
if [[ "$VERIFIED_VERSION" != "$LATEST_VERSION" ]]; then
    echo "WARNING: Installed version ($VERIFIED_VERSION) does not match expected version ($LATEST_VERSION)"
else
    echo "Terraform v$VERIFIED_VERSION installed successfully!"
fi

# Add helpful instructions
if [[ -d "$HOME/bin" && -f "$HOME/bin/terraform" ]]; then
    echo "Terraform was installed to $HOME/bin/terraform"
    echo "You may need to restart your shell or run 'source ~/.bashrc' to use Terraform."
else
    echo "Terraform was installed to $(which terraform)"
fi
