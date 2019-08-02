#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This script extends the Hyperledger Fabric By Your First Network by
# adding a third organization to the network previously setup in the
# BYFN tutorial.
#

# prepending $PWD/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired

export PATH=${PWD}/../bin:${PWD}:$PATH
export FABRIC_CFG_PATH=${PWD}
export VERBOSE=false

# Print the usage message
function printHelp () {
  echo "Usage: "
  echo "  add.sh up [-o <orgname>] [-c <channel name>] [-t <timeout>] [-d <delay>] [-f <docker-compose-file>] [-s <dbtype>] [-l <language>] [-i <imagetag>] [-a <adminorg>] [-p <adminpeer>] [-v <verbose>]"
  echo "  add.sh -h|--help (print this message)"
  echo "    <mode> - 'up'"
  echo "      - 'up' - bring up the network with docker-compose up"
  echo "    -o <orgname> - name of the organization to be added [this is a required field]"
  echo "    -c <channel name> - channel name to use (defaults to \"mychannel\")"
  echo "    -t <timeout> - CLI timeout duration in seconds (defaults to 10)"
  echo "    -d <delay> - delay duration in seconds (defaults to 3)"
  echo "    -f <docker-compose-file> - specify which docker-compose file use (defaults to docker-compose-cli.yaml)"
  echo "    -s <dbtype> - the database backend to use: goleveldb (default) or couchdb"
  echo "    -l <language> - the chaincode language: golang (default) or node"
  echo "    -i <imagetag> - the tag to be used to launch the network (defaults to \"latest\")"
  echo "    -a <adminorg> - the network admin organization (defaults to \"org1\")"
  echo "    -p <adminpeer> - the peer of the network admin organization (defaults to \"peer0\")"
  echo "    -v <verbose> - verbose mode"
  echo
  echo "	add.sh up -c mychannel -s couchdb"
  echo "	add.sh up -l node"
  echo
  echo "Taking all defaults:"
  echo "	add.sh generate"
  echo "	add.sh "
}

# Generate the needed certificates, the genesis block and start the network.
function networkUp () {
  generateCerts
  generateChannelArtifacts
  createConfigTx

  CURRENT_DIR=$PWD
  cd "$CURRENT_DIR"
  cp docker-compose-template-new-org.yaml docker-compose-${ORG_NAME}.yaml
  sed $OPTS "s/Org3/${ORG_NAME}/g" docker-compose-${ORG_NAME}.yaml

  # If MacOSX, remove the temporary backup of the docker-compose file
  if [ "$ARCH" == "Darwin" ]; then
    rm docker-compose-${ORG_NAME}.yamlt
  fi

  # start org3 peers
  if [ "${IF_COUCHDB}" == "couchdb" ]; then
      IMAGE_TAG=${IMAGETAG} docker-compose -f docker-compose-$ORG_NAME.yaml -f $COMPOSE_FILE_COUCH_NEW_ORG up -d 2>&1
  else
      IMAGE_TAG=$IMAGETAG docker-compose -f docker-compose-$ORG_NAME.yaml up -d 2>&1
  fi
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to start New Organization network i.e. related containers"
    exit 1
  fi
  echo
  echo "###############################################################"
  echo "############### New Organization's peers joining the network ##################"
  echo "###############################################################"
  docker exec ${ORG_NAME}cli newOrgscripts/step2orgnew.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE ${ORG_NAME}
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! New Organization peers coudn't join the network"
    exit 1
  fi
  echo 
  echo "###############################################################"
  echo "##### Upgrading chaincode to have New Organization peers on the network #####"
  echo "###############################################################"

  cp newOrgscripts/step3orgnew.sh scripts/step3orgnew.sh
  cp newOrgscripts/utils.sh scripts/newutils.sh 
  
  docker exec cli scripts/step3orgnew.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to add New Organization peers on network. Could not upgrade Chaincode"
    exit 1
  fi
}

# Use the CLI container to create the configuration transaction needed to add
# New Organization's to the network
function createConfigTx () {
  echo
  echo "###############################################################"
  echo "####### Generate and submit config tx to add New-Org #############"
  echo "###############################################################"
  cp newOrgscripts/step1orgnew.sh scripts/step1orgnew.sh
  
  docker exec cli scripts/step1orgnew.sh $CHANNEL_NAME $CLI_DELAY $LANGUAGE $CLI_TIMEOUT $VERBOSE $MAINTAINER_ORG $MAINTAINER_ORG_PEER $ORG_NAME
  if [ $? -ne 0 ]; then
    echo "ERROR !!!! Unable to create config tx"
    exit 1
  fi
}

# We use the cryptogen tool to generate the cryptographic material
# (x509 certs) for the New Organization's.  After we run the tool, the certs will
# be parked in the BYFN folder titled ``crypto-config``.

# Generates New Organization's certs using cryptogen tool
function generateCerts (){
  which cryptogen
  if [ "$?" -ne 0 ]; then
    echo "cryptogen tool not found. exiting"
    exit 1
  fi
  echo
  echo "###############################################################"
  echo "##### Generate New Organization's certificates using cryptogen tool #########"
  echo "###############################################################"

  #Code might go wrong here in cd command. Don't know if
  CURRENT_DIR=$PWD
  
  (cd $DIR_NAME
   set -x
   cryptogen generate --config=./crypto-config.yaml
   res=$?
   set +x
   if [ $res -ne 0 ]; then
     echo "Failed to generate certificates..."
     exit 1
   fi
  )
  echo
  cd $CURRENT_DIR
}

