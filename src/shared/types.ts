export type ConnectionProfile = {
  id: string;
  name: string;
  host: string;
  port: number;
  username: 'root';
  agentPort: number;
  repoUrl: string;
  repoRef: string;
  createdAt: string;
  updatedAt: string;
};

export type ConnectionSecret = {
  password?: string;
  privateKey?: string;
  trueNasAdminPassword?: string;
};

export type AgentPayloadMetadata = {
  version: string;
  payloadHash: string;
  fileCount: number;
  byteCount: number;
  calculatedAt?: string;
  agentRoot?: string;
  manifest?: AgentPayloadMetadata;
};

export type AgentHealth = {
  ok: boolean;
  version: string;
  hostname: string;
  uptimeSeconds: number;
  stateDir: string;
  payloadManifest?: AgentPayloadMetadata;
};

export type GuidedStep = {
  id: string;
  title: string;
  weight: number;
  critical: boolean;
  target: string;
  destructive?: boolean;
  requiresManualCheckpoint?: boolean;
};

export type ScriptCategory = 'install' | 'vm' | 'service' | 'config' | 'branding' | 'health' | 'repair' | 'maintenance' | 'support' | 'additional';
export type ScriptRisk = 'safe' | 'caution' | 'destructive';
export type ScriptImplementation = 'ready' | 'wrapped-core' | 'wrapped-vendor' | 'planned';

export type ScriptCatalogItem = {
  id: string;
  title: string;
  description: string;
  category: ScriptCategory;
  target: string;
  riskLevel: ScriptRisk;
  implementation: ScriptImplementation;
  defaultOrder: number;
  tags?: string[];
  requires?: string[];
  stopOnFailure?: boolean;
};

export type ScriptCatalogGroup = {
  id: string;
  title: string;
  description: string;
  itemIds: string[];
  riskLevel: ScriptRisk;
};

export type ScriptCatalog = {
  items: ScriptCatalogItem[];
  groups: ScriptCatalogGroup[];
};

export type StepState = {
  id: string;
  status: 'pending' | 'running' | 'done' | 'warn' | 'failed' | 'skipped';
  updatedAt?: string;
  title?: string;
};

export type ScriptState = StepState & {
  target?: string;
};

export type RunInfo = {
  id: string;
  target: string;
  title: string;
  status: 'queued' | 'running' | 'done' | 'failed' | 'cancelled';
  exitCode?: number;
  startedAt: string;
  finishedAt?: string;
  logPath: string;
  needsRepair?: {
    id: string;
    title: string;
    target?: string;
    reason: string;
  };
};

export type HardwareInventory = {
  collectedAt: string;
  lsblk: string;
  nvme: string;
  pci: string;
  storage: string;
  vmResources: string;
};

export type TrueNasIsoManifest = {
  product?: string;
  brand?: string;
  sourceVersion?: string;
  sourceUrl?: string;
  sourceSha256?: string;
  outputSha256?: string;
  createdAtUtc?: string;
};

export type TrueNasIsoSelection = {
  localPath: string;
  fileName: string;
  sha256: string;
  sizeBytes: number;
  manifestPath?: string;
  manifest?: TrueNasIsoManifest;
  warnings: string[];
  uploaded?: boolean;
  remotePath?: string;
  remoteSha256?: string;
  uploadedAt?: string;
};

export type TrueNasInstallConfig = {
  installMode: 'auto-with-fallback';
  vmId: 101;
  vmName: 'truenas';
  sshHost: '192.168.50.101';
  sshUser: 'truenas_admin';
  bootDiskGb: 64;
  ramMb: 16384;
  cores: 4;
  fixedMac: '02:23:14:00:01:01';
  truenasIso?: TrueNasIsoSelection;
};

export type ChiaDbBootstrapMode = 'fresh' | 'official_torrent' | 'url' | 'manual';

