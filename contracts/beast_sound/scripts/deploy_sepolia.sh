#!/bin/sh
# Declare and deploy BeastMidiProvider on Starknet Sepolia, then smoke-test get_sound on a genesis
# Warlock. Run from anywhere; it builds contracts/beast_sound with its own scarb (2.20.1).
#
#   sh contracts/beast_sound/scripts/deploy_sepolia.sh [beasts_v3_nft_address]
#
# Uses the sncast account profile `beast-sound-sepolia` in ~/.starknet_accounts (no key is read or
# printed here; sncast signs). The account needs STRK for fees: the script stops before sending
# anything while its balance is zero. The NFT defaults to the Beasts V3 test deployment of
# 31 Jul 2026; pass loothero's current Sepolia address if it has moved.
set -e
RPC=${RPC:-https://api.cartridge.gg/x/starknet/sepolia}
NFT=${1:-0x01dac77837c6751777d917051a6e405967c5c75f46df5ab7c635e52819634bfd}
ACCOUNT=beast-sound-sepolia
ACCOUNTS_FILE=$HOME/.starknet_accounts/starknet_open_zeppelin_accounts.json
SNCAST=${SNCAST:-$HOME/.asdf/installs/starknet-foundry/0.64.0/bin/sncast}
STRK=0x04718f5a0fc34cc1af16a1cdee98ffb20c31f5cd61d6ab07201858f4287c938d
cd "$(dirname "$0")/.."

rpc() { curl -s "$RPC" -H 'content-type: application/json' -d "$1"; }
ADDRESS=$(python3 -c "import json; print(json.load(open('$ACCOUNTS_FILE'))['alpha-sepolia']['$ACCOUNT']['address'])")
BALANCE=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"starknet_call\",\"params\":{\"request\":{\"contract_address\":\"$STRK\",\"entry_point_selector\":\"0x2e4263afad30923c891518314c3c95dbe830a16874e8abc5777a9a20b54c76e\",\"calldata\":[\"$ADDRESS\"]},\"block_id\":\"latest\"}}" | python3 -c "import json,sys; r=json.load(sys.stdin).get('result'); print(int(r[0],16) if r else 0)")
echo "account $ADDRESS: $(python3 -c "print(f'{$BALANCE / 1e18:.4f}')") STRK"
if [ "$BALANCE" = "0" ]; then
  echo "Fund $ADDRESS with Sepolia STRK (any Starknet Sepolia faucet), then run this again."
  exit 1
fi

SN="$SNCAST --account $ACCOUNT --accounts-file $ACCOUNTS_FILE"
DEPLOYED=$(rpc "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"starknet_getClassHashAt\",\"params\":{\"block_id\":\"latest\",\"contract_address\":\"$ADDRESS\"}}" | grep -c '"result"' || true)
if [ "$DEPLOYED" = "0" ]; then
  echo "deploying the account"
  $SN account deploy --name $ACCOUNT --url "$RPC"
fi

echo "declaring BeastMidiProvider"
DECLARE=$($SN declare --contract-name BeastMidiProvider --url "$RPC" 2>&1 || true)
echo "$DECLARE"
CLASS=$(echo "$DECLARE" | grep -oE "(class_hash|Class Hash): *0x[0-9a-f]+" | grep -oE "0x[0-9a-f]+" | head -1)
if [ -z "$CLASS" ]; then
  # already declared: sncast reports the hash in the error
  CLASS=$(echo "$DECLARE" | grep -oE "0x[0-9a-f]{50,}" | head -1)
fi
[ -n "$CLASS" ] || { echo "no class hash"; exit 1; }
echo "class $CLASS"

echo "deploying against the Beasts NFT $NFT"
DEPLOY=$($SN deploy --class-hash "$CLASS" --constructor-calldata "$NFT" --url "$RPC")
echo "$DEPLOY"
PROVIDER=$(echo "$DEPLOY" | grep -oE "(contract_address|Contract Address): *0x[0-9a-f]+" | grep -oE "0x[0-9a-f]+" | head -1)
echo "provider $PROVIDER"

# smoke test: the genesis Warlock 0x7006400010000000000000000001 (low, high)
echo "get_sound(genesis Warlock):"
$SNCAST call --contract-address "$PROVIDER" --function get_sound --calldata 0x7006400010000000000000000001 0x0 --url "$RPC" | head -c 400
echo
