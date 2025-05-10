# Deploying Jenkins on AWS with Terraform: Lessons Learned

Deploying Jenkins on AWS using Terraform is a rewarding way to automate infrastructure provisioning and CI/CD setup. In this post, I’ll walk through my project, highlight the challenges I faced, and share solutions and insights that might help you on your own journey.

---

## Project Overview

The goal was to provision a Jenkins server on AWS using Terraform, with the following requirements:

- **Region**: AWS London (`eu-west-2`)
- **S3 Bucket**: For Jenkins backups, with a globally unique name
- **Security**: Restrict SSH and HTTP access to my IP
- **Instance Type**: Use a `t2.medium` EC2 instance for Jenkins

All configuration was managed via Terraform, with variables defined in `terraform.tfvars`:

```hcl
region          = "eu-west-2"
s3_bucket_name  = "jenkins-backup-bucket-123456789"
my_ip           = "my public_ip address/32"
instance_type   = "t2.medium"
```

---

## Architecture Diagram

Below is a high-level architecture of the deployed infrastructure:

```mermaid
graph TD
    A[User Workstation] -- SSH/HTTP --> B[Jenkins EC2 Instance]
    B -- Backup --> C[S3 Bucket (jenkins-backup-bucket-123456789)]
    D[AWS Security Group] -. Restricts Access .-> B
    E[Terraform] -- Provisions --> B
    E -- Provisions --> C
    E -- Provisions --> D
    subgraph AWS eu-west-2
        B
        C
        D
    end
```

---

## Key Issues & Solutions

### 1. **S3 Bucket Name Uniqueness**

**Issue:**  
AWS S3 bucket names must be globally unique. My initial bucket name was already taken, causing Terraform to fail.

**Solution:**  
I appended a unique suffix (date of birth) to the bucket name:  
`jenkins-backup-bucket-123456789` This ensures that each deployment has a unique bucket name, avoiding conflicts and allowing for easy management of backups.

**Tip:**  
Use a naming convention that guarantees uniqueness, such as including a timestamp or a UUID.

---

### 2. **Security Group IP Restrictions**

**Issue:**  
I wanted to restrict access to the Jenkins server to my own IP, but initially left the security group open to all (`0.0.0.0/0`), which is insecure.

**Solution:**  
I parameterized my IP in `terraform.tfvars` and referenced it in the security group rules:

```hcl
ingress {
  from_port   = 22
  to_port     = 22
  protocol    = "tcp"
  cidr_blocks = [var.my_ip]
}
```

**Tip:**  
Always restrict access to known IPs, especially for SSH and web interfaces.

---

### 3. **Terraform State Management**

**Issue:**  
Running Terraform from different machines or losing the local state file can cause drift or resource duplication.

**Solution:**  
I configured remote state storage in the S3 bucket, ensuring consistent state management:

```hcl
terraform {
  backend "s3" {
    bucket = var.s3_bucket_name
    key    = "terraform.tfstate"
    region = var.region
  }
}
```

**Tip:**  
Always use remote state for team projects or when working across multiple environments.

---

### 4. **Instance Type Selection**

**Issue:**  
The default `t2.micro` instance was underpowered for Jenkins, leading to slow performance.

**Solution:**  
I switched to `t2.medium` in `terraform.tfvars`, which provided sufficient resources for Jenkins and plugins.

---

### 5. **IAM Permissions**

**Issue:**  
Jenkins needed access to the S3 bucket for backups, but the EC2 instance profile lacked the necessary permissions.

**Solution:**  
I created an IAM role and policy granting the EC2 instance access to the S3 bucket, and attached it to the instance.

---

### 6. **Restoring Jenkins from Backup: Slow Performance and URL Mismatch**

**Issue:**  
After restoring Jenkins from a backup, I noticed that although the Jenkins server was running, it was extremely slow and unresponsive. Oddly, when I deployed a fresh Jenkins instance (without restoring from backup), everything worked perfectly.

**How I Troubleshooted:**

1. **Checked EC2 Server Status:**  
   I first verified the EC2 instance's health and resource usage (CPU, memory, disk) via the AWS console and SSH. Everything looked normal.

2. **Compared Fresh vs. Restored Jenkins:**  
   A fresh Jenkins install was fast and responsive, so the issue was clearly related to the restored configuration.

3. **Investigated Jenkins Logs:**  
   I checked Jenkins logs (`/var/log/jenkins/jenkins.log`) for errors or warnings, but found nothing conclusive.

4. **Checked Jenkins URL Configuration:**  
   I realized that the Jenkins setup wizard (before backup) had registered the server with a different URL than the current public IP address. Jenkins stores this information in its configuration XML files.

