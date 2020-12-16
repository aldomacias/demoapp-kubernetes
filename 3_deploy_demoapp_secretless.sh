#!/usr/bin/env bash
set -euo pipefail

ECR_BASE_URI="XXXXX.dkr.ecr.us-east-1.amazonaws.com"
new_pwd=$(openssl rand -hex 12)
CONJUR_ADMIN_PASSWORD='XXXXXXXX'
DAP_HOSTNAME='ecXXXXX.compute-1.amazonaws.com'
#aws ecr get-login --no-include-email --region us-east-1 | sh


echo "creating namespace..."
kubectl create namespace demoapp-secretless
kubectl config set-context $(kubectl config current-context) --namespace="demoapp-secretless" > /dev/null
# allow follower to get information in this namespace
kubectl create -f ./kubernetes/demoapp-conjur-authenticator-role-binding-secretless.yml 

# certs to enable ssl on postgres
kubectl --namespace demoapp-secretless \
      create secret generic \
      demoapp-backend-certs \
      --from-file=server.crt=./etc/ca.pem \
      --from-file=server.key=./etc/ca-key.pem

echo "storing cert as configmap..."
follower_pod_name=$(kubectl get pods -n conjur-dev --selector role=follower --no-headers | awk '{ print $1 }' | head -1)
ssl_cert=$(kubectl -n conjur-dev exec $follower_pod_name -- cat /opt/conjur/etc/ssl/conjur.pem)
kubectl create configmap server-certificate --from-file=ssl-certificate=<(echo "$ssl_cert")


echo "###Loading DAP Policies and variables ##### INFORMATION SECURITY ##### ----"
#Authenticate
api_key=$(curl -sk --user admin:$CONJUR_ADMIN_PASSWORD https://$DAP_HOSTNAME/authn/demo/login)
auth_result=$(curl -sk https://$DAP_HOSTNAME/authn/demo/admin/authenticate -d "$api_key")
DAP_TOKEN=$(echo -n $auth_result | base64 | tr -d '\r\n')
DAP_AUTH_HEADER="Authorization: Token token=\"$DAP_TOKEN\""

#LoadPolicy 
POST_URL="https://$DAP_HOSTNAME/policies/demo/policy/root"
curl -k -H "$DAP_AUTH_HEADER" -d "$(< ./demoapp-secretless/demoapp-secretless-policy.yaml)" $POST_URL
#Load Variables
POST_URL="https://$DAP_HOSTNAME/secrets/demo/variable/demoapp-secretless-db/username"
curl -sk -H "$DAP_AUTH_HEADER" --data "demoapp-user" $POST_URL
POST_URL="https://$DAP_HOSTNAME/secrets/demo/variable/demoapp-secretless-db/host"
curl -sk -H "$DAP_AUTH_HEADER" --data "demoapp-secretless-backend.demoapp-secretless.svc.cluster.local" $POST_URL
POST_URL="https://$DAP_HOSTNAME/secrets/demo/variable/demoapp-secretless-db/port"
curl -sk -H "$DAP_AUTH_HEADER" --data "5432" $POST_URL
POST_URL="https://$DAP_HOSTNAME/secrets/demo/variable/demoapp-secretless-db/password"
curl -sk -H "$DAP_AUTH_HEADER" --data "$new_pwd" $POST_URL

echo "Deploying postgres..."
sed "s#{{ TEST_APP_PG_DOCKER_IMAGE }}#$ECR_BASE_URI/demoapp-pg#g" ./demoapp-secretless/postgres.yaml |
      sed "s#{{ DEMOAPP_DB_PASSWORD }}#$new_pwd#g" |
      kubectl create -f -

kubectl create configmap secretless-config --from-file=./demoapp-secretless/secretless.yaml

echo "Deploying demoapp with secretless..."
kubectl create -f demoapp-secretless/demoapp-secretless.yaml

if [ ]; then
  kubectl describe service demoapp-secretless | grep 'LoadBalancer Ingress'
  app_url=$(kubectl describe service demoapp-secretless | grep 'LoadBalancer Ingress' | awk '{ print $3 }'):8080
  curl  -d '{"name": "Mr. Secretless"}' -H "Content-Type: application/json" $app_url/pet
  echo $(curl $app_url/pets) | jq .
  echo $(curl $app_url/vulnerable) | jq .
fi
