const fs = require('fs');
const path = require('path');
let orgName = process.env.ORG;

if (! orgName || orgName == undefined ){
    throw new Error("Org name is not provided ");
}
let orgNumber = process.env.ORG_NUM;

if (! orgNumber || orgNumber == undefined ){
    throw new Error("Org number ex., 'org1' is not provided ");
}


let cert = process.env.CERT;
if (! cert || cert == undefined ){
    throw new Error("Org admin certificate is not set ");
}

let key = process.env.KEY;
if (! key || key == undefined ){
    throw new Error("Org admin private key is not set");
}


let config = require(path.join(__dirname, process.env.CONNECTION_PROF_DIR,  orgNumber + '.json'));
config.organizations[orgName].signedCert.pem = cert.replace(/\\n/g, '\n');
config.organizations[orgName].adminPrivateKey = {};
config.organizations[orgName].adminPrivateKey.pem = key.replace(/\\n/g, '\n');
// console.log(JSON.stringify(config, null, 4));
fs.writeFileSync(path.join(__dirname, process.env.CONNECTION_PROF_DIR, orgNumber + '.json'), JSON.stringify(config, null, 4), 'utf-8');