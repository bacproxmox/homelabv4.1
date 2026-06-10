import { contextBridge, ipcRenderer } from 'electron';
import type {
  AgentRequestOptions,
  BrandingPack,
  ConnectionProfile,
  ConnectionSecret,
  GithubPackageSelection,
  GithubRepoPublishRequest,
  GithubRepoPublishResult,
  GithubReleaseUploadRequest,
  GithubReleaseUploadResult,
  GithubRepoVersion,
  GithubSettings,
  HomelabSecretsProfile,
  HomelabSecretsUploadResult,
  InstallResetResult,
  HomelabApi,
  SupportBundle,
  SupportBundleDownloadContext,
  SupportBundleDownloadResult,
  TrueNasIsoSelection
} from '../shared/types';

const api: HomelabApi = {
  loadProfile: () => ipcRenderer.invoke('profile:load'),
  saveProfile: (profile: ConnectionProfile, secret?: ConnectionSecret) => ipcRenderer.invoke('profile:save', profile, secret),
  testSsh: (profile: ConnectionProfile, secret?: ConnectionSecret) => ipcRenderer.invoke('ssh:test', profile, secret),
  bootstrapAgent: (profile: ConnectionProfile, secret?: ConnectionSecret) => ipcRenderer.invoke('agent:bootstrap', profile, secret),
  localAgentPayload: () => ipcRenderer.invoke('agent:payload:local'),
  openTunnel: (profile: ConnectionProfile, secret?: ConnectionSecret) => ipcRenderer.invoke('agent:tunnel', profile, secret),
  selectTrueNasIso: () => ipcRenderer.invoke('truenasIso:select') as Promise<TrueNasIsoSelection | null>,
  inspectTrueNasIso: (localPath: string) => ipcRenderer.invoke('truenasIso:inspect', localPath) as Promise<TrueNasIsoSelection>,
  uploadTrueNasIso: (profile: ConnectionProfile, secret: ConnectionSecret | undefined, iso: TrueNasIsoSelection) =>
    ipcRenderer.invoke('truenasIso:upload', profile, secret, iso) as Promise<TrueNasIsoSelection>,
  loadHomelabSecrets: () => ipcRenderer.invoke('secrets:load') as Promise<HomelabSecretsProfile>,
  saveHomelabSecrets: (secrets: HomelabSecretsProfile) =>
    ipcRenderer.invoke('secrets:save', secrets) as Promise<HomelabSecretsProfile>,
  uploadHomelabSecrets: (profile: ConnectionProfile, secret: ConnectionSecret | undefined, secrets: HomelabSecretsProfile) =>
    ipcRenderer.invoke('secrets:upload', profile, secret, secrets) as Promise<HomelabSecretsUploadResult>,
  loadGithubSettings: () => ipcRenderer.invoke('github:settings:load') as Promise<GithubSettings>,
  saveGithubSettings: (settings: GithubSettings) => ipcRenderer.invoke('github:settings:save', settings) as Promise<GithubSettings>,
  listGithubHomelabRepos: (settings: GithubSettings) => ipcRenderer.invoke('github:repos:list', settings) as Promise<GithubRepoVersion[]>,
  selectGithubPackage: () => ipcRenderer.invoke('github:package:select') as Promise<GithubPackageSelection | null>,
  inspectGithubPackage: (localPath: string) => ipcRenderer.invoke('github:package:inspect', localPath) as Promise<GithubPackageSelection>,
  uploadGithubReleaseAsset: (request: GithubReleaseUploadRequest) =>
    ipcRenderer.invoke('github:release:upload', request) as Promise<GithubReleaseUploadResult>,
  publishGithubRepoFromPackage: (request: GithubRepoPublishRequest) =>
    ipcRenderer.invoke('github:repo:publish-from-package', request) as Promise<GithubRepoPublishResult>,
  resetInstallState: (profile: ConnectionProfile, secret?: ConnectionSecret) =>
    ipcRenderer.invoke('agent:reset-install-state', profile, secret) as Promise<InstallResetResult>,
  listSupportBundles: (profile: ConnectionProfile, secret?: ConnectionSecret) =>
    ipcRenderer.invoke('support:bundles:list', profile, secret) as Promise<{ bundles: SupportBundle[] }>,
  downloadSupportBundle: (profile: ConnectionProfile, secret: ConnectionSecret | undefined, bundle: SupportBundle) =>
    ipcRenderer.invoke('support:bundle:download', profile, secret, bundle) as Promise<SupportBundleDownloadResult | null>,
  downloadSupportBundleToRemoteLogs: (
    profile: ConnectionProfile,
    secret: ConnectionSecret | undefined,
    bundle: SupportBundle,
    context?: SupportBundleDownloadContext
  ) =>
    ipcRenderer.invoke('support:bundle:download-remote-logs', profile, secret, bundle, context) as Promise<SupportBundleDownloadResult>,
  openRemoteLogsFolder: () => ipcRenderer.invoke('support:remote-logs:open') as Promise<{ path: string }>,
  agentRequest: <T>(path: string, options?: AgentRequestOptions) => ipcRenderer.invoke('agent:request', path, options) as Promise<T>,
  readBundledBrandingPacks: () => ipcRenderer.invoke('branding:bundled-packs') as Promise<BrandingPack[]>
};

contextBridge.exposeInMainWorld('homelab', api);
