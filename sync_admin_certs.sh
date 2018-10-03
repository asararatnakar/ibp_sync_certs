#!/bin/bash

if [ ! -f creds/network.json ]; then
	printf "\n ERROR : Make sure to include the (Network Credentials) network.json under cred dir\n\n"
	exit 1 
fi
export PATH=$PATH:$PWD/bin/
PROG="[helio-apis]"
rm -rf bin cacert.pem

function log() {
	printf "${PROG}  ${1}\n" 
	# | tee -a run.log
}

####################
# Helper Functions #
####################
get_pem() {
	awk '{printf "%s\\n", $0}' creds/org"$1"admin/msp/signcerts/cert.pem
}

ORG1_NAME=$(jq -r "[.[] | .key][0]" creds/network.json)
if [ "$ORG1_NAME" =  "PeerOrg1" ]; then
	IS_ENTERPRISE=true
	export CA_VERSION=1.1.0
	export CHANNEL_NAME=${1:-channel1}
else 
	export CA_VERSION=1.2.0
	export CHANNEL_NAME=defaultchannel
fi

API_ENDPOINT=$(jq -r .\"${ORG1_NAME}\".url creds/network.json)
NETWORK_ID=$(jq -r .\"${ORG1_NAME}\".network_id creds/network.json)

ORG1_API_KEY=$(jq -r .\"${ORG1_NAME}\".key creds/network.json)
ORG1_API_SECRET=$(jq -r .\"${ORG1_NAME}\".secret creds/network.json)


## TODO: Do we need to Download the connection profiles ?
echo "Downloading the Connection profile for org1"
curl -s -X GET --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${ORG1_API_KEY}:${ORG1_API_SECRET} ${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/connection_profile | jq . >& creds/org1.json

# ORG1_NAME=$(jq -r '.organizations | to_entries[] | .key' creds/org1.json)

ORG1_PEER_NAME=$(jq -r .organizations.\"${ORG1_NAME}\".peers[0] creds/org1.json)
ORG1_CA_NAME=$(jq -r .organizations.\"${ORG1_NAME}\".certificateAuthorities[0] creds/org1.json)
ORG1_CA_URL=$(jq -r .certificateAuthorities.\"$ORG1_CA_NAME\".url creds/org1.json | cut -d '/' -f 3)
ORG1_ENROLL_SECRET=$(jq -r .certificateAuthorities.\"$ORG1_CA_NAME\".registrar[0].enrollSecret creds/org1.json)

############################################################
# STEP 1 - generate user certs and upload to remote fabric #
############################################################
# save the cert
jq -r .certificateAuthorities.\"${ORG1_CA_NAME}\".tlsCACerts.pem creds/org1.json > cacert.pem
log "Enrolling admin user for ${ORG1_NAME}."

export ARCH=$(echo "$(uname -s|tr '[:upper:]' '[:lower:]'|sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')
if [ ! -f bin/fabric-ca-client ]; then
	curl https://nexus.hyperledger.org/content/repositories/releases/org/hyperledger/fabric-ca/hyperledger-fabric-ca/${ARCH}-${CA_VERSION}/hyperledger-fabric-ca-${ARCH}-${CA_VERSION}.tar.gz | tar xz
else
	log "fabric-ca-client already exists ... skipping download"
fi

export FABRIC_CA_CLIENT_HOME=${PWD}/creds/org1admin
fabric-ca-client enroll --tls.certfiles ${PWD}/cacert.pem -u https://admin:${ORG1_ENROLL_SECRET}@${ORG1_CA_URL} --mspdir ${PWD}/creds/org1admin/msp

# rename the keyfile
mv creds/org1admin/msp/keystore/* creds/org1admin/msp/keystore/priv.pem

# upload the cert
BODY1=$(cat <<EOF1
{
	"msp_id": "${ORG1_NAME}",
	"adminCertName": "PeerAdminCert1",
	"adminCertificate": "$(get_pem 1)",
	"peer_names": [
		"${ORG1_PEER_NAME}"
	],
	"SKIP_CACHE": true
}
EOF1
)
log "Uploading admin certificate for org 1."
curl -s -X POST \
	--header 'Content-Type: application/json' \
	--header 'Accept: application/json' \
	--basic --user ${ORG1_API_KEY}:${ORG1_API_SECRET} \
	--data "${BODY1}" \
    ${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/certificates


##########################
# STEP 2 - restart peers #
##########################
# STEP 2.1 - ORG1
PEER=${ORG1_PEER_NAME}
log "Stoping ${PEER}"
curl -s -X POST \
	--header 'Content-Type: application/json' \
	--header 'Accept: application/json' \
	--basic --user ${ORG1_API_KEY}:${ORG1_API_SECRET} \
	--data-binary '{}' \
	${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/nodes/${PEER}/stop

log "Waiting for ${PEER} to stop..."
RESULT=""
while [[ ${RESULT} != "exited" ]]; do
	RESULT=$(curl -s -X GET \
		--header 'Content-Type: application/json' \
		--header 'Accept: application/json' \
		--basic --user ${ORG1_API_KEY}:${ORG1_API_SECRET} \
		${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/nodes/status | jq -r '.["'${PEER}'"].status')
done
log "${RESULT}"

log "Starting ${PEER}"
curl -s -X POST \
	--header 'Content-Type: application/json' \
	--header 'Accept: application/json' \
	--basic --user ${ORG1_API_KEY}:${ORG1_API_SECRET} \
	--data-binary '{}' \
	${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/nodes/${PEER}/start

log "Waiting for ${PEER} to start..."
RESULT=""
while [[ ${RESULT} != "running" ]]; do
	RESULT=$(curl -s -X GET \
		--header 'Content-Type: application/json' \
		--header 'Accept: application/json' \
		--basic --user ${ORG1_API_KEY}:${ORG1_API_SECRET} \
		${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/nodes/status | jq -r '.["'${PEER}'"].status')
done
log "${RESULT}"

printf "\n\n Update connection profiles to include the admin certs of ${ORG1_NAME}"
export CERT=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' creds/org1admin/msp/signcerts/cert.pem) 
export KEY=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' creds/org1admin/msp/keystore/priv.pem)
export ORG=${ORG1_NAME}
export ORG_NUM=org1
node updateAdminCerts.js

### If this is not enterprise offerig we see two default orgs for starter
if [ "$IS_ENTERPRISE" != true ]; then
	ORG2_NAME=$(jq -r "[.[] | .key][1]" creds/network.json)
	ORG2_API_KEY=$(jq -r .\"${ORG2_NAME}\".key creds/network.json)
	ORG2_API_SECRET=$(jq -r .\"${ORG2_NAME}\".secret creds/network.json)
	echo "Downloading the Connection profile for org2"
	curl -s -X GET --header 'Content-Type: application/json' --header 'Accept: application/json' --basic --user ${ORG2_API_KEY}:${ORG2_API_SECRET} ${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/connection_profile | jq . >& creds/org2.json
	# ORG2_NAME=$(jq -r '.organizations | to_entries[] | .key' creds/org2.json)
	ORG2_PEER_NAME=$(jq -r .organizations.\"${ORG2_NAME}\".peers[0] creds/org2.json)

	ORG2_CA_NAME=$(jq -r .organizations.\"${ORG2_NAME}\".certificateAuthorities[0] creds/org2.json)
	ORG2_CA_URL=$(jq -r .certificateAuthorities.\"$ORG2_CA_NAME\".url creds/org2.json | cut -d '/' -f 3)
	ORG2_ENROLL_SECRET=$(jq -r .certificateAuthorities.\"$ORG2_CA_NAME\".registrar[0].enrollSecret creds/org2.json)

	# STEP 1.2 - ORG2
	log "Enrolling admin user for org2."
	export FABRIC_CA_CLIENT_HOME=${PWD}/creds/org2admin
	fabric-ca-client enroll --tls.certfiles ${PWD}/cacert.pem -u https://admin:${ORG2_ENROLL_SECRET}@${ORG2_CA_URL} --mspdir ${PWD}/creds/org2admin/msp
	# rename the keyfile
	mv creds/org2admin/msp/keystore/* creds/org2admin/msp/keystore/priv.pem
# upload the cert
BODY2=$(cat <<EOF2
{
 "msp_id": "${ORG2_NAME}",
 "adminCertName": "PeerAdminCert2",
 "adminCertificate": "$(get_pem 2)",
 "peer_names": [
   "${ORG2_PEER_NAME}"
 ],
 "SKIP_CACHE": true
}
EOF2
)
	log "Uploading admin certificate for org 2."
	curl -s -X POST \
		--header 'Content-Type: application/json' \
		--header 'Accept: application/json' \
		--basic --user ${ORG2_API_KEY}:${ORG2_API_SECRET} \
		--data "${BODY2}" \
		${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/certificates

	# STEP 2.2 - ORG2
	PEER="${ORG2_PEER_NAME}"
	log "Stoping ${PEER}"
	curl -s -X POST \
		--header 'Content-Type: application/json' \
		--header 'Accept: application/json' \
		--basic --user ${ORG2_API_KEY}:${ORG2_API_SECRET} \
		--data-binary '{}' \
		${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/nodes/${PEER}/stop

	log "Waiting for ${PEER} to stop..."
	RESULT=""
	while [[ $RESULT != "exited" ]]; do
		RESULT=$(curl -s -X GET \
			--header 'Content-Type: application/json' \
			--header 'Accept: application/json' \
			--basic --user ${ORG2_API_KEY}:${ORG2_API_SECRET} \
			${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/nodes/status | jq -r '.["'${PEER}'"].status')
	done
	log "${RESULT}"

	log "Starting ${PEER}"
	curl -s -X POST \
		--header 'Content-Type: application/json' \
		--header 'Accept: application/json' \
		--basic --user ${ORG2_API_KEY}:${ORG2_API_SECRET} \
		--data-binary '{}' \
		${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/nodes/${PEER}/start

	log "Waiting for ${PEER} to start..."
	RESULT=""
	while [[ $RESULT != "running" ]]; do
		RESULT=$(curl -s -X GET \
			--header 'Content-Type: application/json' \
			--header 'Accept: application/json' \
			--basic --user ${ORG2_API_KEY}:${ORG2_API_SECRET} \
			${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/nodes/status | jq -r '.["'${PEER}'"].status')
	done
	log "${RESULT}"

	printf "\n\n Update connection profiles to include the admin certs of ${ORG2_NAME}"
	export CERT=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' creds/org2admin/msp/signcerts/cert.pem) 
	export KEY=$(awk 'NF {sub(/\r/, ""); printf "%s\\n",$0;}' creds/org2admin/msp/keystore/priv.pem)
	export ORG=${ORG2_NAME}
	export ORG_NUM=org1
	node updateAdminCerts.js
fi

#########################
# STEP 3 - SYNC CHANNEL #
#########################
log "Syncing the channel."
curl -s -X POST \
	--header 'Content-Type: application/json' \
  	--header 'Accept: application/json' \
  	--basic --user ${ORG1_API_KEY}:${ORG1_API_SECRET} \
  	--data-binary '{}' \
  	${API_ENDPOINT}/api/v1/networks/${NETWORK_ID}/channels/${CHANNEL_NAME}/sync


printf "\n\n========= A D M I N   C E R T S   A R E   S Y N C E D  O N   C H A N N E L =============\n"

