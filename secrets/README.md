# Sealed Secrets

## Fetch public certificate

```shell
kubeseal --fetch-cert > pub.crt
```

## Fetch private certificate

```shell
kubectl get secret -n kube-system -l sealedsecrets.bitnami.com/sealed-secrets-key -o yaml >main.key 
```

## Generate secrets

From repository root

```shell
./secrets/generate.sh -a dex -k client-id -v 555555555 -e ops -c ops
```
