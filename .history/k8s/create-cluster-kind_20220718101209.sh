#!/usr/bin/env bash

# https://vaneyckt.io/posts/safer_bash_scripts_with_set_euxo_pipefail/
set -Eeuo pipefail

echo -e '\n[BOOSTRAPING CLUSTER]\n'
kind create cluster --config=cluster-kind.yaml

echo -e '\n[Ingress]\n'
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml

echo "⏳ Waiting for Ingress to be ready..."
kubectl wait --namespace ingress-nginx --for=condition=complete job --selector=app.kubernetes.io/component=admission-webhook --timeout=120s
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=120s

echo "✅ Done!"