# Generate channel configuration transaction
function generateChannelArtifacts() {
  which configtxgen
  if [ "$?" -ne 0 ]; then
    echo "configtxgen tool not found. Exiting"
    exit 1
  fi
  echo "##########################################################"
  echo "#########  Generating New Organization's config material ###############"
  echo "##########################################################"
  (cd $DIR_NAME
   export FABRIC_CFG_PATH=$PWD
   set -x
   configtxgen -printOrg ${ORG_NAME}MSP > ../channel-artifacts/orgnew.json
   res=$?
   set +x
   if [ $res -ne 0 ]; then
     echo "Failed to generate New Organization's config material..."
     exit 1
   fi
  )
  cp -r crypto-config/ordererOrganizations ${DIR_NAME}/crypto-config/
  echo
}

function createNewConfigFiles() {
  CURRENT_DIR=$PWD
  DIR_NAME=${ORG_NAME}-artifacts

  # Making artifacts directory 
  mkdir -p -- "$DIR_NAME"

  # Copying template artifact files into the directory
  cp configtx-template.yaml $DIR_NAME/configtx.yaml
  cp crypto-config-template.yaml $DIR_NAME/crypto-config.yaml

  cd $DIR_NAME

  # Copying from template files 
  # cp configtx-template.yaml configtx.yaml
  # cp crypto-config-template.yaml crypto-config.yaml

  # Replacing New Organization's name with the template organization name
  sed $OPTS "s/Org3/${ORG_NAME}/g" configtx.yaml

  sed $OPTS "s/Org3/${ORG_NAME}/g" crypto-config.yaml
  sed $OPTS "s/NUMOFPEERS/${NUM_OF_PEERS}/g" crypto-config.yaml



  # If MacOSX, remove the temporary backup of the configtx and crypto-config file
  if [ "$ARCH" == "Darwin" ]; then
    rm configtx.yamlt
    rm crypto-config.yamlt
  fi

  cd $CURRENT_DIR

}

# If BYFN wasn't run abort
if [ ! -d crypto-config ]; then
  echo
  echo "ERROR: Please, run this script in an already created network. Coudn't find existing crypto-config folder"
  echo
  exit 1
fi


# Obtain the OS and Architecture string that will be used to select the correct
# native binaries for your platform
OS_ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
# timeout duration - the duration the CLI should wait for a response from
# another container before giving up
CLI_TIMEOUT=10
#default for delay
CLI_DELAY=3
# channel name defaults to "mychannel"
CHANNEL_NAME="mychannel"
# use this as the default docker-compose yaml definition
COMPOSE_FILE=docker-compose-cli.yaml
#
COMPOSE_FILE_COUCH=docker-compose-couch.yaml
# use this as the default docker-compose yaml definition
COMPOSE_FILE_NEW_ORG=docker-compose-template-new-org.yaml
#
COMPOSE_FILE_COUCH_NEW_ORG=docker-compose-couch-new-org.yaml
# kafka and zookeeper compose file
COMPOSE_FILE_KAFKA=docker-compose-kafka.yaml
# use golang as the default language for chaincode
LANGUAGE=golang
# default image tag
IMAGETAG="latest"
#default network admin org
#MAINTAINER_ORG="org1"
#default network admin org peer
MAINTAINER_ORG_PEER="peer0"
#default value
ORG_NAME="ORGNEW"
# default number of peers to be added
NUM_OF_PEERS=2

# sed on MacOSX does not support -i flag with a null extension. We will use
# 't' for our back-up's extension and delete it at the end of the function
ARCH=$(uname -s | grep Darwin)
if [ "$ARCH" == "Darwin" ]; then
  OPTS="-it"
else
  OPTS="-i"
fi

while getopts "h?o:c:t:d:f:s:l:i:a:p:n:v" opt; do
  case "$opt" in
    h|\?)
      printHelp
      exit 0
    ;;
    c)  CHANNEL_NAME=$OPTARG;  
    ;;
    t)  CLI_TIMEOUT=$OPTARG;  
    ;;
    d)  CLI_DELAY=$OPTARG; 
    ;;
    f)  COMPOSE_FILE=$OPTARG;  
    ;;
    s)  IF_COUCHDB=$OPTARG;  
    ;;
    l)  LANGUAGE=$OPTARG;  
    ;;
    i)  IMAGETAG=$OPTARG;  
    ;;
    a)  MAINTAINER_ORG=$OPTARG;
    ;;
    p)  MAINTAINER_ORG_PEER=$OPTARG;
    ;;
    o)  ORG_NAME=$OPTARG; 
    ;;
    n)  NUM_OF_PEERS=$OPTARG; 
    ;;
    v)  VERBOSE=true; 
    ;;
    esac
done


# Announce what was requested

  if [ "${IF_COUCHDB}" == "couchdb" ]; then
        echo
        echo "Beginning to add New Organization to the Network with channel '${CHANNEL_NAME}' and CLI timeout of '${CLI_TIMEOUT}' seconds and CLI delay of '${CLI_DELAY}' seconds and using database '${IF_COUCHDB}'"
  else
        echo "Beginning to add New Organization to the Network with channel '${CHANNEL_NAME}' and CLI timeout of '${CLI_TIMEOUT}' seconds and CLI delay of '${CLI_DELAY}' seconds"
  fi
if [ ! "${MAINTAINER_ORG}" ]; then
            echo $MAINTAINER_ORG
            echo "Network admin organization not provided. Kindly provide it as an argument using the -a flag. Use -h for help."
            echo "Exiting....."
            exit 1
fi

echo "REQUESTED NUM_OF_PEERS IS ${NUM_OF_PEERS}"
createNewConfigFiles
# Create the network using docker compose
networkUp

