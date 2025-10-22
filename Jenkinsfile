pipeline {
    agent any

    environment {
        FLUTTER_HOME = "C:\\src\\flutter"
        PATH = "${FLUTTER_HOME}\\bin;${env.PATH}"
    }

    stages {
        stage('Checkout Code') {
            steps {
                git branch: 'main', url: 'https://github.com/star0tex/Go_India_frontend.git'
            }
        }

        stage('Install Dependencies') {
            steps {
                bat 'flutter pub get'
            }
        }

        stage('Run Tests') {
            steps {
                bat 'flutter test'
            }
        }

        stage('Build Release AAB') {
            steps {
                bat 'flutter build appbundle --release'
            }
        }

        stage('Archive Build') {
            steps {
                archiveArtifacts artifacts: 'build\\app\\outputs\\bundle\\release\\*.aab', fingerprint: true
            }
        }
    }
}
