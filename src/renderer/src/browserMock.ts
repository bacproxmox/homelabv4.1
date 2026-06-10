import brandingManifest from '../../../agent/manifests/branding-packs.json';
import guidedManifest from '../../../agent/manifests/guided-steps.json';
import scriptCatalogManifest from '../../../agent/manifests/script-catalog.json';
import type {
  AgentHealth,
  AgentRequestOptions,
  BrandingPack,
  GithubPackageSelection,
  GithubRepoPublishResult,
  GithubRepoVersion,
  HardwareInventory,
  HomelabApi,
  HomelabSecretsProfile,
  HomelabSecretsUploadResult,
  RunInfo,
  ScriptCatalog,
  SupportBundle,
  TrueNasIsoSelection
} from '@shared/types';

const packs = brandingManifest.packs as BrandingPack[];
const scripts = scriptCatalogManifest as ScriptCatalog;

const mockHealth: AgentHealth = {
  ok: true,
  version: '4.1.0-preview',
  hostname: 'proxmox-preview',
  uptimeSeconds: 48114,
  stateDir: '/opt/homelabv4/state'
};

const mockInventory: HardwareInventory = {
  collectedAt: new Date().toISOString(),
  lsblk: 'nvme0n1 1T MLD M500\nnvme1n1 1T ADATA XPG S50\nnvme2n1 2T XPG S40G\nsda 480G Kioxia\nsdb 500G Samsung 870 EVO\nsd[c-h] 8T Toshiba N300',
  nvme: 'MLD M500, ADATA XPG Gammix S50, XPG Spectrix S40G',
  pci: 'Intel i5-14400, MSI Z790 EDGE, RTX 3060 passthrough candidate, JMicron JMS58x adapters',
  storage: 'Fresh wipe gated to explicitly selected NVMe targets only.',
  vmResources: 'VM 106\nname: docker-media\nmemory: 65536\nballoon: 32768\ncores: 8'
};

const previewRun = (target: string): RunInfo => ({
  id: `preview-${Date.now()}`,
  target,
  title: target,
  status: 'done',
  exitCode: 0,
  startedAt: new Date().toISOString(),
  finishedAt: new Date().toISOString(),
  logPath: '/opt/homelabv4/logs/preview.log'
});

const mockTrueNasIso = (): TrueNasIsoSelection => ({
  localPath: 'C:\\Users\\Burhan\\Documents\\Bacmaster Brand ISO tool\\out\\Bacmasters-NAS_25.10.4.iso',
  fileName: 'Bacmasters-NAS_25.10.4.iso',
  sha256: '0b027944e4f7eebe62cd17f10a63c07463343f0cb75842339965d0a14ea9b93e',
  sizeBytes: 2_147_483_648,
  manifestPath: 'C:\\Users\\Burhan\\Documents\\Bacmaster Brand ISO tool\\out\\Bacmasters-NAS_25.10.4.iso.manifest.json',
  manifest: {
    product: 'truenas',
    brand: "Bacmaster's NAS",
    sourceVersion: '25.10.4',
    outputSha256: '0b027944e4f7eebe62cd17f10a63c07463343f0cb75842339965d0a14ea9b93e'
  },
  warnings: []
});

