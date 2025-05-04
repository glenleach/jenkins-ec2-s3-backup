# Jenkins on EC2 with S3 Backup

## Overview

This project provides a **cost-effective, on-demand Jenkins server** solution for DevOps teams. By leveraging AWS EC2 and S3, you can spin up a Jenkins server with the latest configuration and job data, run your CI/CD workloads, and then destroy all resources except your S3 backup. This approach minimizes AWS costs by only running Jenkins when you need it, while always preserving your Jenkins state and configuration in S3.

---

## Purpose

- **Save DevOps money:** Only pay for Jenkins EC2 resources when you need them.
- **On-demand Jenkins:** Quickly provision a Jenkins server with the latest jobs, plugins, and configuration.
- **Persistent backups:** All Jenkins data is backed up to S3, so you can destroy and recreate your Jenkins server at any time.
- **Automated restore:** On launch, the server automatically restores from the latest S3 backup if available.
- **Automated backup:** Jenkins data is backed up to S3 daily and after 30 minutes of initial setup.

---


---

## Features

- Automated Jenkins installation and configuration on Amazon Linux 2 EC2.
- Automated restore of Jenkins home from S3 if a backup exists.
- Automated update of Jenkins public URL after restore.
- Automated daily and initial (30 min after boot) backup to S3.
- Easy manual backup trigger.
- Safe to destroy all AWS resources except the S3 bucket—restore will always bring back your latest Jenkins state.

---

## Usage Instructions

### 1. **Clone the Repository**

```sh
git clone https://github.com/your-org/jenkins-on-ec2-s3-backup.git
cd jenkins-on-ec2-s3-backup
```

### 2. **Configure Your Variables**

Create a `terraform.tfvars` file in the project root with your settings:

```hcl
region         = "us-east-1"                         # AWS region (e.g., N. Virginia)
s3_bucket_name = "jenkins-backup-bucket-20240505"    # Globally unique S3 bucket name
my_ip          = "203.0.113.42/32"                   # Your IP address for SSH/Jenkins access
instance_type  = "t2.medium                    # EC2 instance type for Jenkins
```

### 3. **Initialize and Apply Terraform**

```sh
terraform init
terraform apply
```

- This will provision all AWS resources and start Jenkins.
- The Jenkins server will be accessible at `http://<public-ip>:8080`.

---

## How to Get the Initial Jenkins Admin Password

- **On a fresh install (no backup):**
  1. SSH into your EC2 instance:
     ```sh
     ssh -i ./jenkins-key.pem ec2-user@<public-ip>
     ```
  2. View the password in the user data log:
     ```sh
     sudo grep "Initial admin password" -A 1 /var/log/user-data.log
     ```
     or directly from the container:
     ```sh
     sudo docker exec jenkins cat /var/jenkins_home/secrets/initialAdminPassword
     ```

- **On restore from backup:**  
  If you restored a Jenkins home with setup completed, log in with your existing admin credentials. The initial password file may not exist.

---

## How to Run a Manual Backup

To trigger a manual backup of Jenkins data to S3 at any time:

1. **SSH into your EC2 instance:**
   ```sh
   ssh -i ./jenkins-key.pem ec2-user@<public-ip>
   ```

2. **Run the backup script:**
   ```sh
   sudo /usr/local/bin/jenkins_backup.sh
   ```

- This will sync the entire Jenkins home directory to your S3 bucket.
- The backup includes all jobs, plugins, configurations, and build history.
- You should see progress output as files are uploaded to S3.

---

## Cost-Saving Workflow

1. **Run Jenkins when needed:**  
   Use `terraform apply` to provision Jenkins with the latest backup.
2. **Destroy resources when not needed:**  
   Use `terraform destroy` (after removing the S3 bucket from state with `terraform state rm aws_s3_bucket.jenkins_backup`) to delete all AWS resources except your S3 backup.
3. **Restore anytime:**  
   Use `terraform apply` again to bring Jenkins back with all jobs, plugins, and configuration restored from S3.

---

## Example `terraform.tfvars`

```hcl
region         = "ap-southeast-1"                         # AWS region (e.g., Singapore)
s3_bucket_name = "jenkins-backup-bucket-unique-20240505"  # Globally unique S3 bucket name
my_ip          = "198.51.100.77/32"                       # Your IP address for SSH/Jenkins access
instance_type  = "t3.large"                               # EC2 instance type for Jenkins
```

---

## Local Development & Setup

1. **Clone the repository:**
   ```sh
   git clone https://github.com/your-org/jenkins-on-ec2-s3-backup.git
   cd jenkins-on-ec2-s3-backup
   ```

2. **Install prerequisites:**
   - [Terraform](https://www.terraform.io/downloads.html)
   - [AWS CLI](https://aws.amazon.com/cli/)
   - AWS credentials configured (`aws configure`)

3. **Edit `terraform.tfvars` with your settings.**

4. **Initialize and apply:**
   ```sh
   terraform init
   terraform apply
   ```

5. **Access Jenkins:**
   - Find the public IP in Terraform outputs or AWS Console.
   - Open `http://<public-ip>:8080` in your browser.

---

## Destroying and Restoring Jenkins

- To **destroy all resources except your S3 backup**:
  ```sh
  terraform state rm aws_s3_bucket.jenkins_backup
  terraform destroy
  ```
- To **restore Jenkins**:
  ```sh
  terraform apply
  ```
  Jenkins will be restored from the latest S3 backup.

---

## Troubleshooting

- **Check logs:**  
  SSH into your instance and view `/var/log/user-data.log` for provisioning output and errors.
- **Check Jenkins container:**  
  ```sh
  sudo docker ps -a
  sudo docker logs jenkins
  ```
- **Check backup script:**  
  ```sh
  sudo cat /usr/local/bin/jenkins_backup.sh
  ```

---

## License

MIT License

---

## Author

Glen Leach

---

**Enjoy cost-effective, on-demand Jenkins with persistent S3 backup!**

---

## Resources Created

This project provisions the following resources:

### **AWS Resources**

- **EC2 Instance**
  - Amazon Linux 2 instance running Jenkins in Docker
  - Configured with a persistent EBS volume for Jenkins home
  - Associated with an IAM instance profile for S3 access

- **S3 Bucket**
  - Stores Jenkins home backups for persistent state across instance lifecycles

- **IAM Role and Instance Profile**
  - Grants the EC2 instance permissions to access the S3 bucket

- **IAM Role Policy Attachment**
  - Attaches the AmazonS3FullAccess policy to the Jenkins EC2 role

- **Key Pair**
  - SSH key pair for secure access to the EC2 instance

- **Security Group**
  - Allows inbound SSH (port 22) and Jenkins web (port 8080) access from your IP
  - Allows all outbound traffic

- **Security Group Rules**
  - Ingress rules for SSH and Jenkins
  - Egress rule for all outbound traffic

### **Local Resources**

- **Terraform State Files**
  - `terraform.tfstate` and backups (ignored by git)

- **Private Key File**
  - `jenkins-key.pem` (ignored by git)

- **User Data Script**
  - `user_data.sh.tpl` (used to bootstrap Jenkins and configure backup/restore)

- **Backup Script**
  - `/usr/local/bin/jenkins_backup.sh` (created on the EC2 instance)

- **Log Files**
  - `/var/log/user-data.log` (on the EC2 instance)
  - `/var/log/jenkins_backup.log` (on the EC2 instance)

- **Terraform Configuration Files**
  - `.tf` files describing all infrastructure

- **Documentation**
  - `README.md` and example variable files

**All resources are managed by Terraform and can be destroyed (except the S3 bucket, if you remove it from state) to minimize costs.**
