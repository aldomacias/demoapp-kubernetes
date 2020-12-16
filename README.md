# demoapp-kubernetes
Demo app to deploy in a kubernetes with DAP already integrated. 

Uses cases included are

1. Deploy app without secrets protection
2. Deploy app with secrets stored in DAP and delivered with k8s-authenticator as init container and summon 
3. Deploy app with secrets stored in DAP and connection delivered with secretless
4. Deploy app with secrets stored in DAP and delivered with Secrets Provider for Kubernetes as a Job in the application namespace
