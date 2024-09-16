
# VPN Manager Script

## Overview

This project provides a **dynamic solution** for creating and managing ephemeral VPN servers using **DigitalOcean**. The VPN Manager script automates the process of provisioning secure OpenVPN servers, adding and removing users, and tearing down the server when it's no longer needed.

This solution is designed to be lightweight and simple to use, perfect for personal VPN needs, such as when traveling or working from public places. The script uses the **DigitalOcean API** to handle infrastructure, making it easy to deploy VPN servers in different regions around the world.

The script internally uses the [openvpn-install](https://github.com/angristan/openvpn-install) wrapper script to Install and manage OpenVPN.

## Features

- **Create a VPN server on-demand** in any region supported by DigitalOcean.
- **Add or remove users** on the VPN server with ease.
- **Tear down the VPN server** when it is no longer required, saving costs.
- **Choose the geographic location** of your VPN server to access region-specific content.
- **Secure connections** using the OpenVPN protocol.
- **Simple, no-frills approach**—no need for additional tools like Terraform or Ansible.

## Prerequisites

Before using the script, ensure that you have the following:
- A **DigitalOcean account**. If you don’t have one, you can use [this referral link](https://devopsideas.com/recommends/digitalocean_cloud) to get $200 in free credits.
- A **DigitalOcean API token**. You can generate one in the [API section of your DigitalOcean dashboard](https://cloud.digitalocean.com/account/api/tokens).
- OpenSSH installed on your local machine to handle SSH connections.
- Openvpn command line client (optional - for importing profiles through cli)

## Installation

Clone the repository to your local machine:

```bash
git clone https://github.com/yourusername/vpn-manager.git
cd vpn-manager
```

Ensure that the script is executable:

```bash
chmod +x vpn_manager.sh
```

## Configuration

Set your **DigitalOcean API token** as an environment variable. This is necessary for the script to interact with DigitalOcean’s API.

```bash
export DO_API_TOKEN=your_digitalocean_api_token
```

Optionally, set the path to your SSH key:

```bash
export SSH_KEY_PATH=~/.ssh/id_rsa.pub
```

If you don't set the SSH key path, the script will use `~/.ssh/id_rsa.pub` by default.

## Usage

The **vpn_manager.sh** script supports the following commands:

### 1. Create a New VPN Server

```bash
./vpn_manager.sh create_vpn <droplet_name> <region>
```

- `droplet_name`: The name of the new VPN server.
- `region`: The region to deploy the server (e.g., `nyc1`, `lon1`). If not specified, a default region will be used.

Example:

```bash
./vpn_manager.sh create_vpn personal-vpn lon1
```

First checks if your ssh key is available in DigitalOcean infra. If not, it adds your ssh key in DO through the API. It then spins up a new DigitalOcean Droplet in the London (`lon1`) region, attaches your ssh key, installs OpenVPN on it, and gets it ready for secure connections. It also generates a default profile in the format <droplet_name-region>.ovpn. and downloads it to your local.

### 2. List Available Regions

```bash
./vpn_manager.sh list_regions
```

This command lists all the available DigitalOcean regions where you can deploy your VPN server.

### 3. List Active Droplets

```bash
./vpn_manager.sh list_droplets
```

This command lists all active DigitalOcean droplets that were created using the script. It displays the droplet ID, name, region, and IP addresses.

### 4. Add a New VPN User

```bash
./vpn_manager.sh create_user <droplet_ip> <username>
```

- `droplet_ip`: The public IP address of the VPN server.
- `username`: The name of the new VPN user.

Example:

```bash
./vpn_manager.sh create_user 123.45.67.89 johndoe
```

This creates a new VPN user named "johndoe" and generates an `.ovpn` configuration file for them. It also downloads the .ovpn file in the directory of the script.

### 5. Delete a VPN User

```bash
./vpn_manager.sh delete_user <droplet_ip> <username>
```

- `droplet_ip`: The public IP address of the VPN server.
- `username`: The name of the user whose access you want to revoke.

Example:

```bash
./vpn_manager.sh delete_user 123.45.67.89 johndoe
```

This revokes access for the user "johndoe" on the specified VPN server.

### 6. Destroy the VPN Server

```bash
./vpn_manager.sh destroy_vpn <droplet_id>
```

- `droplet_id`: The ID of the droplet you want to destroy (this can be found using the `list_droplets` command).

Example:

```bash
./vpn_manager.sh destroy_vpn 87654321
```

This will destroy the VPN server, removing all associated resources from your DigitalOcean account.

### 7. Import the VPN Profile

Once you create a new VPN user, an `.ovpn` file will be generated. You can use the following command to import the VPN profile into your OpenVPN client.

```bash
./vpn_manager.sh import_ovpn <ovpn_file>
```

- `ovpn_file`: The path to the `.ovpn` file for the VPN user.

Example:

```bash
./vpn_manager.sh import_ovpn johndoe.ovpn
```

This will import the VPN profile for "johndoe" into your OpenVPN client.

## Example Workflow

Here’s a typical workflow for using the script:

1. **Create a VPN server**:
   ```bash
   ./vpn_manager.sh create_vpn myvpn lon1
   ```

2. **Add a user to the VPN (Optional)**:
   ```bash
   ./vpn_manager.sh create_user 123.45.67.89 alice
   ```
  This is optional. You can use the default profile (<droplet_name-region>.ovpn) that gets created while you create the VPN. 

4. **Connect to the VPN** using your OpenVPN client.

5. **Destroy the VPN server** when no longer needed:
   ```bash
   ./vpn_manager.sh destroy_vpn 87654321
   ```

## Ensure your connection is secure and connected to VPN

Use [Browser Leaks](https://browserleaks.com/) and run the tests to ensure your connection is secure and connected to VPN.

## License

This project is licensed under the **MIT License**. See the [LICENSE](LICENSE) file for more details.

## Contributing

Contributions are welcome! Feel free to open an issue or submit a pull request to improve the script.
