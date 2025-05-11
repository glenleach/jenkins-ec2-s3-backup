
pipeline {
    agent {
        docker {
            image 'jenkins/jenkins:lts'
            args '-u root'
        }
    }
    environment {
        GITHUB_TOKEN = credentials('github-token-credentials') // Uses your specified Jenkins credential ID
    }
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
                    apt-get install -y wget unzip curl jq file
                '''
            }
        }
        stage('Install or Update Terraform') {
            steps {
                sh '''
                    chmod +x scripts/install_or_update_terraform.sh
                    GITHUB_TOKEN="$GITHUB_TOKEN" scripts/install_or_update_terraform.sh
                '''
            }
        }
    }
}