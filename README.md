# AWS Complete Infrastructure Setup Script

This script automates the setup of a Virtual Private Cloud in AWS with the necessary subnets, gateways, route tables, and security groups. It also deploys a bastion host, web servers, and a classic load balancer.

## Overview

The script performs the following actions:

- **SSH Key Creation**: if it doesn't already exist, creates a new pair of SSH keys on AWS. the private key is downloaded and placed in the default ssh folder of the current user.
- **VPC Creation**: Initializes a VPC with a CIDR block of `10.0.0.0/16`.
- **Internet Gateway**: Sets up an Internet Gateway and attaches it to the VPC.
- **Subnets**: Creates one public subnet (`10.0.1.0/24`) and two private subnets (`10.0.2.0/24` and `10.0.3.0/24`).
- **NAT Gateway**: Provisions a NAT Gateway in the public subnet with an Elastic IP to allow instances in private subnets to access the internet.
- **Route Tables**: Configures route tables for the public and private subnets.
- **Security Groups**: Establishes security groups with rules for web servers (HTTP and HTTPS access) and a bastion host (SSH and OpenVPN access).
- **EC2 Instances**: Launches EC2 instances for the bastion host in the public subnet, web servers in the first private subnet and a private virtual machine in the second private subnet.
- **Classic Load Balancer**: Deploys a Classic Load Balancer to balance traffic between the web servers.

## Prerequisites

- A terminal running BASH
- AWS CLI must be installed and configured with the necessary access permissions.

## Usage

To execute the script, run the following command in your terminal:

```bash
chmod +x ./aws_deployment.sh
./aws_deployment.sh
```
