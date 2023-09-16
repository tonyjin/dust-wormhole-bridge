#/bin/bash

pgrep anvil > /dev/null
if [ $? -eq 0 ]; then
    echo "anvil already running"
    exit 1;
fi

# ethereum goerli testnet
anvil \
    -m "myth like bonus scare over problem client lizard pioneer submit female collect" \
    --port 8546 \
    --fork-url $ETH_FORK_RPC > anvil_eth.log &

# avalanche fuji testnet
anvil \
    -m "myth like bonus scare over problem client lizard pioneer submit female collect" \
    --port 8547 \
    --fork-url $POLYGON_FORK_RPC > anvil_polygon.log &

sleep 2

## first key from mnemonic above
export PRIVATE_KEY=$WALLET_PRIVATE_KEY

# mkdir -p cache
# cp -v foundry.toml cache/foundry.toml
# cp -v foundry-test.toml foundry.toml

# echo "overriding foundry.toml"
# mv -v cache/foundry.toml foundry.toml

## run tests here
npx ts-mocha -t 1000000 ts/test/*.ts

# nuke
pkill anvil