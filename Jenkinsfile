pipeline {
  agent any

  stages {
    stage('Build Artifact - Maven') {
      steps {
        sh "mvn clean package -DskipTests=true"
        archive 'target/*.jar'
      }
    }

    stage('Unit Tests - JUnit and Jacoco') {
      steps {
        sh "mvn test"
      }
      post {
        always {
          junit 'target/surefire-reports/*.xml'
          jacoco execPattern: 'target/jacoco.exec'
        }
      }
    }
    stage('Mutation Tests - PIT') {
      steps {
        sh "mvn org.pitest:pitest-maven:mutationCoverage"
      }
      post {
        always {
          pitmutation mutationStatsFile: '**/target/pit-reports/**/mutations.xml'
        }
      }
    }
    stage('SonarQube - SAST') {
      steps {
        sh "mvn sonar:sonar \
  -Dsonar.projectKey=numeric-application \
  -Dsonar.host.url=http://devsecops-cloud.westus2.cloudapp.azure.com:9000 \
  -Dsonar.login=20aede12aaab7056b837efbef5eebd3285c627bb"
      }
    }
    stage('Docker Build and Push') {
      steps {
          withDockerRegistry([credentialsId: "docker-hub", url: ""]) {
              sh "printenv"
              sh "docker build -t merlinxor/numeric-app:${GIT_COMMIT} ."
              sh "docker push merlinxor/numeric-app:${GIT_COMMIT}"
          }
      }
    }
    stage('Kubernetes Deployment - DEV') {
      steps {
          withKubeConfig([credentialsId: 'kubeconfig']) {
              sh "sed -i 's#replace#merlinxor/numeric-app:${GIT_COMMIT}#g' k8s_deployment_service.yaml"
              sh "kubectl apply -f k8s_deployment_service.yaml"
          }
      }
    }
  }
}
