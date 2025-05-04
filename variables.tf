variable "region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

variable "s3_bucket_name" {
  description = "Globally unique S3 bucket name for Jenkins backups"
  type        = string
}

variable "my_ip" {
  description = "Your public IP address in CIDR notation (e.g., 1.2.3.4/32)"
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for Jenkins server"
  type        = string
  default     = "t2.medium"
}

variable "jenkins_volume_size" {
  description = "Size of the EBS volume for Jenkins in GB"
  type        = number
  default     = 30
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "subnet_cidr" {
  description = "CIDR block for the subnet"
  type        = string
  default     = "10.0.1.0/24"
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {
    Name        = "jenkins-server"
    Environment = "dev"
    Terraform   = "true"
  }
}