const mockGithubRepos = (): GithubRepoVersion[] => [
  {
    id: 245,
    name: 'homelabv2.4.5',
    fullName: 'bacproxmox/homelabv2.4.5',
    owner: 'bacproxmox',
    repo: 'homelabv2.4.5',
    htmlUrl: 'https://github.com/bacproxmox/homelabv2.4.5',
    cloneUrl: 'https://github.com/bacproxmox/homelabv2.4.5.git',
    defaultBranch: 'main',
    private: false,
    updatedAt: new Date().toISOString(),
    version: '2.4.5',
    versionLabel: 'Homelabv2.4.5'
  },
  {
    id: 311,
    name: 'homelabv3.1.1-r2',
    fullName: 'bacproxmox/homelabv3.1.1-r2',
    owner: 'bacproxmox',
    repo: 'homelabv3.1.1-r2',
    htmlUrl: 'https://github.com/bacproxmox/homelabv3.1.1-r2',
    cloneUrl: 'https://github.com/bacproxmox/homelabv3.1.1-r2.git',
    defaultBranch: 'main',
    private: false,
    updatedAt: new Date().toISOString(),
    version: '3.1.1-r2',
    versionLabel: 'Homelabv3.1.1-r2'
  },
  {
    id: 400,
    name: 'homelabv4.1',
    fullName: 'bacproxmox/homelabv4.1',
    owner: 'bacproxmox',
    repo: 'homelabv4.1',
    htmlUrl: 'https://github.com/bacproxmox/homelabv4.1',
    cloneUrl: 'https://github.com/bacproxmox/homelabv4.1.git',
    defaultBranch: 'main',
    private: false,
    updatedAt: new Date().toISOString(),
    version: '4.1',
    versionLabel: 'Homelabv4.1'
  }
];

const mockGithubPackage = (): GithubPackageSelection => ({
  localPath: 'C:\\Users\\Burhan\\Documents\\Homelabv4\\homelabv4.1.zip',
  fileName: 'homelabv4.1.zip',
  sha256: '8640d383570df6e6e65185a7e1454f0fed22e377ca33418bd1cd9fa3c9f12d13',
  sizeBytes: 96_000_000,
  warnings: []
});

const mockSupportBundle = (): SupportBundle => ({
  path: '/root/homelabv4-support-20260608-120000.tar.gz',
  fileName: 'homelabv4-support-20260608-120000.tar.gz',
  sizeBytes: 2_400_000,
  modifiedAt: new Date().toISOString()
});

const mockHomelabSecrets = (): HomelabSecretsProfile => ({
  updatedAt: new Date().toISOString(),
  global: {
    homelabVersion: '4.1',
    domain: 'bacmastercloud.com',
    lanGateway: '192.168.50.1',
    lanDns: '1.1.1.1',
    vmStorage: 'nvme-vm',
    mediaVmStorage: 'nvme-vm-two',
    chiaVmStorage: 'nvme-vm-two',
    pbsVmStorage: 'nvme-vm',
    stacksDir: '/opt/homelab',
    dockerNetwork: 'homelab',
    timezone: 'Europe/Istanbul'
  },
  users: {
    bacmasterPass: '',
    tulumbaPass: '',
    mediaPass: '',
    backupPass: '',
    atlonPass: '',
    elifezelPass: '',
    immichAdminEmail: 'admin@bacmastercloud.com',
    immichSecondUserEmail: 'cinarburhan1601@gmail.com',
    openWebuiAdminEmail: 'admin@bacmastercloud.com'
  },
  truenas: {
    adminPassword: '',
    host: '192.168.50.101',
    gateway: '192.168.50.1',
    dns1: '192.168.50.1',
    dns2: '192.168.50.1',
    dns3: '1.1.1.1'
  },
  smtp: {
    from: 'admin@bacmastercloud.com',
    host: 'smtppro.zoho.eu',
    port: '465',
    security: 'SSL/TLS',
    secure: 'ssl',
    testTo: 'admin@bacmastercloud.com',
    zohoNextcloudAppPass: '',
    zohoImmichAppPass: '',
    zohoSeerrAppPass: '',
    zohoUptimeKumaAppPass: '',
    zohoTruenasAppPass: ''
  },
  google: {
    clientId: '',
    clientSecret: '',
    nextcloudRegistrationEnabled: true,
    nextcloudRegistrationApprovalRequired: true,
    nextcloudRegistrationAllowedDomains: 'gmail.com,googlemail.com,bacmastercloud.com',
    nextcloudDefaultUserQuota: '5 GB'
  },
  cloudflare: {
    authMode: 'interactive-login',
    tunnelName: 'homelab-main'
  },
  chia: {
    mnemonic: '',
    keyLabel: 'bacmaster',
    dbBootstrapMode: 'official_torrent',
    dbTorrentUrl: 'https://torrents.chia.net/databases/mainnet/mainnet.latest.tar.gz.torrent',
    dbDownloadUrl: 'https://torrents.chia.net/databases/mainnet/mainnet.latest.tar.gz.torrent',
    dbManualPath: '',
    dbCacheNfs: '192.168.50.101:/mnt/tank/chia-db',
    dbCacheMount: '/mnt/chia-db-cache',
    dbDownloadDir: '/mnt/chia-db-cache',
    expectedPlotDisks: '5'
  },
  ollama: {
    pullModels: true,
    models: 'llama3.1:8b qwen2.5-coder:7b nomic-embed-text'
  }
});

