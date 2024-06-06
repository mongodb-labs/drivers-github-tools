
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

Known Vulnerabilities
Any vulnerabilities that may be shown in the links referenced above have been reviewed and accepted by the appropriate approvers.
EOF
