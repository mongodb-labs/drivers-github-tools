#!/usr/bin/env bash

set -eux

# Get release creator.
export GH_TOKEN=${GH_TOKEN:-TOKEN}
RELEASE_CREATOR=$(gh api users/${ACTOR} --jq '.name')

# Handle security report.
SECURITY_REPORT="N/A"
SECURITY_REPORT_LOCATION=
if [ -n "$SECURITY_REPORT_LOCATION" ]; then
  if [[ $SECURITY_REPORT_LOCATION == https* ]]; then
    SECURITY_REPORT="See $SECURITY_REPORT_LOCATION"
  else
    SECURITY_REPORT="See https://github.com/$REPOSITORY/blob/$RELEASE_VERSION/$SECURITY_REPORT_LOCATION"
  fi
fi

cat << EOF >> ${S3_ASSETS}/ssdlc_compliance_report.md
Release Creator
${RELEASE_CREATOR}

Tool used to track third party vulnerabilities
Silk

Third-Party Dependency Information
See ${SBOM_NAME}

Static Analysis Findings
See ${SARIF_NAME}

Signature Information
See ${AUTHORIZED_PUB_NAME}

Security Report
${SECURITY_REPORT}

Known Vulnerabilities
Any vulnerabilities that may be shown in the files referenced above have been reviewed and accepted by the appropriate approvers.
EOF
