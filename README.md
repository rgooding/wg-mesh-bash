# wg-mesh-bash

This is a bash script to create a simple mesh network using WireGuard. Configuration is all performed over SSH 
and private keys never leave the machines.

Tested on Debian 11 and Raspberry Pi OS 11.

### Requirements:
- SSH access to all hosts, either as root or as a user with password-less sudo rights
- A direct network connection between all hosts (this could be over the public Internet or local LAN)

## Usage

1. Rename or copy the `inventory-example` file to `inventory` then edit it to your needs. See the comments for usage information.
2. Edit the variables at the top of `deploy.sh` if required
3. Run `./deploy.sh` to deploy and activate the network

## What the script does

- Install the `wireguard` package and its dependencies if it is not already present
- Allocates a static IP address on the mesh network for each host, this is stored in the `cfg` directory
- Generate private and public keys on each host, these are generated once per host+interface.
- Generate and install the config file for the mesh network interface on each host
- (optionally) Start or reconfigure the mesh network interface on each host
