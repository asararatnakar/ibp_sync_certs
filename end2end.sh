#!/bin/bash

if [ -z $1 -o -z $2 ]; then
  echo "===== ERROR:  Must pass the API Key and ORG name ===="
  exit 1
fi

# ./create_network.sh $1 $2
echo 
echo 
echo "Generate admin certs , upload to the peers and Sync them to the channel"
./sync_admin_certs.sh