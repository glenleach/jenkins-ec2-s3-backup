pipeline {
    agent any

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }
        stage('Install Prerequisites') {
            steps {
                sh '''
                    apt-get update
                    apt-get install -y wget unzip curl
                '''
            }
        }
        stage('Install or Update Terraform') {
            steps {
                sh '''
                    chmod +x scripts/install_or_update_terraform.sh
                    scripts/install_or_update_terraform.sh
                '''
            }
        }
        // Optional: Add Terraform commands here
        // stage('Terraform Init') {
        //     steps {
        //         sh 'terraform init'
        //     }
        // }
        // stage('Terraform Plan') {
        //     steps {
        //         sh 'terraform plan'
        //     }
        // }
    }
}
