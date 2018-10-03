#!/bin/bash

if [ -z $1 -o -z $2 ]; then
  echo "===== ERROR:  Must pass the API Key and ORG name ===="
  exit 1
fi

rm -rf ./creds
mkdir -p creds

KEY=$1
ORG=$2
BLUEMIX_API_KEY=$KEY
BLUEMIX_ORG=$ORG
BLUEMIX_SPACE=dev
BLUEMIX_API_ENDPOINT=https://api.stage1.ng.bluemix.net

INSTANCE_NAME=Blockchain-$RANDOM
SERVICE_NAME=ibm-blockchain-5-staging
SERVICE_PLAN=ibm-blockchain-plan-v1-ga1-starter-staging
SERVICE_KEY=service_key

## disable update check
bx config --check-version=false

# login to ibm cloud
bx api ${BLUEMIX_API_ENDPOINT}

# bx login
bx login --apikey ${BLUEMIX_API_KEY}

# bx target -o ${BLUEMIX_ORG} -s ${BLUEMIX_SPACE}
bx target --cf-api ${BLUEMIX_API_ENDPOINT} -o ${BLUEMIX_ORG} -s ${BLUEMIX_SPACE}

# create a new blockchain starter
bx service create ${SERVICE_NAME} ${SERVICE_PLAN} ${INSTANCE_NAME}

echo ${INSTANCE_NAME} >> creds/instance_name

bx service key-create ${INSTANCE_NAME} ${SERVICE_KEY}
bx service key-show ${INSTANCE_NAME} ${SERVICE_KEY} | tail -n +5 > creds/network.json

echo "... All Done! Network got created"
echo
echo
echo "Delete the instance with the following commands"
echo "bx cf delete-service-key -f ${INSTANCE_NAME} ${SERVICE_KEY}"
echo "bx cf delete-service -f ${INSTANCE_NAME}"