const mockHomelabSecretsUpload = (): HomelabSecretsUploadResult => ({
  ok: true,
  uploadedAt: new Date().toISOString(),
  warnings: [],
  files: [
    'global.env',
    'users.env',
    'truenas-login.env',
    'smtp.env',
    'google.env',
    'nextcloud-sociallogin.env',
    'cloudflare.env',
    'chia-bootstrap.env',
    'ollama-models.env'
  ].map((fileName) => ({
    fileName,
    path: `/root/homelab-secrets/${fileName}`,
    bytes: 512
  }))
});

export function installBrowserMock(): void {
  if (window.homelab) return;

  const api: HomelabApi = {
    loadProfile: async () => null,
    saveProfile: async () => undefined,
    testSsh: async () => ({ ok: true, output: 'Preview mode: SSH test is mocked.' }),
    bootstrapAgent: async () => ({ ok: true, output: 'Preview mode: agent bootstrap is mocked.' }),
    localAgentPayload: async () => ({
      version: 'preview',
      payloadHash: 'preview',
      fileCount: 0,
      byteCount: 0,
      calculatedAt: new Date().toISOString()
    }),
    openTunnel: async () => ({ ok: true, localPort: 48114 }),
    selectTrueNasIso: async () => mockTrueNasIso(),
    inspectTrueNasIso: async () => mockTrueNasIso(),
    uploadTrueNasIso: async () => ({
      ...mockTrueNasIso(),
      uploaded: true,
      remotePath: '/var/lib/vz/template/iso/Bacmasters-NAS_25.10.4.iso',
      remoteSha256: mockTrueNasIso().sha256,
      uploadedAt: new Date().toISOString()
    }),
    loadHomelabSecrets: async () => mockHomelabSecrets(),
    saveHomelabSecrets: async (secrets) => ({ ...secrets, updatedAt: new Date().toISOString() }),
    uploadHomelabSecrets: async () => mockHomelabSecretsUpload(),
    loadGithubSettings: async () => ({ owner: 'bacproxmox', tokenSaved: false }),
    saveGithubSettings: async (settings) => ({ owner: settings.owner || 'bacproxmox', tokenSaved: Boolean(settings.token) }),
    listGithubHomelabRepos: async () => mockGithubRepos(),
    selectGithubPackage: async () => mockGithubPackage(),
    inspectGithubPackage: async () => mockGithubPackage(),
    uploadGithubReleaseAsset: async (request) => ({
      repoFullName: `${request.owner}/${request.repo}`,
      releaseUrl: `https://github.com/${request.owner}/${request.repo}/releases/tag/${request.tagName}`,
      assetUrl: `https://github.com/${request.owner}/${request.repo}/releases/download/${request.tagName}/homelabv4.1.zip`,
      browserDownloadUrl: `https://github.com/${request.owner}/${request.repo}/releases/download/${request.tagName}/homelabv4.1.zip`,
      assetName: 'homelabv4.1.zip',
      sha256: mockGithubPackage().sha256,
      sizeBytes: mockGithubPackage().sizeBytes,
      uploadedAt: new Date().toISOString()
    }),
    publishGithubRepoFromPackage: async (request): Promise<GithubRepoPublishResult> => ({
      repoFullName: `${request.owner}/${request.repo}`,
      repoUrl: `https://github.com/${request.owner}/${request.repo}`,
      branch: request.branch ?? 'main',
      commitSha: '9d20df743ae1a9d2f61f09d641fd1ad4d2055540',
      commitUrl: `https://github.com/${request.owner}/${request.repo}/commit/9d20df743ae1a9d2f61f09d641fd1ad4d2055540`,
      createdRepo: true,
      uploadedFiles: 561,
      totalBytes: mockGithubPackage().sizeBytes,
      packageSha256: mockGithubPackage().sha256,
      private: request.private ?? false,
      warnings: [],
      publishedAt: new Date().toISOString()
    }),
    resetInstallState: async () => ({
      ok: true,
      cancelledRuns: [],
      steps: [],
      scripts: [],
      runs: [],
      fallback: 'agent'
    }),
    listSupportBundles: async () => ({ bundles: [mockSupportBundle()] }),
    downloadSupportBundle: async (_profile, _secret, bundle) => ({
      remotePath: bundle.path,
      localPath: `C:\\Users\\Burhan\\Downloads\\${bundle.fileName}`,
      sizeBytes: bundle.sizeBytes,
      downloadedAt: new Date().toISOString()
    }),
    downloadSupportBundleToRemoteLogs: async (_profile, _secret, bundle) => ({
      remotePath: bundle.path,
      localPath: `C:\\Users\\Burhan\\Documents\\Homelabv4\\Remote-Logs\\${bundle.fileName}`,
      summaryPath: `C:\\Users\\Burhan\\Documents\\Homelabv4\\Remote-Logs\\${bundle.fileName}.summary.txt`,
      sizeBytes: bundle.sizeBytes,
      downloadedAt: new Date().toISOString()
    }),
    openRemoteLogsFolder: async () => ({ path: 'C:\\Users\\Burhan\\Documents\\Homelabv4\\Remote-Logs' }),
    readBundledBrandingPacks: async () => packs,
    agentRequest: async <T>(path: string, options: AgentRequestOptions = {}) => {
      if (path === '/api/v1/health') return mockHealth as T;
      if (path === '/api/v1/payload') {
        return {
          version: 'preview',
          payloadHash: 'preview',
          fileCount: 0,
          byteCount: 0,
          calculatedAt: new Date().toISOString()
        } as T;
      }
      if (path === '/api/v1/manifest') return guidedManifest as T;
      if (path === '/api/v1/script-catalog') return scripts as T;
      if (path === '/api/v1/state') return { steps: [], scripts: [], runs: [], installProfile: {} } as T;
      if (path === '/api/v1/inventory/hardware') return mockInventory as T;
      if (path === '/api/v1/branding/packs') return { packs } as T;
      if (path.includes('/api/v1/branding/packs/') && path.endsWith('/status')) {
        return { id: path.split('/').at(-2), status: 'preview', output: 'Preview mode: status target is mocked.' } as T;
      }
      if (path === '/api/v1/runs' && options.method === 'POST') return previewRun('preview') as T;
      if (path === '/api/v1/script-catalog/runs' && options.method === 'POST') return previewRun('script-preview') as T;
      if (path.startsWith('/api/v1/script-catalog/groups/') && path.endsWith('/run')) return previewRun('script-group-preview') as T;
      if (path === '/api/v1/runs') return { runs: [] } as T;
      if (path === '/api/v1/support-bundle') return { path: '/opt/homelabv4/support-bundles/preview.tar.gz' } as T;
      if (path === '/api/v1/support/bundles') return { bundles: [mockSupportBundle()] } as T;
      return previewRun(path) as T;
    }
  };

  window.homelab = api;
}