5. **Solution – Update Jenkins URL in Config:**  
   I modified my Terraform template's shell script (`tpl` file) to automatically update the relevant XML configuration file (such as `jenkins.model.JenkinsLocationConfiguration.xml`) with the current public IP address of the EC2 instance during provisioning. This ensured that Jenkins would use the correct URL after restore, resolving the slowness and unresponsiveness.

**Tip:**  
When restoring Jenkins or similar applications from backup, always check for hardcoded URLs or hostnames in the configuration files and update them to match the new environment. Automating this step in your provisioning scripts can save a lot of troubleshooting time!

---

### 7. **Simple and Effective Backups: Jenkins Home Folder to S3**

**Observation:**  
I found that the easiest and most reliable way to back up Jenkins was simply to copy the entire Jenkins home folder (`/var/jenkins_home`) directly to S3. This approach captured all jobs, plugins, and configuration in one place, making restores straightforward.

**Why Not Use tar Files or Tar Archives?**Files for Backup?**  
While tar Files or Tar Archives files are great for managing infrastructure variables, they aren't suitable for storing Jenkins data or configuration. Similarly, creating a tar archive adds an extra step and complexity. By backing up the Jenkins home folder directly to S3, I ensured that all Jenkins data was preserved in its native structure, making restoration and migration much easier and more reliable.

**Implementation:**  
I set up a simple cron job on the Jenkins server that runs daily to sync the Jenkins home directory to my S3 bucket:

```bash
aws s3 sync /var/jenkins_home s3://<bucket-name>/jenkins-home/ --delete
```

This command ensures that the S3 bucket always has an up-to-date copy of the Jenkins configuration, including all jobs, plugins, and user settings.

**Tip:**  
For Jenkins, focus on backing up the home directory (`/var/jenkins_home` by default) to S3 or another remote storage solution. This makes disaster recovery and migration much easier, and avoids the need for extra packaging or complex backup logic.

---

## Final Thoughts

Automating Jenkins deployment with Terraform on AWS is a great way to learn about infrastructure as code, cloud security, and best practices. The main takeaways from my experience:

- Always use unique names for global resources.
- Lock down your infrastructure with strict security group rules.
- Use remote state for reliability.
- Choose the right instance size for your workload.
- Grant only the permissions your services need.
- When restoring from backup, always update configuration files to reflect the current environment.

---

**Happy automating!**

---

## S3 Bucket Security: How Are My Jenkins Backups Protected?

A critical part of this project is ensuring that Jenkins backups stored in S3 are secure and not accessible to unauthorized users. Here's how security is achieved in this setup:

### 1. **Default S3 Bucket Privacy**

- **S3 buckets are private by default.** Only the AWS account and explicitly authorized IAM users or roles can access the contents.
- **Public access is blocked** unless you intentionally add a bucket policy or object ACL to allow it.

### 2. **IAM Role-Based Access**

- The Jenkins EC2 instance is assigned an **IAM role** with permissions to access only the specific S3 bucket used for backups.
- **No public access** is granted; only the Jenkins server (via its IAM role) can read from and write to the backup bucket.
- The backup and restore scripts use the AWS CLI, which leverages the instance's IAM role for secure, credential-free access.

### 3. **No Sensitive Data in tfvars or Public Storage**

- Only Jenkins configuration and job data are stored in the S3 bucket.
- Sensitive infrastructure variables (like those in `tfvars`) are not stored in the bucket.

### 4. **Block Public Access Setting**

- AWS S3 provides a "Block all public access" setting, which is enabled by default for new buckets.
- This setting prevents accidental exposure of your backups, even if a public policy or ACL is mistakenly added.

### 5. **How This Protects Your Data**

- **Knowing the bucket name or URL is not enough** to access the contents. Unauthorized users will receive an "Access Denied" error.
- Only the Jenkins EC2 instance (and any other explicitly authorized IAM users/roles) can access the backups.
- No public bucket policy or object ACL is present, so the data is not exposed to the internet.

### 6. **Best Practices Checklist**

- [x] **Block all public access** is enabled on the S3 bucket.
- [x] **IAM role** is used for Jenkins EC2 instance access.
- [x] **No public bucket policy** or object ACLs.
- [x] **No sensitive credentials** or tfvars stored in the bucket.

**In summary:**  
Your Jenkins backups are secure because access is strictly limited to your Jenkins EC2 instance via IAM, and public access is blocked by default. Always double-check your S3 bucket permissions in the AWS Console to ensure these best practices remain in place.
