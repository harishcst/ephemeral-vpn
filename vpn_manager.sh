#!/bin/bash

TAG="vpn-manager"
install_script="https://github.com/chrissam/openvpn-install-1/blob/master/openvpn-install.sh"

# Ensure that the API token is set in the environment
if [[ -z "$DO_API_TOKEN" ]]; then
    echo "Error: DigitalOcean API token is not set. Please set the DO_API_TOKEN environment variable."
    exit 1
fi

# Ensure SSH key path is set
SSH_KEY_PATH="${SSH_KEY_PATH:-$HOME/.ssh/id_rsa.pub}"

# Function to get SSH key ID from fingerprint
function get_ssh_key_id() {
    local key_fingerprint="$1"
    local response
    response=$(curl -s -X GET "https://api.digitalocean.com/v2/account/keys" \
        -H "Authorization: Bearer $DO_API_TOKEN")

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to retrieve SSH keys."
        exit 1
    fi

    local key_id
    key_id=$(echo "$response" | jq -r --arg fingerprint "$key_fingerprint" '.ssh_keys[] | select(.fingerprint == $fingerprint) | .id // empty')

    echo "$key_id"
}

# Function to get the fingerprint of the local SSH key
function get_local_ssh_key_fingerprint() {
    local key_path="$1"
    if [[ ! -f "$key_path" ]]; then
        echo "Error: SSH key file not found at $key_path"
        exit 1
    fi
    ssh-keygen -E md5 -lf "$key_path" | awk '{print $2}' | sed 's/^MD5://'
}

# Function to add the SSH key to DigitalOcean if not present
function add_ssh_key_to_do() {
    local key_name="$1"
    local key_path="$2"

    # Get the SSH key contents
    local ssh_key_content
    ssh_key_content=$(cat "$key_path")

    local response
    response=$(curl -s -X POST "https://api.digitalocean.com/v2/account/keys" \
        -H "Authorization: Bearer $DO_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "'"$key_name"'",
            "public_key": "'"$ssh_key_content"'"
        }')

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to add SSH key to DigitalOcean."
        exit 1
    fi

    echo "SSH key added to DigitalOcean with name: $key_name"
}

# Function to create a new droplet
function create_droplet() {
    local droplet_name="$1"
    local region="$2"

    # Set default region if not provided
    if [[ -z "$region" ]]; then
        region="nyc1"  # Default region
    fi

    # Validate input parameters
    if [[ -z "$droplet_name" ]]; then
        echo "Error: Droplet name must be provided. Optionally you can pass the region slug where you want to spin the VM"
        echo "Usage: create_vpn <droplet_name> <region-slug>"
        exit 1
    fi

    echo "Creating a new droplet in region $region..."

    # Get the local SSH key fingerprint
    local key_fingerprint
    key_fingerprint=$(get_local_ssh_key_fingerprint "$SSH_KEY_PATH")

    # Get SSH key ID from fingerprint
    local ssh_key_id
    ssh_key_id=$(get_ssh_key_id "$key_fingerprint")

    if [[ -z "$ssh_key_id" ]]; then
        echo "SSH key not found on DigitalOcean. Adding the SSH key..."
        add_ssh_key_to_do "$(hostname)-ssh-key" "$SSH_KEY_PATH"
        ssh_key_id=$(get_ssh_key_id "$key_fingerprint")

        if [[ -z "$ssh_key_id" ]]; then
            echo "Error: Failed to retrieve the SSH key ID after adding the key."
            exit 1
        fi
    fi

    echo "Using SSH key with ID: $ssh_key_id"

    # Create the droplet
    local response
    response=$(curl -s -X POST "https://api.digitalocean.com/v2/droplets" \
        -H "Authorization: Bearer $DO_API_TOKEN" \
        -H "Content-Type: application/json" \
        -d '{
            "name": "'"$droplet_name"'",
            "region": "'"$region"'",
            "size": "s-1vcpu-1gb",
            "image": "ubuntu-24-04-x64",
            "ssh_keys": ['"$ssh_key_id"'],
            "backup": false,
            "ipv6": true,
            "tags": ["'"$TAG"'"]
        }')

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create droplet."
        exit 1
    fi

    local droplet_id
    droplet_id=$(echo "$response" | jq -r '.droplet.id')

    if [[ -z "$droplet_id" ]]; then
        echo "Error: Failed to retrieve droplet ID."
        exit 1
    fi

    echo "Droplet created with ID: $droplet_id"

    # Wait for droplet to become active and assign IP
    local droplet_ip
    droplet_ip=""
    while [[ -z "$droplet_ip" ]]; do
        echo "Waiting for droplet to become active..."
        sleep 30

        local status_response
        status_response=$(curl -s -X GET "https://api.digitalocean.com/v2/droplets/$droplet_id" \
            -H "Authorization: Bearer $DO_API_TOKEN")

        if [[ $? -ne 0 ]]; then
            echo "Error: Failed to check droplet status."
            exit 1
        fi

        droplet_ip=$(echo "$status_response" | jq -r '.droplet.networks.v4[] | select(.type == "public") | .ip_address')

        if [[ -z "$droplet_ip" ]]; then
            echo "Droplet is not active or IP not assigned yet. Retrying in 30 seconds..."
        fi
    done

    echo "Droplet is active at IP: $droplet_ip"

    # Retry SSH connection until successful
    local max_attempts=5
    local attempt=1
    local ssh_command='bash -s'
    local install_script='https://raw.githubusercontent.com/angristan/openvpn-install/master/openvpn-install.sh'
    local ssh_options='-o StrictHostKeyChecking=no -o ConnectTimeout=30'
    local profile_name="$1-$region"

    while [[ $attempt -le $max_attempts ]]; do
        echo "Attempting to install OpenVPN (attempt $attempt of $max_attempts)..."
        ENV_VARS="IPV6_SUPPORT=y PORT_CHOICE=1 PROTOCOL_CHOICE=1 DNS=11 COMPRESSION_ENABLED=n CUSTOMIZE_ENC=n APPROVE_IP=y PASS=1 CLIENT=$profile_name MENU_OPTION=1"
        ssh $ssh_options root@"$droplet_ip" <<EOF
            # Download the OpenVPN installation script
            curl -sL "$install_script" -o /root/openvpn-install.sh

            # Make the script executable
            chmod +x /root/openvpn-install.sh

            # Set environment variables and execute the script
            export $ENV_VARS
            /root/openvpn-install.sh
EOF

        if [[ $? -eq 0 ]]; then
            echo "OpenVPN installed successfully on droplet at $droplet_ip"
            break
        else
            echo "Failed to install OpenVPN. Retrying in 30 seconds..."
            sleep 30
            ((attempt++))
        fi
    done

    if [[ $attempt -gt $max_attempts ]]; then
        echo "Error: Failed to install OpenVPN after $max_attempts attempts."
        exit 1
    fi

    # Fetch the default auto generated vpn profile after installing openvpn
    echo "Fetching .ovpn file for user $profile_name"
    mkdir -p ovpn_files
    scp root@"$droplet_ip":/root/$profile_name.ovpn ./ovpn_files/

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download .ovpn file for user $profile_name."
        exit 1
    fi
}

