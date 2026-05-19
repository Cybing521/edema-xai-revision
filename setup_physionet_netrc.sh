#!/usr/bin/env bash
set -euo pipefail
read -r -p 'PhysioNet username: ' PN_USER
read -r -s -p 'PhysioNet password: ' PN_PASS
echo
cat > ~/.netrc <<NETRC
machine physionet.org
  login ${PN_USER}
  password ${PN_PASS}
NETRC
chmod 600 ~/.netrc
echo 'Testing MIMIC-IV access...'
curl -L --netrc --fail --head https://physionet.org/files/mimiciv/2.2/hosp/patients.csv.gz >/tmp/physionet_mimic_test.log 2>&1 && echo 'MIMIC-IV access OK' || { echo 'MIMIC-IV access failed'; cat /tmp/physionet_mimic_test.log; exit 1; }
echo 'Testing eICU-CRD access...'
curl -L --netrc --fail --head https://physionet.org/files/eicu-crd/2.0/patient.csv.gz >/tmp/physionet_eicu_test.log 2>&1 && echo 'eICU-CRD access OK' || { echo 'eICU-CRD access failed'; cat /tmp/physionet_eicu_test.log; exit 1; }
echo 'PhysioNet credential setup complete.'
