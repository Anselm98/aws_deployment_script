#!/bin/bash

# Enter your key name. If it doesn't already exist, it will be automatically created and the private key will be place in your ssh directory by default.
KEY_NAME="new-aws-key"
KEY_PATH="$HOME/.ssh/${KEY_NAME}.pem"

# Define variables
VPC_NAME="vpc"
REGION="eu-west-1"
IGW_NAME="igw"
NAT_GW_NAME="nat-gw"
PUBLIC_SUBNET_NAME="public-subnet"
PRIVATE_SUBNET_NAME_1="private-subnet-1"
PRIVATE_SUBNET_NAME_2="private-subnet-2"
BASTION_NAME="bastion"
WEB_SERVER1_NAME="web-server-1"
WEB_SERVER2_NAME="web-server-2"
PRIV_VM_NAME="priv-vm"
AMI_ID_DEBIAN="ami-0eb11ab33f229b26c"
INSTANCE_TYPE="t2.micro"
WEB_SERVER_SG_NAME="web-sg"
BASTION_SG_NAME="bastion-sg"
LB_NAME="lb-name"
LISTENER_PORT=80
INSTANCE_PORT=80
PROTOCOL="HTTP"




# Disable pager to have a continuous output
aws configure set cli_pager ""


# Check if the key already exists in the local .ssh folder
if [ ! -f "$KEY_PATH" ]; then
    # Since the key does not exist, create a new key pair and save the private key
    echo "Creating a new EC2 key pair named $KEY_NAME..."
    aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > $KEY_PATH
    
    # Update the file permissions to be read-only by the file's owner
    chmod 400 $KEY_PATH
    echo "The new key pair has been saved to $KEY_PATH"
else
    echo "The key $KEY_NAME already exists at $KEY_PATH. Skipping key creation."
fi


# Create VPC
echo "Creating VPC..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.0.0.0/16 --query 'Vpc.VpcId' --output text --no-cli-pager)
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value=$VPC_NAME
echo "VPC ID: $VPC_ID"

# Create Internet Gateway
echo "Creating Internet Gateway..."
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text --no-cli-pager)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID
echo "Tagging Internet Gateway..."
aws ec2 create-tags --resources $IGW_ID --tags Key=Name,Value=$IGW_NAME
echo "Internet Gateway ID: $IGW_ID"

# Create public subnet
echo "Creating public subnet..."
PUBLIC_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.1.0/24 --query 'Subnet.SubnetId' --output text --no-cli-pager)
aws ec2 create-tags --resources $PUBLIC_SUBNET_ID --tags Key=Name,Value=$PUBLIC_SUBNET_NAME
echo "Public Subnet ID: $PUBLIC_SUBNET_ID"

# Create private subnet
echo "Creating private subnet..."
PRIVATE_SUBNET_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.2.0/24 --query 'Subnet.SubnetId' --output text --no-cli-pager)
aws ec2 create-tags --resources $PRIVATE_SUBNET_ID --tags Key=Name,Value=$PRIVATE_SUBNET_NAME_1
echo "Private Subnet ID: $PRIVATE_SUBNET_ID"

# Create a second private subnet
echo "Creating second private subnet..."
PRIVATE_SUBNET_ID_2=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.0.3.0/24 --query 'Subnet.SubnetId' --output text --no-cli-pager)
aws ec2 create-tags --resources $PRIVATE_SUBNET_ID_2 --tags Key=Name,Value=$PRIVATE_SUBNET_NAME_2
echo "Second Private Subnet ID: $PRIVATE_SUBNET_ID_2"


# Allocate Elastic IP for NAT Gateway
echo "Allocating Elastic IP for NAT Gateway..."
EIP_ALLOC_ID=$(aws ec2 allocate-address --domain vpc --query 'AllocationId' --output text --no-cli-pager)
echo "Elastic IP Allocation ID: $EIP_ALLOC_ID"

