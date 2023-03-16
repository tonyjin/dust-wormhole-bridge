#!/bin/bash

### Are the wormhole programs already built? If so, bail out.
ls wormhole.so token_bridge.so > /dev/null 2>&1
if [ $? -eq 0 ]; then
  exit 0
fi

### Clone the repo
echo "fetching Solana programs from wormhole repo"
git clone \
  --depth 1 \
  --branch main \
  --filter=blob:none \
  --sparse \
  https://github.com/wormhole-foundation/wormhole \
  tmp-wormhole > /dev/null 2>&1
cd tmp-wormhole

### Checkout solana directory and move that to this program directory
git sparse-checkout set solana > /dev/null 2>&1

### Build program artifacts
echo "building"
cd solana
DOCKER_BUILDKIT=1 docker build \
  -f Dockerfile \
  --build-arg BRIDGE_ADDRESS=3u8hJUVTA4jH1wYAyUur7FFZVQ8H635K3tSHHF4ssjQ5 \
  -o artifacts .

### Move wormhole artifact
cd ../..
mv tmp-wormhole/solana/artifacts/bridge.so wormhole.so
rm -rf tmp-wormhole

### Done
exit 0
