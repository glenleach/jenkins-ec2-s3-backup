output "jenkins_public_ip" {
  description = "Public IP address of the Jenkins server"
  value       = aws_instance.jenkins_ec2.public_ip
}

output "jenkins_s3_bucket" {
  description = "S3 bucket used for Jenkins backups"
  value       = aws_s3_bucket.jenkins_backup.bucket
}

output "ssh_command" {
  description = "SSH command to connect to your Jenkins EC2 instance"
  value       = "ssh -i ${path.module}/jenkins-key.pem ec2-user@${aws_instance.jenkins_ec2.public_ip}"
}

output "jenkins_url" {
  description = "URL to access the Jenkins web interface"
  value       = "http://${aws_instance.jenkins_ec2.public_ip}:8080"
}

output "tls_private_key" {
  value     = tls_private_key.jenkins.private_key_pem
  sensitive = true
}
