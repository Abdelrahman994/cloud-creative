provider "aws" {
  region = "us-east-1"
}

# ----------------- VPC -----------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "main-vpc"
  }
}

# ------------- Internet Gateway -------------
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

# ----------------- Subnets -----------------
# 1. Public Subnets
resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "public-subnet-a" }
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "public-subnet-b" }
}

# 2. Web Tier Private Subnets
resource "aws_subnet" "web_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.11.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "web-private-subnet-a" }
}

resource "aws_subnet" "web_private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.12.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "web-private-subnet-b" }
}

# 3. App Tier Private Subnets
resource "aws_subnet" "app_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.21.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "app-private-subnet-a" }
}

resource "aws_subnet" "app_private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.22.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "app-private-subnet-b" }
}

# 4. Data Tier Private Subnets
resource "aws_subnet" "data_private_a" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "us-east-1a"
  tags = { Name = "data-private-subnet-a" }
}

resource "aws_subnet" "data_private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "data-private-subnet-b" }
}

# --------------- NAT Gateway ---------------
# Elastic IP for NAT
resource "aws_eip" "nat_eip" {
  domain = "vpc"
}

# Creating NAT in Public Subnet A 
resource "aws_nat_gateway" "nat_gw" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_a.id
  depends_on    = [aws_internet_gateway.igw]
  tags = { Name = "main-nat-gw" }
}

# --------------- Route Tables ---------------

# 1. Public Route Table (Routes to IGW)
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
  tags = { Name = "public-rt" }
}

resource "aws_route_table_association" "public_a_assoc" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_b_assoc" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public_rt.id
}

# 2. Private Route Table for Web & App (Routes to NAT for Patching)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat_gw.id
  }
  tags = { Name = "private-rt-web-app" }
}

# Web Tier Associations
resource "aws_route_table_association" "web_a_assoc" {
  subnet_id      = aws_subnet.web_private_a.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "web_b_assoc" {
  subnet_id      = aws_subnet.web_private_b.id
  route_table_id = aws_route_table.private_rt.id
}

# App Tier Associations
resource "aws_route_table_association" "app_a_assoc" {
  subnet_id      = aws_subnet.app_private_a.id
  route_table_id = aws_route_table.private_rt.id
}
resource "aws_route_table_association" "app_b_assoc" {
  subnet_id      = aws_subnet.app_private_b.id
  route_table_id = aws_route_table.private_rt.id
}

# 3. Data Tier Route Table (Completely Isolated)
resource "aws_route_table" "data_rt" {
  vpc_id = aws_vpc.main.id
  # No internet or NAT routes
  tags = { Name = "isolated-rt-data" }
}

# Data Tier Associations
resource "aws_route_table_association" "data_a_assoc" {
  subnet_id      = aws_subnet.data_private_a.id
  route_table_id = aws_route_table.data_rt.id
}
resource "aws_route_table_association" "data_b_assoc" {
  subnet_id      = aws_subnet.data_private_b.id
  route_table_id = aws_route_table.data_rt.id
}

# ----------- S3 VPC Endpoint (For Data Tier Backups) -----------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.us-east-1.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.data_rt.id]
  tags = { Name = "s3-vpc-endpoint" }
}