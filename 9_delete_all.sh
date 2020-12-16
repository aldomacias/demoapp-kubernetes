#!/usr/bin/env bash
set -x

kubectl delete  namespace demoapp
kubectl delete  namespace demoapp-summon
kubectl delete  namespace demoapp-secretless
kubectl delete  namespace demoapp-secrets-provider