# AWS Three-Tier Web Architecture Migration (RetailEdge Inc.)

## 📌 Project Overview
This repository contains the Infrastructure as Code (IaC) written in **Terraform** to provision a highly available, scalable, and secure three-tier web architecture on AWS. The project simulates a cloud migration and infrastructure modernization effort for a retail application, transitioning from a monolithic design to a decoupled, resilient cloud-native architecture.

## 🏗️ Architecture Diagram
*(Add your architecture diagram image here. e.g., `![Architecture Diagram](./image_5d1087.png)`)*

## 🚀 Key Features & Design Decisions

### 1. Network Isolation & Security (VPC Design)
- **Custom VPC** (`10.0.0.0/16`) spanning two Availability Zones for high availability.
- **8 Subnets Architecture**:
  - **2 Public Subnets**: The primary Internet-facing Application Load Balancer MUST be deployed in these public subnets to successfully receive external traffic from the internet. A NAT Gateway is also provisioned here.
  - **6 Private Subnets**: Divided into Web Tier, App Tier, and a completely isolated Data Tier.
- **Chained Security Groups (Zero-Trust)**:
  - **Bastion Host SG**: Allows SSH (port 22) access for management.
  - **Web Tier SG**: Accepts HTTP (port 80) only from the External ALB.
  - **App Tier SG**: Accepts API traffic (port 4000) only from the Internal ALB.
  - **Data Tier SG**: Accepts MySQL (3306) and Redis (6379) traffic strictly from the App Tier SG.

### 2. Compute & Auto Scaling (Web & App Tiers)
- **Web Tier (Frontend)**: Runs an Nginx web server serving a compiled React application. 
- **App Tier (Backend)**: Runs a Node.js REST API managed by PM2.
- **Launch Templates**: Utilized `m7i-flex.large` instances with automated `user_data` bash scripts. The frontend script dynamically injects the Internal ALB DNS into the Nginx configuration during boot.
- **Auto Scaling Groups (ASG)**: Configured with `min=2`, `desired=2`, and `max=10`.
- **Target Tracking**: Scaling policies automatically adjust capacity based on an `ASGAverageCPUUtilization` target of 60%.

### 3. Resilient Data Tier
- **Amazon RDS (MySQL 8.0)**: Deployed in private subnets with `Multi-AZ` enabled for synchronous replication and automatic failover.
- **Amazon ElastiCache (Redis)**: A 2-node cluster with automatic failover enabled to handle caching and reduce database latency.
- **Total Isolation**: The Data Tier route tables have no routes to an Internet Gateway or NAT Gateway, ensuring maximum security compliance.

---

## 🚧 Common Pitfalls & Troubleshooting Guide

During the development and provisioning of this infrastructure, several real-world issues were encountered and resolved. Below is a log of the troubleshooting steps:

### Issue 1: `500 Internal Server Error` on Initial Deployment
* **Symptom**: Accessing the External ALB DNS returned a 500 error from Nginx.
* **Root Cause**: The Internal ALB was attempting to forward traffic to the App Tier on port `4000` (the Node.js backend port). However, the `app_tier_sg` (Security Group) was misconfigured to only accept Ingress traffic on port `80` from the Internal ALB. 
* **Resolution**: Updated the `app_tier_sg` in Terraform to explicitly allow Ingress on port `4000` from the `int_alb_sg`.

### Issue 2: Incorrect Application Provisioning (User Data Mix-up)
* **Symptom**: The backend API was unreachable.
* **Root Cause**: The bash script intended for the Web Tier (installing Nginx and building React) was mistakenly attached to the App Tier Launch Template. Consequently, the Node.js/PM2 backend was never started.
* **Resolution**: Separated the deployment scripts. Created distinct `user_data` payloads for `web_lt` (Frontend setup) and `app_lt` (Backend setup).

### Issue 3: Stale Instances Causing Lingering 500 Errors
* **Symptom**: After fixing the Terraform code (Security Groups and Launch Templates) and running `terraform apply`, the 500 Error persisted.
* **Root Cause**: Terraform successfully updated the Launch Templates, but the Auto Scaling Group does not immediately terminate existing healthy (but incorrectly configured) EC2 instances. Nginx was still routing traffic to the old, broken instances.
* **Resolution**: Manually terminated the stale App Tier EC2 instances via the AWS Console. This triggered the ASG to automatically spin up new instances using the corrected Launch Template, resolving the error.

### Issue 4: RDS Creation Failure (`FreeTierRestrictionError`)
* **Symptom**: Terraform failed to provision the RDS instance, returning an API error regarding Free Tier limits.
* **Root Cause**: The project required `multi_az = true` and `backup_retention_period = 7`. AWS Free Tier/Academy accounts have strict limits on storage overhead for high-availability backups.
* **Resolution**: Reduced the `backup_retention_period` from 7 days to 1 day to comply with account restrictions while maintaining the Multi-AZ deployment.

---

## 🛠️ Technology Stack
* **Infrastructure Provisioning**: Terraform (IaC)
* **Cloud Provider**: Amazon Web Services (AWS)
* **Compute & Networking**: VPC, EC2, Auto Scaling Groups, Application Load Balancers, NAT Gateway
* **Database & Caching**: RDS (MySQL), ElastiCache (Redis)
* **Application**: React, Node.js, Nginx, PM2

## ⚙️ How to Deploy

1. **Clone the repository**:
   ```bash
   git clone [https://github.com/YourUsername/retailedge-aws-three-tier.git](https://github.com/YourUsername/retailedge-aws-three-tier.git)
   cd retailedge-aws-three-tier/terraform