export type HomelabSecretsProfile = {
  updatedAt?: string;
  global: {
    homelabVersion: string;
    domain: string;
    lanGateway: string;
    lanDns: string;
    vmStorage: string;
    mediaVmStorage: string;
    chiaVmStorage: string;
    pbsVmStorage: string;
    stacksDir: string;
    dockerNetwork: string;
    timezone: string;
  };
  users: {
    bacmasterPass: string;
    tulumbaPass: string;
    mediaPass: string;
    backupPass: string;
    atlonPass: string;
    elifezelPass: string;
    immichAdminEmail: string;
    immichSecondUserEmail: string;
    openWebuiAdminEmail: string;
  };
  truenas: {
    adminPassword: string;
    host: string;
    gateway: string;
    dns1: string;
    dns2: string;
    dns3: string;
  };
  smtp: {
    from: string;
    host: string;
    port: string;
    security: string;
    secure: string;
    testTo: string;
    zohoNextcloudAppPass: string;
    zohoImmichAppPass: string;
    zohoSeerrAppPass: string;
    zohoUptimeKumaAppPass: string;
    zohoTruenasAppPass: string;
  };
  google: {
    clientId: string;
    clientSecret: string;
    nextcloudRegistrationEnabled: boolean;
    nextcloudRegistrationApprovalRequired: boolean;
    nextcloudRegistrationAllowedDomains: string;
    nextcloudDefaultUserQuota: string;
  };
  cloudflare: {
    authMode: string;
    tunnelName: string;
  };
  chia: {
    mnemonic: string;
    keyLabel: string;
    dbBootstrapMode: ChiaDbBootstrapMode;
    dbTorrentUrl: string;
    dbDownloadUrl: string;
    dbManualPath: string;
    dbCacheNfs: string;
    dbCacheMount: string;
    dbDownloadDir: string;
    expectedPlotDisks: string;
  };
  ollama: {
    pullModels: boolean;
    models: string;
  };
};

export type HomelabSecretsUploadFile = {
  path: string;
  fileName: string;
  bytes: number;
};

export type HomelabSecretsUploadResult = {
  ok: boolean;
  files: HomelabSecretsUploadFile[];
  warnings: string[];
  uploadedAt: string;
};

export type BrandingRisk = 'low' | 'medium' | 'high';

export type BrandingPack = {
  id: string;
  service: string;
  brandName: string;
  displayName: string;
  description: string;
  primaryColor: string;
  accentColor: string;
  riskLevel: BrandingRisk;
  reapplyAfterUpdate: boolean;
  assets: {
    wideLogo?: string;
    transparentLogo?: string;
    icon?: string;
    favicon?: string;
    loginBackground?: string;
  };
  targets: {
    apply: string;
    status: string;
    restore: string;
  };
  implementation: 'ready' | 'wrapped-vendor' | 'planned' | 'built-in';
};

export type AgentRequestOptions = {
  method?: 'GET' | 'POST';
  body?: unknown;
  timeoutMs?: number;
};

export type GithubSettings = {
  owner: string;
  token?: string;
  tokenSaved?: boolean;
  updatedAt?: string;
};

export type GithubRepoVersion = {
  id: number;
  name: string;
  fullName: string;
  owner: string;
  repo: string;
  htmlUrl: string;
  cloneUrl: string;
  defaultBranch: string;
  private: boolean;
  updatedAt: string;
  version: string;
  versionLabel: string;
};

export type GithubPackageSelection = {
  localPath: string;
  fileName: string;
  sha256: string;
  sizeBytes: number;
  warnings: string[];
};

export type GithubReleaseUploadRequest = {
  owner: string;
  repo: string;
  token?: string;
  tagName: string;
  releaseName: string;
  body?: string;
  draft?: boolean;
  prerelease?: boolean;
  assetPath: string;
  replaceExisting?: boolean;
};

export type GithubReleaseUploadResult = {
  repoFullName: string;
  releaseUrl: string;
  assetUrl: string;
  browserDownloadUrl: string;
  assetName: string;
  sha256: string;
  sizeBytes: number;
  uploadedAt: string;
};

export type GithubRepoPublishRequest = {
  owner: string;
  repo: string;
  token?: string;
  packagePath: string;
  branch?: string;
  description?: string;
  private?: boolean;
  replaceContents?: boolean;
  stripSingleRootDirectory?: boolean;
  commitMessage?: string;
};

