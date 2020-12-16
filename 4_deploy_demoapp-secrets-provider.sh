#!/usr/bin/env bash
set -euo pipefail

ECR_BASE_URI="XXXXX.dkr.ecr.us-east-1.amazonaws.com"
new_pwd=$(openssl rand -hex 12)
CONJUR_ADMIN_PASSWORD='XXXXXXXX'
DAP_HOSTNAME='ecXXXXX.compute-1.amazonaws.com'
#aws ecr get-login --no-include-email --region us-east-1 | sh
kubectl create namespace demoapp-secrets-provider
kubectl config set-context $(kubectl config current-context) --namespace="demoapp-secrets-provider" > /dev/null

kubectl --namespace demoapp-secrets-provider \
      create secret generic \
      demoapp-backend-certs \
      --from-file=server.crt=./etc/ca.pem \
      --from-file=server.key=./etc/ca-key.pem

###Load DAP Policies and variables ##### INFORMATION SECURITY ##### ----
#Authenticate
api_key=$(curl -sk --user admin:$CONJUR_ADMIN_PASSWORD https://$DAP_HOSTNAME/authn/demo/login)
auth_result=$(curl -sk https://$DAP_HOSTNAME/authn/demo/admin/authenticate -d "$api_key")
DAP_TOKEN=$(echo -n $auth_result | base64 | tr -d '\r\n')
DAP_AUTH_HEADER="Authorization: Token token=\"$DAP_TOKEN\""

#LoadPolicy
POST_URL="https://$DAP_HOSTNAME/policies/demo/policy/root"
curl -k -H "$DAP_AUTH_HEADER" -d "$(< ./demoapp-secrets-provider/demoapp-secrets-provider-policy.yaml)" $POST_URL
#Load Variables
POST_URL="https://$DAP_HOSTNAME/secrets/demo/variable/demoapp-secrets-provider-db/username"
curl -sk -H "$DAP_AUTH_HEADER" --data "demoapp-user" $POST_URL
POST_URL="https://$DAP_HOSTNAME/secrets/demo/variable/demoapp-secrets-provider-db/password"
curl -sk -H "$DAP_AUTH_HEADER" --data "$new_pwd" $POST_URL

# retrieve cert from follower
follower_pod_name=$(kubectl get pods -n conjur-dev --selector role=follower --no-headers | awk '{ print $1 }' | head -1)
ssl_cert=$(kubectl -n conjur-dev exec $follower_pod_name -- cat /opt/conjur/etc/ssl/conjur.pem)

# Installing secrets-provider
helm repo add cyberark https://cyberark.github.io/helm-charts

helm install \
secrets-provider cyberark/secrets-provider \
-f demoapp-secrets-provider/custom-values.yaml \
--set-file environment.conjur.sslCertificate.value=<(echo "$ssl_cert")

# Deploy postgres
sed "s#{{ TEST_APP_PG_DOCKER_IMAGE }}#$ECR_BASE_URI/demoapp-pg#g" ./demoapp-secrets-provider/postgres.yaml |
      sed "s#{{ DEMOAPP_DB_PASSWORD }}#$new_pwd#g" |
      kubectl create -f -

# Creating secrets in kubernetes
kubectl apply -f demoapp-secrets-provider/secret.yaml
# Deploying Application
kubectl create -f demoapp-secrets-provider/demoapp-secrets-provider.yaml
      



if [ ]; then
  kubectl describe service demoapp-secrets-provider | grep 'LoadBalancer Ingress'
  app_url=$(kubectl describe service demoapp-secrets-provider | grep 'LoadBalancer Ingress' | awk '{ print $3 }'):8080
  curl  -d '{"name": "Mr. secrets-provider"}' -H "Content-Type: application/json" $app_url/pet
  echo $(curl $app_url/pets) | jq .
  echo $(curl $app_url/vulnerable) | jq .
fi