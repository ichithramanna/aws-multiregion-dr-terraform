pipeline {
    agent any

    parameters {
        booleanParam(name: 'DOCKER_PUSH', defaultValue: true,  description: 'Build and push Docker image to ECR')
        booleanParam(name: 'APPLY',       defaultValue: false, description: 'Run terraform apply after plan (requires manual approval)')
    }

    environment {
        AWS_REGION_PRIMARY = 'us-east-1'
        ECR_REGISTRY       = '002506421910.dkr.ecr.us-east-1.amazonaws.com'
        ECR_REPO           = 'backend-app'
        IMAGE_TAG          = "${env.BUILD_NUMBER}"
        TF_IN_AUTOMATION   = 'true'
    }

    options {
        timestamps()
        timeout(time: 45, unit: 'MINUTES')
        disableConcurrentBuilds()
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {

        // ─────────────────────────────────────────────
        // STAGE 1 — Checkout
        // ─────────────────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                echo "Branch: ${env.BRANCH_NAME} | Build: #${env.BUILD_NUMBER}"
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 2 — Terraform Validate
        // -backend=false skips S3 — only checks syntax
        // and formatting, no live infra needed
        // ─────────────────────────────────────────────
        stage('Terraform Validate') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                                  credentialsId: 'aws-credentials']]) {
                    sh '''
                        echo "==> Init (no backend)..."
                        terraform init -backend=false -reconfigure -input=false

                        echo "==> Validate..."
                        terraform validate

                        echo "==> Format check..."
                        terraform fmt -check -recursive
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 3 — Terraform Plan
        // Connects to S3 backend to read current state
        // One plan covers PRIMARY (us-east-1) + DR
        // (us-west-2) via aliased providers in one repo
        // ─────────────────────────────────────────────
        stage('Terraform Plan') {
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                                  credentialsId: 'aws-credentials'],
                                 string(credentialsId: 'db-password', variable: 'TF_VAR_db_password')]) {
                    sh '''
                        echo "==> Init with S3 backend..."
                        terraform init -reconfigure -input=false

                        echo "==> Planning PRIMARY + DR regions..."
                        terraform plan \
                            -var="aws_region=${AWS_REGION_PRIMARY}" \
                            -out=tfplan \
                            -no-color \
                            -input=false
                    '''
                }
            }
            post {
                always {
                    archiveArtifacts artifacts: 'tfplan', allowEmptyArchive: true
                }
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 4 — Docker Build & Push to ECR
        // Skipped if DOCKER_PUSH param = false
        // Only runs on main branch
        // ─────────────────────────────────────────────
        stage('Docker Build & Push to ECR') {
            when {
                allOf {
                    branch 'main'
                    expression { return params.DOCKER_PUSH == true }
                }
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                                  credentialsId: 'aws-credentials']]) {
                    sh '''
                        echo "==> Authenticating with ECR..."
                        aws ecr get-login-password --region ${AWS_REGION_PRIMARY} \
                            | docker login --username AWS --password-stdin ${ECR_REGISTRY}

                        echo "==> Building image from ./backend/Dockerfile..."
                        docker build -t ${ECR_REPO}:${IMAGE_TAG} ./backend

                        echo "==> Tagging..."
                        docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
                        docker tag ${ECR_REPO}:${IMAGE_TAG} ${ECR_REGISTRY}/${ECR_REPO}:latest

                        echo "==> Pushing to ECR..."
                        docker push ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}
                        docker push ${ECR_REGISTRY}/${ECR_REPO}:latest

                        echo "==> Done: ${ECR_REGISTRY}/${ECR_REPO}:${IMAGE_TAG}"
                    '''
                }
            }
        }

        // ─────────────────────────────────────────────
        // STAGE 5 — Terraform Apply (manual approval)
        // Only runs if APPLY param = true on main branch
        // Pipeline pauses and waits for human to confirm
        // ─────────────────────────────────────────────
        stage('Terraform Apply') {
            when {
                allOf {
                    branch 'main'
                    expression { return params.APPLY == true }
                }
            }
            input {
                message "Apply Terraform to PRIMARY (us-east-1) + DR (us-west-2)?"
                ok "Yes, Apply Now"
            }
            steps {
                withCredentials([[$class: 'AmazonWebServicesCredentialsBinding',
                                  credentialsId: 'aws-credentials'],
                                 string(credentialsId: 'db-password', variable: 'TF_VAR_db_password')]) {
                    sh '''
                        echo "==> Applying Terraform plan..."
                        terraform apply -auto-approve tfplan
                        echo "==> Infrastructure deployed successfully."
                    '''
                }
            }
        }

    }

    post {
        success {
            echo "Pipeline passed — Build #${env.BUILD_NUMBER} on ${env.BRANCH_NAME}"
        }
        failure {
            echo "Pipeline FAILED — Build #${env.BUILD_NUMBER}. Check logs above."
        }
        always {
            cleanWs()
        }
    }
}