export type GithubRepoPublishResult = {
  repoFullName: string;
  repoUrl: string;
  branch: string;
  commitSha: string;
  commitUrl: string;
  createdRepo: boolean;
  uploadedFiles: number;
  totalBytes: number;
  packageSha256: string;
  private: boolean;
  warnings: string[];
  publishedAt: string;
};

export type InstallResetResult = {
  ok: boolean;
  cancelledRuns: string[];
  steps: StepState[];
  scripts: ScriptState[];
  runs: RunInfo[];
  fallback?: 'agent' | 'ssh';
};

export type SupportBundle = {
  path: string;
  fileName: string;
  sizeBytes: number;
  modifiedAt: string;
};

export type SupportBundleDownloadResult = {
  remotePath: string;
  localPath: string;
  summaryPath?: string;
  sizeBytes: number;
  downloadedAt: string;
};

export type SupportBundleDownloadContext = {
  runId?: string;
  runLog?: string;
};

export type HomelabApi = {
  loadProfile: () => Promise<ConnectionProfile | null>;
  saveProfile: (profile: ConnectionProfile, secret?: ConnectionSecret) => Promise<void>;
  testSsh: (profile: ConnectionProfile, secret?: ConnectionSecret) => Promise<{ ok: boolean; output: string }>;
  bootstrapAgent: (profile: ConnectionProfile, secret?: ConnectionSecret) => Promise<{ ok: boolean; output: string; payload?: AgentPayloadMetadata }>;
  localAgentPayload: () => Promise<AgentPayloadMetadata>;
  openTunnel: (profile: ConnectionProfile, secret?: ConnectionSecret) => Promise<{ ok: boolean; localPort: number }>;
  selectTrueNasIso: () => Promise<TrueNasIsoSelection | null>;
  inspectTrueNasIso: (localPath: string) => Promise<TrueNasIsoSelection>;
  uploadTrueNasIso: (
    profile: ConnectionProfile,
    secret: ConnectionSecret | undefined,
    iso: TrueNasIsoSelection
  ) => Promise<TrueNasIsoSelection>;
  loadHomelabSecrets: () => Promise<HomelabSecretsProfile>;
  saveHomelabSecrets: (secrets: HomelabSecretsProfile) => Promise<HomelabSecretsProfile>;
  uploadHomelabSecrets: (
    profile: ConnectionProfile,
    secret: ConnectionSecret | undefined,
    secrets: HomelabSecretsProfile
  ) => Promise<HomelabSecretsUploadResult>;
  loadGithubSettings: () => Promise<GithubSettings>;
  saveGithubSettings: (settings: GithubSettings) => Promise<GithubSettings>;
  listGithubHomelabRepos: (settings: GithubSettings) => Promise<GithubRepoVersion[]>;
  selectGithubPackage: () => Promise<GithubPackageSelection | null>;
  inspectGithubPackage: (localPath: string) => Promise<GithubPackageSelection>;
  uploadGithubReleaseAsset: (request: GithubReleaseUploadRequest) => Promise<GithubReleaseUploadResult>;
  publishGithubRepoFromPackage: (request: GithubRepoPublishRequest) => Promise<GithubRepoPublishResult>;
  resetInstallState: (profile: ConnectionProfile, secret?: ConnectionSecret) => Promise<InstallResetResult>;
  listSupportBundles: (profile: ConnectionProfile, secret?: ConnectionSecret) => Promise<{ bundles: SupportBundle[] }>;
  downloadSupportBundle: (
    profile: ConnectionProfile,
    secret: ConnectionSecret | undefined,
    bundle: SupportBundle
  ) => Promise<SupportBundleDownloadResult | null>;
  downloadSupportBundleToRemoteLogs: (
    profile: ConnectionProfile,
    secret: ConnectionSecret | undefined,
    bundle: SupportBundle,
    context?: SupportBundleDownloadContext
  ) => Promise<SupportBundleDownloadResult>;
  openRemoteLogsFolder: () => Promise<{ path: string }>;
  agentRequest: <T>(path: string, options?: AgentRequestOptions) => Promise<T>;
  readBundledBrandingPacks: () => Promise<BrandingPack[]>;
};