# Create NAT Gateway in the public subnet
echo "Creating NAT Gateway..."
NAT_GW_ID=$(aws ec2 create-nat-gateway --subnet-id $PUBLIC_SUBNET_ID --allocation-id $EIP_ALLOC_ID --query 'NatGateway.NatGatewayId' --output text --no-cli-pager)
echo "Waiting for NAT Gateway to become available..."
aws ec2 wait nat-gateway-available --nat-gateway-ids $NAT_GW_ID
echo "Tagging NAT Gateway..."
aws ec2 create-tags --resources $NAT_GW_ID --tags Key=Name,Value=$NAT_GW_NAME
echo "NAT Gateway ID: $NAT_GW_ID"

# Update route table for private subnet to use NAT Gateway
PRIVATE_ROUTE_TABLE_ID=$(aws ec2 create-route-table --vpc-id $VPC_ID --query 'RouteTable.RouteTableId' --output text --no-cli-pager)
aws ec2 create-route --route-table-id $PRIVATE_ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --nat-gateway-id $NAT_GW_ID
aws ec2 create-tags --resources $PRIVATE_ROUTE_TABLE_ID --tags Key=Name,Value="${VPC_NAME}-private-route-table"
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_ID --route-table-id $PRIVATE_ROUTE_TABLE_ID

# Associate the second private subnet with the existing route table
echo "Associating second private subnet with NAT Gateway..."
aws ec2 associate-route-table --subnet-id $PRIVATE_SUBNET_ID_2 --route-table-id $PRIVATE_ROUTE_TABLE_ID


