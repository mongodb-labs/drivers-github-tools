import * as core from '@actions/core'
import { getAlerts } from './api'
import { createSarifReport } from './sarif'
import * as fs from 'fs'
import * as process from 'process'
import * as path from 'path'

type RepositoryInfo = {
  owner: string
  repo: string
}

/**
 * The main function for the action.
 * @returns {Promise<void>} Resolves when the action is complete.
 */
export async function run(): Promise<void> {
  const repositoryInfo = getRepositoryInfo()
  const ref = core.getInput('ref')

  core.debug(
    `Fetching open and dismissed alerts for repository ${repositoryInfo.owner}/${repositoryInfo.repo}#${ref}`
  )

  const alerts = await getAlerts(
    repositoryInfo.owner,
    repositoryInfo.repo,
    ref,
    core.getInput('token')
  )

  core.debug(`Found ${alerts.length} alerts, processing now...`)

  const sarifReport = createSarifReport(alerts)
  const filePath = path.join(process.cwd(), core.getInput('output-file'))

  core.debug(`Processing done, writing report to file ${filePath}`)

  fs.writeFileSync(filePath, JSON.stringify(sarifReport), {})
}

function getRepositoryInfo(): RepositoryInfo {
  const repository = process.env['GITHUB_REPOSITORY']
  if (repository === undefined) {
    throw new Error('"GITHUB_REPOSITORY" environment variable must be set')
  }

  return parseRepositoryInfo(repository)
}

/**
 * Shamelessly stolen from https://github.com/github/codeql-action/blob/acdf23828ad6151dd966f467acc7cf231aca129b/src/repository.ts#L9
 */
function parseRepositoryInfo(input: string): RepositoryInfo {
  const parts = input.split('/')

  if (parts.length !== 2) {
    throw new Error(`"${input}" is not a valid repository name`)
  }

  return {
    owner: parts[0],
    repo: parts[1]
  }
}
