pipeline {
    agent any

    environment {
        // Target webroot directory on this same server
        DEPLOY_DIR = '/var/www/berryshot' 
    }

    triggers {
        // Triggers the pipeline when a push or pull request merge occurs on GitHub
        githubPush()
    }

    options {
        timeout(time: 15, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '10'))
    }

    stages {
        stage('Checkout Source') {
            steps {
                checkout scm
            }
        }

        stage('Build macOS Binaries (Optional)') {
            steps {
                script {
                    // Check if Swift compiler is available on the active agent
                    def hasSwift = sh(script: 'command -v swift >/dev/null 2>&1 && echo "true" || echo "false"', returnStdout: true).trim()
                    
                    if (hasSwift == 'true') {
                        echo "\u2705 Swift compiler found. Compiling macOS app and packaging DMG/Zip..."
                        sh 'chmod +x build_app.sh'
                        sh './build_app.sh'
                    } else {
                        echo "\u26A0\uFE0F Swift compiler not found on this Jenkins agent. Skipping binary compilation."
                        echo "Deploying with pre-existing binaries inside landingpage/assets/ directory."
                    }
                }
            }
        }

        stage('Verify Landing Page Code') {
            steps {
                echo "Validating landing page HTML components..."
                sh 'test -f landingpage/index.html'
                sh 'test -f landingpage/docs.html'
                sh 'test -d landingpage/assets'
                echo "\u2705 HTML files and assets directory verified."
            }
        }

        stage('Deploy locally to Webroot') {
            when {
                anyOf {
                    branch 'main'
                    expression { env.GIT_BRANCH == 'main' }
                    expression { env.GIT_BRANCH == 'origin/main' }
                    expression { env.GIT_BRANCH == 'refs/heads/main' }
                }
            }
            steps {
                echo "Deploying landing page directly to local directory: ${env.DEPLOY_DIR}..."
                
                // Diagnostic checks to help user troubleshoot environment/permissions
                sh '''
                    echo "--- Build Environment Diagnostics ---"
                    echo "Running on host: $(hostname)"
                    echo "Running as user: $(whoami)"
                    echo "Current directory: $(pwd)"
                    echo "Checking /var/www write permissions..."
                    if [ -w "/var/www" ] || [ -w "/var/www/berryshot" ]; then
                        echo "Write permission check: SUCCESS"
                    else
                        echo "Write permission check: FAILED (Permission Denied)"
                    fi
                '''
                
                // Synchronize only the contents of the landingpage/ folder.
                sh """
                    mkdir -p ${DEPLOY_DIR}
                    rsync -av --delete \
                    --exclude='.DS_Store' \
                    --exclude='.git*' \
                    landingpage/ ${DEPLOY_DIR}/
                """
                
                echo "\u2705 Local deployment completed successfully to ${env.DEPLOY_DIR}."
            }
        }
    }

    post {
        success {
            echo "Jenkins Build #${BUILD_NUMBER} succeeded! Deployment complete."
        }
        failure {
            echo "Jenkins Build #${BUILD_NUMBER} failed. Please review console logs."
        }
    }
}
