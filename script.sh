#!/bin/bash

kubectl -n glitchtip get secret glitchtip -o jsonpath='{.data.SECRET_KEY}' | base64 -d \
  | az keyvault secret set --vault-name kv-myproject-prod \
      --name glitchtip--secret-key --file /dev/stdin