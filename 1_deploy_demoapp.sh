#!/usr/bin/env bash
set -euo pipefail

new_pwd="InsecurePwd"
ECR_BASE_URI="XXXXX.dkr.ecr.us-east-1.amazonaws.com"
#aws ecr get-login --no-include-email --region us-east-1 | sh

kubectl create namespace demoapp

kubectl config set-context $(kubectl config current-context) --namespace="demoapp" > /dev/null

kubectl --namespace demoapp \
      create secret generic \
      demoapp-backend-certs \
      --from-file=server.crt=./etc/ca.pem \
      --from-file=server.key=./etc/ca-key.pem

#### Build and push postgress for demo app insecure####
docker build -t demoapp-pg -f pg/Dockerfile .
docker tag demoapp-pg $ECR_BASE_URI/demoapp-pg
docker push $ECR_BASE_URI/demoapp-pg

#### Build and push demoapp-insecure####
#docker build -t demoapp-insecure -f demoapp/Dockerfile .
#docker tag demoapp-insecure $ECR_BASE_URI/demoapp-insecure 
#docker push $ECR_BASE_URI/demoapp-insecure 

sed "s#{{ TEST_APP_PG_DOCKER_IMAGE }}#$ECR_BASE_URI/demoapp-pg#g" ./demoapp/postgres.yaml |
      sed "s#{{ DEMOAPP_DB_PASSWORD }}#$new_pwd#g" |
      kubectl create -f -

sed "s#{{ DEMOAPP_DB_PASSWORD }}#$new_pwd#g" ./demoapp/demoapp-insecure.yaml |
      kubectl create -f -


if [ ]; then
  kubectl describe service demoapp-insecure | grep 'LoadBalancer Ingress'
  app_url=$(kubectl describe service demoapp-insecure | grep 'LoadBalancer Ingress' | awk '{ print $3 }'):8080
  curl  -d '{"name": "Mr. insecure"}' -H "Content-Type: application/json" $app_url/pet
  echo $(curl $app_url/pets) | jq .
  echo $(curl $app_url/vulnerable) | jq .
fi