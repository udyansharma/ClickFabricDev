#!/bin/bash
#
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#

# This script is designed to be run in the org3cli container as the
# first step of the EYFN tutorial.  It creates and submits a
# configuration transaction to add org3 to the network previously
# setup in the BYFN tutorial.
#
ORDERER_CA=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem

CHANNEL_NAME="$1"
DELAY="$2"
LANGUAGE="$3"
TIMEOUT="$4"
VERBOSE="$5"
MAINTAINER_ORG="$6"
MAINTAINER_ORG_PEER="$7"
ORG_NAME="$8"

: ${CHANNEL_NAME:="mychannel"}
: ${DELAY:="3"}
: ${LANGUAGE:="golang"}
: ${TIMEOUT:="10"}
: ${VERBOSE:="false"}
: ${MAINTAINER_ORG:="org1"}
: ${MAINTAINER_ORG_PEER:="peer0"}
LANGUAGE=`echo "$LANGUAGE" | tr [:upper:] [:lower:]`
COUNTER=1
MAX_RETRY=5

CC_SRC_PATH="github.com/chaincode/chaincode_example02/go/"
if [ "$LANGUAGE" = "node" ]; then
	CC_SRC_PATH="/opt/gopath/src/github.com/chaincode/chaincode_example02/node/"
fi

# fetchChannelConfig <channel_id> <output_json>
# Writes the current channel config for a given channel to a JSON file
fetchChannelConfig() {
  CHANNEL=$1
  OUTPUT=$2

  CORE_PEER_LOCALMSPID="OrdererMSP"
  CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/orderers/orderer.example.com/msp/tlscacerts/tlsca.example.com-cert.pem
  CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/ordererOrganizations/example.com/users/Admin@example.com/msp

  echo "Fetching the most recent configuration block for the channel"
  if [ -z "$CORE_PEER_TLS_ENABLED" -o "$CORE_PEER_TLS_ENABLED" = "false" ]; then
    set -x
    peer channel fetch config config_block.pb -o orderer.example.com:7050 -c $CHANNEL --cafile $ORDERER_CA
    set +x
  else
    set -x
    peer channel fetch config config_block.pb -o orderer.example.com:7050 -c $CHANNEL --tls --cafile $ORDERER_CA
    set +x
  fi

  echo "Decoding config block to JSON and isolating config to ${OUTPUT}"
  set -x
  configtxlator proto_decode --input config_block.pb --type common.Block | jq .data.data[0].payload.data.config >"${OUTPUT}"
  set +x
}

# createConfigUpdate <channel_id> <original_config.json> <modified_config.json> <output.pb>
# Takes an original and modified config, and produces the config update tx
# which transitions between the two
createConfigUpdate() {
  CHANNEL=$1
  ORIGINAL=$2
  MODIFIED=$3
  OUTPUT=$4
  echo "In createConfigUpdate got channel name as ${CHANNEL}"

  set -x
  configtxlator proto_encode --input "${ORIGINAL}" --type common.Config >original_config.pb
  configtxlator proto_encode --input "${MODIFIED}" --type common.Config >modified_config.pb
  configtxlator compute_update --channel_id "${CHANNEL}" --original original_config.pb --updated modified_config.pb >config_update.pb
  configtxlator proto_decode --input config_update.pb --type common.ConfigUpdate >config_update.json
  echo '{"payload":{"header":{"channel_header":{"channel_id":"'$CHANNEL'", "type":2}},"data":{"config_update":'$(cat config_update.json)'}}}' | jq . >config_update_in_envelope.json
  configtxlator proto_encode --input config_update_in_envelope.json --type common.Envelope >"${OUTPUT}"
  set +x
}

# signConfigtxAsPeerOrg <org> <configtx.pb>
# Set the peerOrg admin of an org and signing the config update
signConfigtxAsPeerOrg() {
  ORG=$1
  PEERORG=$2
  TX=$3
  # ----- CHANGE PORT NUMBER OF MAINTAINER ORG HERE 
  CORE_PEER_LOCALMSPID="${MAINTAINER_ORG}MSP"
  CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${MAINTAINER_ORG}.example.com/peers/${MAINTAINER_ORG_PEER}.${MAINTAINER_ORG}.example.com/tls/ca.crt
  CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/${MAINTAINER_ORG}.example.com/users/Admin@${MAINTAINER_ORG}.example.com/msp
  CORE_PEER_ADDRESS=${MAINTAINER_ORG_PEER}.${MAINTAINER_ORG}.example.com:7051

  set -x
  peer channel signconfigtx -f "${TX}"
  set +x
}
selectSecond(){
    CORE_PEER_LOCALMSPID="Org2MSP"
    CORE_PEER_TLS_ROOTCERT_FILE=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/peers/peer0.org2.example.com/tls/ca.crt
    CORE_PEER_MSPCONFIGPATH=/opt/gopath/src/github.com/hyperledger/fabric/peer/crypto/peerOrganizations/org2.example.com/users/Admin@org2.example.com/msp
    CORE_PEER_ADDRESS=peer0.org2.example.com:9051
}

echo
echo "========= Creating config transaction to add org3 to network =========== "
echo

echo "Installing jq"
apt-get -y update && apt-get -y install jq


# yq is a command line yaml/xml processor
echo "Installing yq"
# This will only work if your Linux Distribution supports snap packages
# snap install yq

# This is to install yq using apt packages.
# Uncomment the following lines

# sudo add-apt-repository ppa:rmescandon/yq
# sudo apt update
# sudo apt install yq -y

# Fetch the config for the channel, writing it to config.json
fetchChannelConfig ${CHANNEL_NAME} config.json

# Modify the configuration to append the orgnew
set -x
#----------CODE MIGHT GO WRONG HERE------------
MSP_NAME="${ORG_NAME}MSP"
jq -s '.[0] * {"channel_group":{"groups":{"Application":{"groups": {"Org3MSP":.[1]}}}}}' config.json ./channel-artifacts/orgnew.json > modified_config.json
sed $OPTS "s/Org3MSP/${MSP_NAME}/g" modified_config.json

set +x

# Compute a config update, based on the differences between config.json and modified_config.json, write it as a transaction to new_org_update_in_envelope.pb
createConfigUpdate ${CHANNEL_NAME} config.json modified_config.json new_org_update_in_envelope.pb


echo
echo "========= Config transaction to add org3 to network created ===== "
echo

echo "Signing config transaction"
echo
signConfigtxAsPeerOrg $MAINTAINER_ORG $MAINTAINER_ORG_PEER new_org_update_in_envelope.pb

echo
echo "========= Submitting transaction from a different peer (peer0.org2) which also signs it ========= "
echo

selectSecond

peer channel update -f "${TX}" -c ${CHANNEL_NAME} -o orderer.example.com:7050 --tls --cafile $ORDERER_CA
set -x
# Orderer Name to Be changed here
set +x

echo
echo "========= Config transaction to add New Organization to network submitted! =========== "
echo

exit 0
