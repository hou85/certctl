#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="certctl"
HOSTNAME="certctl.tail44be45.ts.net"

# Namespace
kubectl create namespace "$NAMESPACE" --dry-run=client -o yaml | kubectl apply -f -

# Secret Postgres
if ! kubectl get secret -n "$NAMESPACE" postgres-secret >/dev/null 2>&1; then
  kubectl create secret generic postgres-secret \
    --namespace "$NAMESPACE" \
    --from-literal=password="$(openssl rand -base64 32)"
  echo "✓ postgres-secret créé"
else
  echo "⊙ postgres-secret existe déjà, skip"
fi

# Secret certctl (API key + bootstrap token)
if ! kubectl get secret -n "$NAMESPACE" certctl-secret >/dev/null 2>&1; then
  kubectl create secret generic certctl-secret \
    --namespace "$NAMESPACE" \
    --from-literal=auth-secret="$(openssl rand -base64 32)" \
    --from-literal=bootstrap-token="$(openssl rand -base64 32)"
  echo "✓ certctl-secret créé"
else
  echo "⊙ certctl-secret existe déjà, skip"
fi

# Secret TLS auto-signé (RSA 2048 pour compatibilité OpenSSL/LibreSSL)
if ! kubectl get secret -n "$NAMESPACE" certctl-tls >/dev/null 2>&1; then
  TLS_DIR=$(mktemp -d)
  trap "rm -rf $TLS_DIR" EXIT

  openssl req -x509 -newkey rsa:2048 \
    -keyout "$TLS_DIR/tls.key" -out "$TLS_DIR/tls.crt" \
    -days 3650 -nodes \
    -subj "/CN=$HOSTNAME" \
    -addext "subjectAltName=DNS:certctl,DNS:certctl.certctl.svc,DNS:certctl.certctl.svc.cluster.local,DNS:$HOSTNAME" \
    -addext "extendedKeyUsage=serverAuth"

  kubectl create secret tls certctl-tls \
    --namespace "$NAMESPACE" \
    --cert="$TLS_DIR/tls.crt" \
    --key="$TLS_DIR/tls.key"
  echo "✓ certctl-tls créé"
else
  echo "⊙ certctl-tls existe déjà, skip"
fi

echo ""
echo "Bootstrap terminé. Récupère ton api-key :"
echo "  kubectl get secret -n $NAMESPACE certctl-secret -o jsonpath='{.data.auth-secret}' | base64 -d"