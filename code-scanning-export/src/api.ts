import * as github from '@actions/github'
import { AlertType } from './sarif'
import { components } from '@octokit/openapi-types'

type StateType = components['schemas']['code-scanning-alert-state']

export async function getAlerts(
  owner: string,
  repo: string,
  ref: string,
  token: string
): Promise<AlertType[]> {
  return (await getDismissedAlerts(owner, repo, ref, token)).concat(
    await getOpenAlerts(owner, repo, ref, token)
  )
}

async function getDismissedAlerts(
  owner: string,
  repo: string,
  ref: string,
  token: string
): Promise<AlertType[]> {
  return await fetchAlerts(owner, repo, ref, token, 'dismissed')
}

async function getOpenAlerts(
  owner: string,
  repo: string,
  ref: string,
  token: string
): Promise<AlertType[]> {
  return await fetchAlerts(owner, repo, ref, token, 'open')
}

async function fetchAlerts(
  owner: string,
  repo: string,
  ref: string,
  token: string,
  state: StateType
): Promise<AlertType[]> {
  const octokit = github.getOctokit(token)

  return await octokit.paginate(octokit.rest.codeScanning.listAlertsForRepo, {
    owner,
    repo,
    ref,
    state
  })
}