# Function to create a new VPN user
function create_vpn_user() {
    local droplet_ip="$1"
    local username="$2"

    # Validate input parameters
    if [[ -z "$droplet_ip" || -z "$username" ]]; then
        echo "Error: Both droplet IP and username must be provided."
        echo "Usage: create_vpn_user <droplet_ip> <username>"
        exit 1
    fi

    echo "Creating VPN user $username on droplet $droplet_ip..."

  ENV_VARS="CLIENT=$username MENU_OPTION=1 PASS=1"
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 root@"$droplet_ip" <<EOF
        set -e

        # Download the OpenVPN installation script
        #curl -sL "$install_script" -o /root/openvpn-install.sh

        # Make the script executable
        chmod +x /root/openvpn-install.sh

        # Set environment variables and execute the script
        export $ENV_VARS
        /root/openvpn-install.sh
EOF

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to create VPN user $username."
        exit 1
    fi

    echo "Fetching .ovpn file for user $username..."
    scp root@"$droplet_ip":/root/$username.ovpn ./

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to download .ovpn file for user $username."
        exit 1
    fi

    echo ".ovpn file for user $username downloaded locally."
}

# Function to delete a VPN user
function delete_vpn_user() {
    local droplet_ip="$1"
    local username="$2"

    # Validate input parameters
    if [[ -z "$droplet_ip" || -z "$username" ]]; then
        echo "Error: Both droplet IP and username must be provided."
        echo "Usage: delete_vpn_user <droplet_ip> <username>"
        exit 1
    fi

    echo "Deleting VPN user $username on droplet $droplet_ip..."

    # Use a heredoc with variable interpolation
    ssh -o StrictHostKeyChecking=no -o ConnectTimeout=30 root@"$droplet_ip" <<EOF
    set -e

    # Print debugging information
    echo "Debug: Client name is $username"

    # Find the client in the index file
    CLIENT=\$(tail -n +2 /etc/openvpn/easy-rsa/pki/index.txt | grep "^V" | cut -d '=' -f 2 | grep "^$username\$")

    # Ensure CLIENT is found
    if [[ -z "\$CLIENT" ]]; then
        echo "Error: Client $username not found."
        exit 1
    fi

    echo "Debug: Client to revoke is \$CLIENT"

    echo "Revoking client certificate for $username..."

    cd /etc/openvpn/easy-rsa/

    # Revoke the client certificate
    ./easyrsa --batch revoke "$username"

    # Generate the CRL
    EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl

    # Update the CRL file
    rm -f /etc/openvpn/crl.pem
    cp /etc/openvpn/easy-rsa/pki/crl.pem /etc/openvpn/crl.pem
    chmod 644 /etc/openvpn/crl.pem

    # Clean up client configuration files
    find /home/ -maxdepth 2 -name "$username.ovpn" -delete
    rm -f "/root/$username.ovpn"

    # Update the ipp.txt file
    sed -i "/^$username,.*/d" /etc/openvpn/ipp.txt

    # Backup the index.txt file
    cp /etc/openvpn/easy-rsa/pki/index.txt{,.bk}

    echo "Certificate for client $username revoked."
EOF

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to delete VPN user $username."
        exit 1
    fi

    echo "VPN user $username deleted successfully."
}

