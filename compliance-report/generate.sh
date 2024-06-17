#!/usr/bin/env bash

set -eux

# Get release creator.
cd $GITHUB_WORKSPACE
if [ -n "$TOKEN" ]; then
  export GH_TOKEN=$TOKEN
fi
RELEASE_CREATOR=$(gh api users/${GITHUB_ACTOR} --jq '.name')

# Handle security report.
SECURITY_REPORT="N/A"
if [ -n "$SECURITY_REPORT_LOCATION" ]; then
  if [[ $SECURITY_REPORT_LOCATION == https* ]]; then
    SECURITY_REPORT="See $SECURITY_REPORT_LOCATION"
  else
    SECURITY_REPORT="See https://github.com/$GITHUB_REPOSITORY/blob/$RELEASE_VERSION/$SECURITY_REPORT_LOCATION"
  fi
elif [ -n "$SECURITY_REPORT_URL" ]; then
    SECURITY_REPORT="See $SECURITY_REPORT_URL"
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

cat ${S3_ASSETS}/ssdlc_compliance_report.md