# Create a route table for the public subnet
echo "Creating route table for the public subnet..."
PUBLIC_ROUTE_TABLE_ID=$(aws ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" "Name=association.main,Values=true" --query 'RouteTables[0].RouteTableId' --output text --no-cli-pager)

# Rename the PUBLIC route table
echo "Renaming the PUBLIC route table..."
aws ec2 create-tags --resources $PUBLIC_ROUTE_TABLE_ID --tags Key=Name,Value="${VPC_NAME}-public-route-table"
echo "PUBLIC Route Table ID: $PUBLIC_ROUTE_TABLE_ID"

# Create a route in the PUBLIC route table that directs all traffic to the Internet Gateway
echo "Adding route to direct all traffic to the Internet Gateway in the PUBLIC route table..."
aws ec2 create-route --route-table-id $PUBLIC_ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

# Associate the public subnet with the PUBLIC route table
echo "Associating the public subnet with the PUBLIC public route table..."
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_ID --route-table-id $PUBLIC_ROUTE_TABLE_ID


# Add a route to the route table that directs all traffic to the Internet Gateway
echo "Adding route to direct all traffic to the Internet Gateway..."
aws ec2 create-route --route-table-id $PUBLIC_ROUTE_TABLE_ID --destination-cidr-block 0.0.0.0/0 --gateway-id $IGW_ID

# Associate the public subnet with the route table
echo "Associating the public subnet with the route table..."
aws ec2 associate-route-table --subnet-id $PUBLIC_SUBNET_ID --route-table-id $PUBLIC_ROUTE_TABLE_ID


# Create Security Group for Web Servers
echo "Creating Security Group for Web Servers..."
WEB_SERVER_SG_ID=$(aws ec2 create-security-group --group-name $WEB_SERVER_SG_NAME --description "Security Group for Web Servers" --vpc-id $VPC_ID --query 'GroupId' --output text --no-cli-pager)
echo "Web Server Security Group ID: $WEB_SERVER_SG_ID"

# Add rules to Web Server Security Group (Allow HTTP and HTTPS)
echo "Adding rules to Web Server Security Group..."
aws ec2 authorize-security-group-ingress --group-id $WEB_SERVER_SG_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $WEB_SERVER_SG_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $WEB_SERVER_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

# Create Security Group for Bastion Host
echo "Creating Security Group for Bastion Host..."
BASTION_SG_ID=$(aws ec2 create-security-group --group-name $BASTION_SG_NAME --description "Security Group for Bastion Host" --vpc-id $VPC_ID --query 'GroupId' --output text --no-cli-pager)
echo "Bastion Host Security Group ID: $BASTION_SG_ID"

# Add rule to Bastion Host Security Group (Allow SSH)
echo "Adding SSH rule to Bastion Host Security Group..."
aws ec2 authorize-security-group-ingress --group-id $BASTION_SG_ID --protocol tcp --port 22 --cidr 0.0.0.0/0
# Add rule to Bastion Host Security Group (Allow OpenVPN)
aws ec2 authorize-security-group-ingress --group-id $BASTION_SG_ID --protocol udp --port 1194 --cidr 0.0.0.0/0


# Launch Bastion Host in public subnet
echo "Launching Bastion Host in public subnet..."
BASTION_ID=$(aws ec2 run-instances --image-id $AMI_ID_DEBIAN --count 1 --instance-type $INSTANCE_TYPE --associate-public-ip-address --key-name $KEY_NAME --security-group-ids $BASTION_SG_ID --subnet-id $PUBLIC_SUBNET_ID --query 'Instances[0].InstanceId' --output text --no-cli-pager)
aws ec2 create-tags --resources $BASTION_ID --tags Key=Name,Value=$BASTION_NAME
echo "Bastion Host Instance ID: $BASTION_ID"


# Launch Web Server 1 in private subnet
echo "Launching Web Server 1..."
WEB_SERVER1_ID=$(aws ec2 run-instances --image-id $AMI_ID_DEBIAN --count 1 --instance-type $INSTANCE_TYPE --key-name $KEY_NAME --subnet-id $PRIVATE_SUBNET_ID --security-group-ids $WEB_SERVER_SG_ID --query 'Instances[0].InstanceId' --output text --no-cli-pager)
aws ec2 create-tags --resources $WEB_SERVER1_ID --tags Key=Name,Value=$WEB_SERVER1_NAME
echo "Web Server 1 Instance ID: $WEB_SERVER1_ID"

# Launch Web Server 2 with the new security group
echo "Launching Web Server 2..."
WEB_SERVER2_ID=$(aws ec2 run-instances --image-id $AMI_ID_DEBIAN --count 1 --instance-type $INSTANCE_TYPE --key-name $KEY_NAME --subnet-id $PRIVATE_SUBNET_ID --security-group-ids $WEB_SERVER_SG_ID --query 'Instances[0].InstanceId' --output text --no-cli-pager)
aws ec2 create-tags --resources $WEB_SERVER2_ID --tags Key=Name,Value=$WEB_SERVER2_NAME
echo "Web Server 2 Instance ID: $WEB_SERVER2_ID"

# Launch an additional VM in the second private subnet
echo "Launching VM in second private subnet..."
PRIV_VM_ID=$(aws ec2 run-instances --image-id $AMI_ID_DEBIAN --count 1 --instance-type $INSTANCE_TYPE --key-name $KEY_NAME --subnet-id $PRIVATE_SUBNET_ID_2 --security-group-ids $WEB_SERVER_SG_ID --query 'Instances[0].InstanceId' --output text --no-cli-pager)
aws ec2 create-tags --resources $PRIV_VM_ID --tags Key=Name,Value=$PRIV_VM_NAME
echo "VM Instance ID in second private subnet: $PRIV_VM_ID"

# Create a Classic Load Balancer
echo "Creating Classic Load Balancer..."
CLB_DNS_NAME=$(aws elb create-load-balancer --load-balancer-name $LB_NAME --listeners "Protocol=$PROTOCOL,LoadBalancerPort=$LISTENER_PORT,InstanceProtocol=$PROTOCOL,InstancePort=$INSTANCE_PORT" --subnets $PUBLIC_SUBNET_ID --security-groups $WEB_SERVER_SG_ID --query 'DNSName' --output text --no-cli-pager)
echo "Classic Load Balancer DNS Name: $CLB_DNS_NAME"

# Register Web Server Instances with the Load Balancer
echo "Registering instances with the Load Balancer..."
aws elb register-instances-with-load-balancer --load-balancer-name $LB_NAME --instances $WEB_SERVER1_ID $WEB_SERVER2_ID

# Configure Health Check for the Load Balancer
echo "Configuring Health Check..."
aws elb configure-health-check --load-balancer-name $LB_NAME --health-check Target=HTTP:$INSTANCE_PORT/index.html,Interval=30,UnhealthyThreshold=2,HealthyThreshold=2,Timeout=3



echo "Setup completed."