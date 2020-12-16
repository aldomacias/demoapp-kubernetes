#!/usr/bin/env bash
set -euo pipefail

ECR_BASE_URI="XXXXX.dkr.ecr.us-east-1.amazonaws.com"
new_pwd=$(openssl rand -hex 12)
CONJUR_ADMIN_PASSWORD='XXXXXXXX'
DAP_HOSTNAME='ecXXXXX.compute-1.amazonaws.com'
#aws ecr get-login --no-include-email --region us-east-1 | sh

#create namespace
kubectl create namespace demoapp-summon
kubectl config set-context $(kubectl config current-context) --namespace="demoapp-summon" > /dev/null
# allow follower to get information in this namespace
kubectl create -f ./kubernetes/demoapp-conjur-authenticator-role-binding-summon.yml 

# certs to enable ssl on postgres
kubectl --namespace demoapp-summon \
      create secret generic \
      demoapp-backend-certs \
      --from-file=server.crt=./etc/ca.pem \
      --from-file=server.key=./etc/ca-key.pem

# store cert as configmap
follower_pod_name=$(kubectl get pods -n conjur-dev --selector role=follower --no-headers | awk '{ print $1 }' | head -1)
ssl_cert=$(kubectl -n conjur-dev exec $follower_pod_name -- cat /opt/conjur/etc/ssl/conjur.pem)
kubectl create configmap server-certificate --from-file=ssl-certificate=<(echo "$ssl_cert")

###Load DAP Policies and variables ##### INFORMATION SECURITY ##### ----
#Authenticate
api_key=$(curl -sk --user admin:$CONJUR_ADMIN_PASSWORD https://$DAP_HOSTNAME/authn/demo/login)
auth_result=$(curl -sk https://$DAP_HOSTNAME/authn/demo/admin/authenticate -d "$api_key")
DAP_TOKEN=$(echo -n $auth_result | base64 | tr -d '\r\n')
DAP_AUTH_HEADER="Authorization: Token token=\"$DAP_TOKEN\""

#LoadPolicy
POST_URL="https://$DAP_HOSTNAME/policies/demo/policy/root"
curl -k -H "$DAP_AUTH_HEADER" -d "$(< ./demoapp-summon/demoapp-summon-policy.yaml)" $POST_URL
#Load Variables
POST_URL="https://$DAP_HOSTNAME/secrets/demo/variable/demoapp-summon-db/username"
curl -sk -H "$DAP_AUTH_HEADER" --data "demoapp-user" $POST_URL
POST_URL="https://$DAP_HOSTNAME/secrets/demo/variable/demoapp-summon-db/url"
curl -sk -H "$DAP_AUTH_HEADER" --data "postgresql://demoapp-summon-backend.demoapp-summon.svc.cluster.local:5432/demoapp" $POST_URL
POST_URL="https://$DAP_HOSTNAME/secrets/demo/variable/demoapp-summon-db/password"
curl -sk -H "$DAP_AUTH_HEADER" --data "$new_pwd" $POST_URL

# Deploy postgres
sed "s#{{ TEST_APP_PG_DOCKER_IMAGE }}#$ECR_BASE_URI/demoapp-pg#g" ./demoapp-summon/postgres.yaml |
      sed "s#{{ DEMOAPP_DB_PASSWORD }}#$new_pwd#g" |
      kubectl create -f -

#### Build and push demoapp-summon####
docker build -t demoapp-summon -f demoapp-summon/Dockerfile ./demoapp-summon/
docker tag demoapp-summon $ECR_BASE_URI/demoapp-summon 
docker push $ECR_BASE_URI/demoapp-summon 

sed "s#{{ DEMO_APP_IMAGE }}#$ECR_BASE_URI/demoapp-summon#g" ./demoapp-summon/demoapp-summon.yaml |
      kubectl create -f -

if [ ]; then
  kubectl describe service demoapp-summon | grep 'LoadBalancer Ingress'
  app_url=$(kubectl describe service demoapp-summon | grep 'LoadBalancer Ingress' | awk '{ print $3 }'):8080
  curl  -d '{"name": "Mr. summon"}' -H "Content-Type: application/json" $app_url/pet
  echo $(curl $app_url/pets) | jq .
  echo $(curl $app_url/vulnerable) | jq .
fi