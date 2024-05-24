import { components } from '@octokit/openapi-types'

export type AlertType = components['schemas']['code-scanning-alert-items']
export type RuleType = components['schemas']['code-scanning-alert-rule-summary']
export type AlertLocationType =
  components['schemas']['code-scanning-alert-location']

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

type Region = {
  startLine?: number
  endLine?: number
  startColumn?: number
  endColumn?: number
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

    const ruleName = getRuleIdentifier(alert)

    if (ruleName && !results[alert.tool.name].tool.driver.rules[ruleName]) {
      results[alert.tool.name].tool.driver.rules[ruleName] = createSarifRule(
        alert.rule
      )
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
    ruleId: getRuleIdentifier(alert),
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
        region: createRegion(alert.most_recent_instance.location)
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

function createRegion(location: AlertLocationType): Region {
  const region: Region = {}

  if (location.start_line) {
    region.startLine = location.start_line
  }
  if (location.end_line) {
    region.endLine = location.end_line
  }

  if (location.start_column) {
    region.startColumn = location.start_column
  }
  if (location.end_column) {
    region.endColumn = location.end_column
  }

  return region
}

function getRuleIdentifier(alert: AlertType): string {
  return alert.rule.name ? alert.rule.name : alert.rule.id ? alert.rule.id : ''
}
