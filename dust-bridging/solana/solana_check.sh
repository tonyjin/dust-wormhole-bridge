#!/bin/bash

solana_version=`solana --version 2>/dev/null | sed -n 's/^solana-cli \([0-9\.]*\) .*$/\1/p'`
max_version="1.15"
if [[ -z $solana_version ]]; then
  echo "install solana-cli version 1.14.14 first"
  exit 1
fi

if [[ "$(printf '%s\n' "$solana_version" "$max_version" | sort -V | head -n1)" == "$max_version" ]]; then
  echo "Solana version too new - please downgrade to 1.14.14"
  exit 1
fi
