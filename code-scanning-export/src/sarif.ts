import { components } from '@octokit/openapi-types'

export type AlertType = components['schemas']['code-scanning-alert-items']
export type RuleType = components['schemas']['code-scanning-alert-rule-summary']

type SarifReport = {
  version: string
  $schema: string
  runs: {
    tool: {
      driver: {
        name: string
        version: string | null | undefined
        rules: object[]
      }
    }
    results: object[]
  }[]
}

export function createSarifReport(alerts: AlertType[]): SarifReport {
  const results: {
    [index: string]: {
      tool: {
        driver: {
          name: string
          version: string | null | undefined
          rules: { [index: string]: object }
        }
      }
      results: object[]
    }
  } = {}

  for (const alert of alerts) {
    if (!alert.tool.name) {
      continue
    }

    if (!results[alert.tool.name]) {
      results[alert.tool.name] = {
        tool: {
          driver: {
            name: alert.tool.name,
            version: alert.tool.version,
            rules: {}
          }
        },
        results: []
      }
    }

    results[alert.tool.name].results.push(createSarifResult(alert))

    if (
      alert.rule.name &&
      !results[alert.tool.name].tool.driver.rules[alert.rule.name]
    ) {
      results[alert.tool.name].tool.driver.rules[alert.rule.name] =
        createSarifRule(alert.rule)
    }
  }

  return {
    version: '2.1.0',
    $schema: 'https://json.schemastore.org/sarif-2.1.0.json',
    runs: Object.keys(results).map((toolName: string) => {
      const toolResults = results[toolName]

      return {
        tool: {
          driver: {
            ...toolResults.tool.driver,
            rules: Object.keys(toolResults.tool.driver.rules).map(
              ruleName => toolResults.tool.driver.rules[ruleName]
            )
          }
        },
        results: toolResults.results
      }
    })
  }
}

function createSarifRule(rule: RuleType): object {
  return {
    id: rule.name,
    shortDescription: { text: rule.description },
    properties: { tags: rule.tags }
  }
}

export function createSarifResult(alert: AlertType): object {
  return {
    ruleId: alert.rule.name,
    message: alert.most_recent_instance.message,
    level: alert.rule.severity,
    locations: createResultLocation(alert),
    suppressions: createResultSuppressions(alert)
  }
}

function createResultLocation(alert: AlertType): object[] {
  if (!alert.most_recent_instance.location) {
    return []
  }

  return [
    {
      physicalLocation: {
        artifactLocation: { uri: alert.most_recent_instance.location.path },
        region: {
          startLine: alert.most_recent_instance.location.start_line,
          endLine: alert.most_recent_instance.location.end_line,
          startColumn: alert.most_recent_instance.location.start_column,
          endColumn: alert.most_recent_instance.location.end_column
        }
      }
    }
  ]
}

function createResultSuppressions(alert: AlertType): object[] {
  if (alert.state !== 'dismissed' || !alert.dismissed_reason) {
    return []
  }

  let justification: string = alert.dismissed_reason
  if (alert.dismissed_comment) {
    justification += `;${alert.dismissed_comment}`
  }

  return [
    {
      kind: 'external',
      status: 'accepted',
      justification
    }
  ]
}