# Function to destroy a droplet
function destroy_droplet() {
    local droplet_id="$1"

    if [[ -z "$droplet_id" ]]; then
      echo "Droplet id missing. You need to pass the id of the droplet to be destroyed. Use './vpn_manager.sh list_droplets' to get the droplet id"
      exit 1
    fi

    echo "Destroying droplet $droplet_id..."
    curl -s -X DELETE "https://api.digitalocean.com/v2/droplets/$droplet_id" \
        -H "Authorization: Bearer $DO_API_TOKEN"

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to destroy droplet $droplet_id."
        exit 1
    fi

    echo "Droplet $droplet_id destroyed successfully."
}

# Function to list available regions
function list_regions() {
    # Get the list of regions
    local response
    response=$(curl -s -X GET "https://api.digitalocean.com/v2/regions" \
        -H "Authorization: Bearer $DO_API_TOKEN")

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to retrieve regions."
        exit 1
    fi

    # Check for errors in the API response
    local error_message
    error_message=$(echo "$response" | jq -r '.message // empty')
    if [[ -n "$error_message" ]]; then
        echo "Error from DigitalOcean API: $error_message"
        exit 1
    fi

    # Extract and display regions information
    echo "Available regions:"
    echo "Slug      Name"
    echo "--------------------"

    echo "$response" | jq -r '.regions[] | select(.available == true) | "\(.slug) - \(.name)"'
}

# Function to list droplets
function list_droplets() {
    echo "Listing droplets with tag: $TAG..."
    local response
    response=$(curl -s -X GET "https://api.digitalocean.com/v2/droplets" \
        -H "Authorization: Bearer $DO_API_TOKEN")

    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to retrieve droplets."
        exit 1
    fi

    echo "$response" | jq -r --arg tag "$TAG" '
        .droplets[] | select(
            .tags | index($tag)
        ) | [
            .id,
            .name,
            .region.slug,
            (.networks.v4[] | select(.type == "public") | .ip_address),
            (.networks.v4[] | select(.type == "private") | .ip_address // "N/A")
        ] | @tsv
    ' | column -t
}

# Function to check if OpenVPN is installed
function check_openvpn_installed() {
    if ! command -v openvpn &> /dev/null; then
        echo "Error: OpenVPN is not installed on this system. Please install it first."
        exit 1
    fi
}

# Function to import and use an .ovpn profile
function import_ovpn_profile() {
    local ovpn_file="$1"

    # Check if no argument was passed
    if [[ -z "$ovpn_file" ]]; then
        echo "Error: No OVPN file specified. Please provide the path or name of the .ovpn file."
        echo "Usage: $0 import_ovpn /path/to/your/profile.ovpn"
        exit 1
    fi

    # Append .ovpn if the file name doesn't already end with it
    if [[ "$ovpn_file" != *.ovpn ]]; then
        ovpn_file="${ovpn_file}.ovpn"
    fi

    # If only the name is provided, check in the script's directory
    if [[ ! -f "$ovpn_file" ]]; then
        # Get the directory where this script is located
        local script_dir="$(dirname "$0")"

        # Check if the file exists in the script directory
        if [[ -f "$script_dir/$ovpn_file" ]]; then
            ovpn_file="$script_dir/$ovpn_file"
        else
            echo "Error: OVPN file not found at path $ovpn_file or in the script's directory."
            exit 1
        fi
    fi

    # Check if OpenVPN is installed
    check_openvpn_installed

    echo "Starting OpenVPN with the profile: $ovpn_file"
    sudo openvpn --config "$ovpn_file"
}

# Main function to handle script commands
function main() {
    local command="$1"
    shift

    case "$command" in
        create_vpn)
            create_droplet "$@"
            ;;
        create_user)
            create_vpn_user "$@"
            ;;
        delete_user)
            delete_vpn_user "$@"
            ;;
        destroy_vpn)
            destroy_droplet "$@"
            ;;
        list_regions)
            list_regions
            ;;
        list_droplets)
            list_droplets
            ;;
        import_ovpn)
            import_ovpn_profile "$@"
            ;;
        *)
            echo "Usage: $0 {create_vpn|create_user|delete_user|destroy_vpn|list_regions|list_droplets|import_ovpn} [args...]"
            exit 1
            ;;
    esac
}

# Call the main function with all script
main "$@"
