/**
 * Unit tests for SARIF generation functions
 */

import { createSarifReport, createSarifResult, AlertType } from '../src/sarif'
import { matchers } from 'jest-json-schema'
import sarifSchema from './sarif-2.1.0.json'

expect.extend(matchers)

const dismissedAlert: AlertType = {
  number: 331,
  created_at: '2024-05-07T12:21:11Z',
  updated_at: '2024-05-10T14:09:26Z',
  url: 'https://api.github.com/repos/mongodb/mongo-php-library/code-scanning/alerts/331',
  html_url:
    'https://github.com/mongodb/mongo-php-library/security/code-scanning/331',
  state: 'dismissed',
  fixed_at: null,
  dismissed_by: {
    login: 'alcaeus',
    id: 383198,
    node_id: 'MDQ6VXNlcjM4MzE5OA==',
    avatar_url: 'https://avatars.githubusercontent.com/u/383198?v=4',
    gravatar_id: '',
    url: 'https://api.github.com/users/alcaeus',
    html_url: 'https://github.com/alcaeus',
    followers_url: 'https://api.github.com/users/alcaeus/followers',
    following_url:
      'https://api.github.com/users/alcaeus/following{/other_user}',
    gists_url: 'https://api.github.com/users/alcaeus/gists{/gist_id}',
    starred_url: 'https://api.github.com/users/alcaeus/starred{/owner}{/repo}',
    subscriptions_url: 'https://api.github.com/users/alcaeus/subscriptions',
    organizations_url: 'https://api.github.com/users/alcaeus/orgs',
    repos_url: 'https://api.github.com/users/alcaeus/repos',
    events_url: 'https://api.github.com/users/alcaeus/events{/privacy}',
    received_events_url: 'https://api.github.com/users/alcaeus/received_events',
    type: 'User',
    site_admin: false
  },
  dismissed_at: '2024-05-10T14:09:26Z',
  dismissed_reason: "won't fix",
  dismissed_comment: null,
  rule: {
    id: '194',
    severity: 'note',
    description: 'MixedArgumentTypeCoercion',
    name: 'MixedArgumentTypeCoercion',
    tags: ['maintainability']
  },
  tool: {
    name: 'Psalm',
    guid: null,
    version: '5.24.0@462c80e31c34e58cc4f750c656be3927e80e550e'
  },
  most_recent_instance: {
    ref: 'refs/heads/master',
    analysis_key: '.github/workflows/static-analysis.yml:psalm',
    environment: '{}',
    category: '.github/workflows/static-analysis.yml:psalm',
    state: 'dismissed',
    commit_sha: '5cb0d7fd464b86e9ca9ba17a05ba03a1b5c3e51a',
    message: {
      text: 'Argument 1 of MongoDB\\all_servers_support_write_stage_on_secondary expects array<array-key, MongoDB\\Driver\\Server>, but parent type array<array-key, mixed> provided'
    },
    location: {
      path: 'src/functions.php',
      start_line: 635,
      end_line: 635,
      start_column: 56,
      end_column: 78
    },
    classifications: []
  },
  instances_url:
    'https://api.github.com/repos/mongodb/mongo-php-library/code-scanning/alerts/331/instances'
}
const openAlert: AlertType = {
  number: 331,
  created_at: '2024-05-07T12:21:11Z',
  updated_at: '2024-05-10T14:09:26Z',
  url: 'https://api.github.com/repos/mongodb/mongo-php-library/code-scanning/alerts/331',
  html_url:
    'https://github.com/mongodb/mongo-php-library/security/code-scanning/331',
  state: 'open',
  fixed_at: null,
  dismissed_by: null,
  dismissed_at: null,
  dismissed_reason: null,
  dismissed_comment: null,
  rule: {
    id: '194',
    severity: 'note',
    description: 'MixedArgumentTypeCoercion',
    name: 'MixedArgumentTypeCoercion',
    tags: ['maintainability']
  },
  tool: {
    name: 'Psalm',
    guid: null,
    version: '5.24.0@462c80e31c34e58cc4f750c656be3927e80e550e'
  },
  most_recent_instance: {
    ref: 'refs/heads/master',
    analysis_key: '.github/workflows/static-analysis.yml:psalm',
    environment: '{}',
    category: '.github/workflows/static-analysis.yml:psalm',
    state: 'open',
    commit_sha: '5cb0d7fd464b86e9ca9ba17a05ba03a1b5c3e51a',
    message: {
      text: 'Argument 1 of MongoDB\\all_servers_support_write_stage_on_secondary expects array<array-key, MongoDB\\Driver\\Server>, but parent type array<array-key, mixed> provided'
    },
    location: {
      path: 'src/functions.php',
      start_line: 635,
      end_line: 635,
      start_column: 56,
      end_column: 78
    },
    classifications: []
  },
  instances_url:
    'https://api.github.com/repos/mongodb/mongo-php-library/code-scanning/alerts/331/instances'
}

describe('createSarifReport', () => {
  it('generates a valid sarif report', () => {
    const report = createSarifReport([dismissedAlert, openAlert])

    expect(report).toMatchSchema(sarifSchema)

    expect(report.runs).toHaveLength(1)
    expect(report.runs[0].tool).toMatchObject({
      driver: {
        name: 'Psalm',
        version: '5.24.0@462c80e31c34e58cc4f750c656be3927e80e550e'
      }
    })
    expect(report.runs[0].results).toHaveLength(2)
  })
})

describe('createSarifResult', () => {
  it('generates correct sarif for an alert', () => {
    expect(createSarifResult(openAlert)).toEqual({
      ruleId: 'MixedArgumentTypeCoercion',
      message: {
        text: 'Argument 1 of MongoDB\\all_servers_support_write_stage_on_secondary expects array<array-key, MongoDB\\Driver\\Server>, but parent type array<array-key, mixed> provided'
      },
      level: 'note',
      locations: [
        {
          physicalLocation: {
            artifactLocation: { uri: 'src/functions.php' },
            region: {
              startLine: 635,
              endLine: 635,
              startColumn: 56,
              endColumn: 78
            }
          }
        }
      ],
      suppressions: []
    })
  })

  it('adds a suppression for a dismissed alert', () => {
    expect(createSarifResult(dismissedAlert)).toEqual({
      ruleId: 'MixedArgumentTypeCoercion',
      message: {
        text: 'Argument 1 of MongoDB\\all_servers_support_write_stage_on_secondary expects array<array-key, MongoDB\\Driver\\Server>, but parent type array<array-key, mixed> provided'
      },
      level: 'note',
      locations: [
        {
          physicalLocation: {
            artifactLocation: { uri: 'src/functions.php' },
            region: {
              startLine: 635,
              endLine: 635,
              startColumn: 56,
              endColumn: 78
            }
          }
        }
      ],
      suppressions: [
        {
          kind: 'external',
          status: 'accepted',
          justification: "won't fix"
        }
      ]
    })
  })
})
