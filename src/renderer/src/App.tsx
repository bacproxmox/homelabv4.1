import {
  Activity,
  BadgeCheck,
  Box,
  Cable,
  CheckCircle2,
  ClipboardList,
  Cloud,
  Cpu,
  Download,
  ExternalLink,
  FolderOpen,
  Github,
  HardDrive,
  HeartPulse,
  KeyRound,
  LifeBuoy,
  ListChecks,
  MonitorCog,
  Package,
  Paintbrush,
  Play,
  RotateCcw,
  ShieldCheck,
  TerminalSquare,
  Upload,
  Wrench
} from 'lucide-react';
import { useEffect, useMemo, useRef, useState } from 'react';
import bundledScriptCatalog from '../../../agent/manifests/script-catalog.json';
import type {
  AgentRequestOptions,
  AgentHealth,
  AgentPayloadMetadata,
  BrandingPack,
  ConnectionProfile,
  ConnectionSecret,
  GithubPackageSelection,
  GithubRepoPublishResult,
  GithubRepoVersion,
  GuidedStep,
  HardwareInventory,
  HomelabSecretsProfile,
  HomelabSecretsUploadResult,
  RunInfo,
  ScriptCatalog,
  ScriptCatalogGroup,
  ScriptCatalogItem,
  ScriptCategory,
  ScriptState,
  StepState,
  SupportBundle,
  SupportBundleDownloadResult,
  TrueNasIsoSelection
} from '../../shared/types';

type TabKey = 'connection' | 'install' | 'scripts' | 'hardware' | 'secrets' | 'health' | 'repair' | 'branding' | 'packages' | 'support';
type ScriptCategoryFilter = ScriptCategory | 'all';

type RemotePayloadStatus = AgentPayloadMetadata & {
  manifest?: AgentPayloadMetadata;
};

const tabs: Array<{ key: TabKey; label: string; icon: typeof Cable }> = [
  { key: 'connection', label: 'Connection', icon: Cable },
  { key: 'install', label: 'Install', icon: ClipboardList },
  { key: 'scripts', label: 'Scripts', icon: ListChecks },
  { key: 'hardware', label: 'Hardware', icon: Cpu },
  { key: 'secrets', label: 'Secrets', icon: KeyRound },
  { key: 'health', label: 'Health', icon: HeartPulse },
  { key: 'repair', label: 'Repair', icon: Wrench },
  { key: 'branding', label: 'Branding', icon: Paintbrush },
  { key: 'packages', label: 'Packages', icon: Package },
  { key: 'support', label: 'Support', icon: LifeBuoy }
];

const runTerminalStatuses = new Set<RunInfo['status']>(['done', 'failed', 'cancelled']);

function delay(ms: number): Promise<void> {
  return new Promise((resolve) => window.setTimeout(resolve, ms));
}

const fallbackProfile: ConnectionProfile = {
  id: 'default-proxmox',
  name: 'Bacmaster Proxmox',
  host: '192.168.50.100',
  port: 22,
  username: 'root',
  agentPort: 48114,
  repoUrl: 'https://github.com/bacproxmox/homelabv4.git',
  repoRef: 'main',
  createdAt: new Date().toISOString(),
  updatedAt: new Date().toISOString()
};

function assetPath(path: string | undefined, fallback = './branding/source/bacmaster-logo.png'): string {
  if (!path) return fallback;
  return path.startsWith('/') ? `.${path}` : path;
}

function homelabSecretsReady(secrets: HomelabSecretsProfile | null): boolean {
  if (!secrets) return false;
  const required = [
    secrets.users.bacmasterPass,
    secrets.users.tulumbaPass,
    secrets.users.mediaPass,
    secrets.users.backupPass,
    secrets.users.atlonPass,
    secrets.users.elifezelPass,
    secrets.truenas.adminPassword
  ];
  return required.every((value) => value.trim()) && chiaMnemonicWordCount(secrets.chia.mnemonic) === 24;
}

function supportBundleFromRunLog(log: string): SupportBundle | null {
  const match = /Support bundle:\s*(\/root\/(?:homelabv4-support|homelab-support)-[^\s]+?\.tar\.gz)/i.exec(log);
  if (!match) return null;
  const path = match[1];
  return {
    path,
    fileName: path.split('/').pop() ?? 'homelabv4-support.tar.gz',
    sizeBytes: 0,
    modifiedAt: new Date().toISOString()
  };
}

function isReconnectableAgentError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return /Agent tunnel is not open|Reopen Tunnel|connection.*closed|Connection refused|fetch failed|aborted/i.test(message);
}

function App(): JSX.Element {
  const [activeTab, setActiveTab] = useState<TabKey>('connection');
  const [profile, setProfile] = useState<ConnectionProfile>(fallbackProfile);
  const [secret, setSecret] = useState<ConnectionSecret>({});
  const [secretsProfile, setSecretsProfile] = useState<HomelabSecretsProfile | null>(null);
  const [secretsUpload, setSecretsUpload] = useState<HomelabSecretsUploadResult | null>(null);
  const [agentHealth, setAgentHealth] = useState<AgentHealth | null>(null);
  const [statusLine, setStatusLine] = useState('Agent tunnel is not open.');
  const [busy, setBusy] = useState(false);
  const [steps, setSteps] = useState<GuidedStep[]>([]);
  const [stepState, setStepState] = useState<StepState[]>([]);
  const [scriptState, setScriptState] = useState<ScriptState[]>([]);
  const [scriptCatalog, setScriptCatalog] = useState<ScriptCatalog>(bundledScriptCatalog as ScriptCatalog);
  const [scriptCategory, setScriptCategory] = useState<ScriptCategoryFilter>('all');
  const [scriptSearch, setScriptSearch] = useState('');
  const [runs, setRuns] = useState<RunInfo[]>([]);
  const [hardware, setHardware] = useState<HardwareInventory | null>(null);
  const [brandingPacks, setBrandingPacks] = useState<BrandingPack[]>([]);
  const [selectedRunId, setSelectedRunId] = useState<string | null>(null);
  const [selectedRunLog, setSelectedRunLog] = useState('');
  const [trueNasIso, setTrueNasIso] = useState<TrueNasIsoSelection | null>(null);
  const [trueNasIsoOverride, setTrueNasIsoOverride] = useState(false);
  const [githubOwner, setGithubOwner] = useState('bacproxmox');
  const [githubToken, setGithubToken] = useState('');
  const [githubTokenSaved, setGithubTokenSaved] = useState(false);
  const [githubRepos, setGithubRepos] = useState<GithubRepoVersion[]>([]);
  const [selectedGithubRepo, setSelectedGithubRepo] = useState<GithubRepoVersion | null>(null);
  const [githubPackage, setGithubPackage] = useState<GithubPackageSelection | null>(null);
  const [githubRepoName, setGithubRepoName] = useState('homelabv4.1');
  const [githubBranch, setGithubBranch] = useState('main');
  const [githubRepoDescription, setGithubRepoDescription] = useState('Homelabv4 source package published from Windows panel.');
  const [githubRepoPrivate, setGithubRepoPrivate] = useState(false);
  const [githubReplaceContents, setGithubReplaceContents] = useState(true);
  const [githubPublishResult, setGithubPublishResult] = useState<GithubRepoPublishResult | null>(null);
  const [supportBundles, setSupportBundles] = useState<SupportBundle[]>([]);
  const [supportDownload, setSupportDownload] = useState<SupportBundleDownloadResult | null>(null);

  useEffect(() => {
    void window.homelab.loadProfile().then((saved) => {
      if (saved) setProfile(saved);
    });
    void window.homelab.loadGithubSettings().then((settings) => {
      setGithubOwner(settings.owner || 'bacproxmox');
      setGithubTokenSaved(Boolean(settings.tokenSaved));
    });
    void window.homelab.loadHomelabSecrets().then((saved) => {
      setSecretsProfile(saved);
      if (saved.truenas.adminPassword) {
        setSecret((current) => ({ ...current, trueNasAdminPassword: saved.truenas.adminPassword }));
      }
    });
    void window.homelab.readBundledBrandingPacks().then(setBrandingPacks).catch(() => undefined);
  }, []);

  const stepStatusById = useMemo(() => new Map(stepState.map((s) => [s.id, s.status])), [stepState]);
  const fullInstallGroup = useMemo(() => scriptCatalog.groups.find((group) => group.id === 'full-install') ?? null, [scriptCatalog]);
  const chiaDbBootstrapItem = useMemo(() => scriptCatalog.items.find((item) => item.id === 'service.chia_db_bootstrap_start') ?? null, [scriptCatalog]);
  const activeRun = useMemo(() => runs.find((run) => run.status === 'running' || run.status === 'queued') ?? null, [runs]);
  const failedStep = useMemo(() => steps.find((step) => stepStatusById.get(step.id) === 'failed') ?? null, [steps, stepStatusById]);
  const runningStep = useMemo(() => steps.find((step) => stepStatusById.get(step.id) === 'running') ?? null, [steps, stepStatusById]);
  const nextStep = useMemo(
    () => steps.find((step) => !['done', 'skipped'].includes(stepStatusById.get(step.id) ?? 'pending')) ?? null,
    [steps, stepStatusById]
  );
  const secretsReady = useMemo(() => homelabSecretsReady(secretsProfile), [secretsProfile]);

  const completedWeight = useMemo(() => {
    const total = steps.reduce((sum, step) => sum + step.weight, 0);
    const done = steps.reduce((sum, step) => {
      const status = stepStatusById.get(step.id);
      return status === 'done' || status === 'skipped' ? sum + step.weight : sum;
    }, 0);
    return total > 0 ? Math.round((done / total) * 100) : 0;
  }, [steps, stepStatusById]);

  const completedStepCount = useMemo(() => {
    return steps.filter((step) => {
      const status = stepStatusById.get(step.id);
      return status === 'done' || status === 'skipped';
    }).length;
  }, [steps, stepStatusById]);

  useEffect(() => {
    if (!agentHealth?.ok) return undefined;
    const shouldPoll = activeTab === 'install' || activeTab === 'scripts' || Boolean(activeRun);
    if (!shouldPoll) return undefined;
    const interval = window.setInterval(() => {
      void refreshAgent().catch(() => undefined);
    }, activeRun ? 2500 : 6500);
    return () => window.clearInterval(interval);
  }, [activeRun, activeTab, agentHealth?.ok, selectedRunId]);

  async function runAction<T>(label: string, action: () => Promise<T>): Promise<T | undefined> {
    setBusy(true);
    setStatusLine(`${label}...`);
    try {
      const result = await action();
      setStatusLine(`${label} completed.`);
      return result;
    } catch (error) {
      setStatusLine(error instanceof Error ? error.message : String(error));
      return undefined;
    } finally {
      setBusy(false);
    }
  }

  async function agentRequest<T>(path: string, options?: AgentRequestOptions): Promise<T> {
    try {
      return await window.homelab.agentRequest<T>(path, options);
    } catch (error) {
      if (!isReconnectableAgentError(error)) {
        throw error;
      }
      await window.homelab.openTunnel(profile, secret);
      setStatusLine('Agent tunnel reconnected.');
      return window.homelab.agentRequest<T>(path, options);
    }
  }

  async function refreshAgent(): Promise<void> {
    const health = await agentRequest<AgentHealth>('/api/v1/health');
    setAgentHealth(health);
    const manifest = await agentRequest<{ steps: GuidedStep[] }>('/api/v1/manifest');
    setSteps(manifest.steps);
    const catalog = await agentRequest<ScriptCatalog>('/api/v1/script-catalog');
    setScriptCatalog(catalog);
    const state = await agentRequest<{
      steps: StepState[];
      scripts?: ScriptState[];
      runs: RunInfo[];
      installProfile?: { truenasIso?: TrueNasIsoSelection };
    }>(
      '/api/v1/state'
    );
    setStepState(state.steps);
    setScriptState(state.scripts ?? []);
    setRuns(state.runs);
    const preferredRun = (selectedRunId ? state.runs.find((run) => run.id === selectedRunId) : null) ?? state.runs.find((run) => run.status === 'running' || run.status === 'queued') ?? state.runs[0];
    if (preferredRun) {
      setSelectedRunId(preferredRun.id);
      await refreshRunLog(preferredRun.id, { quiet: true });
    } else {
      setSelectedRunId(null);
      setSelectedRunLog('');
    }
    if (state.installProfile?.truenasIso) {
      setTrueNasIso(state.installProfile.truenasIso);
      setTrueNasIsoOverride(Boolean(state.installProfile.truenasIso.uploaded) || state.installProfile.truenasIso.warnings.length === 0);
    }
    try {
      const packs = await agentRequest<{ packs: BrandingPack[] }>('/api/v1/branding/packs');
      setBrandingPacks(packs.packs);
    } catch (error) {
      setStatusLine(`Branding packs refresh skipped: ${error instanceof Error ? error.message : String(error)}`);
    }
  }

  async function startRun(target: string): Promise<RunInfo> {
    const run = await agentRequest<RunInfo>('/api/v1/runs', {
      method: 'POST',
      body: { target }
    });
    setRuns((current) => [run, ...current.filter((item) => item.id !== run.id)]);
    setSelectedRunId(run.id);
    setSelectedRunLog('');
    void refreshRunLog(run.id);
    return run;
  }

  async function startScript(item: ScriptCatalogItem): Promise<void> {
    if (item.id === 'vm.vm101_truenas' && !trueNasIso?.uploaded) {
      setStatusLine('Upload the TrueNAS auto-install ISO before running VM101.');
      return;
    }
    const run = await agentRequest<RunInfo>('/api/v1/script-catalog/runs', {
      method: 'POST',
      body: { id: item.id }
    });
    setRuns((current) => [run, ...current.filter((entry) => entry.id !== run.id)]);
    setSelectedRunId(run.id);
    setSelectedRunLog('');
    void refreshRunLog(run.id);
  }

  async function assertAgentPayloadFresh(): Promise<void> {
    const local = await window.homelab.localAgentPayload();
    let remote: RemotePayloadStatus;
    try {
      remote = await agentRequest<RemotePayloadStatus>('/api/v1/payload', { timeoutMs: 120_000 });
    } catch (error) {
      const detail = error instanceof Error ? error.message : String(error);
      const message = `Agent payload outdated or too old to verify. Bootstrap Agent first. Local ${shortHash(local.payloadHash)}. ${detail}`;
      setStatusLine(message);
      throw new Error(message);
    }
    const remoteHash = remote.payloadHash || remote.manifest?.payloadHash;
    if (!remoteHash || remoteHash !== local.payloadHash) {
      const message = `Agent payload outdated. Bootstrap Agent first. Local ${shortHash(local.payloadHash)}, remote ${shortHash(remoteHash)}.`;
      setStatusLine(message);
      throw new Error(message);
    }
  }

  async function startScriptGroup(group: ScriptCatalogGroup): Promise<void> {
    if (group.itemIds.includes('vm.vm101_truenas') && !trueNasIso?.uploaded) {
      setStatusLine('Upload the TrueNAS auto-install ISO before running a group that includes VM101.');
      return;
    }
    if (group.id === 'full-install') {
      await assertAgentPayloadFresh();
    }
    const run = await agentRequest<RunInfo>(`/api/v1/script-catalog/groups/${group.id}/run`, {
      method: 'POST'
    });
    setRuns((current) => [run, ...current.filter((entry) => entry.id !== run.id)]);
    setSelectedRunId(run.id);
    setSelectedRunLog('');
    void refreshRunLog(run.id);
  }

  async function startFullInstall(): Promise<void> {
    if (!fullInstallGroup) {
      throw new Error('Full install group is not available in the script catalog.');
    }
    await startScriptGroup(fullInstallGroup);
  }

  async function resetInstallState(): Promise<void> {
    const state = await window.homelab.resetInstallState(profile, secret);
    setStepState(state.steps);
    setScriptState(state.scripts);
    setRuns(state.runs);
    setSelectedRunId(null);
    setSelectedRunLog(
      `Install state was reset${state.fallback === 'ssh' ? ' through SSH fallback' : ''}. Previous run logs are still available in Runs & Logs.`
    );
    await refreshAgent();
  }

  async function refreshSupportBundles(): Promise<void> {
    const result = await window.homelab.listSupportBundles(profile, secret);
    setSupportBundles(result.bundles);
  }

  async function waitForRunCompletion(runId: string, timeoutMs = 5 * 60 * 1000): Promise<RunInfo> {
    const deadline = Date.now() + timeoutMs;
    while (Date.now() < deadline) {
      await delay(2500);
      const state = await agentRequest<{ runs: RunInfo[] }>('/api/v1/state');
      setRuns(state.runs);
      const run = state.runs.find((item) => item.id === runId);
      if (run) {
        setSelectedRunId(run.id);
        void refreshRunLog(run.id);
        if (runTerminalStatuses.has(run.status)) {
          return run;
        }
      }
    }
    throw new Error('Support bundle did not finish within 5 minutes.');
  }

  async function createSupportBundle(): Promise<void> {
    const knownBundlePaths = new Set(supportBundles.map((bundle) => bundle.path));
    const run = await startRun('tasks/support/create-support-bundle.sh');
    const completedRun = await waitForRunCompletion(run.id);
    if (completedRun.status !== 'done') {
      throw new Error(`Create support bundle ${completedRun.status}.`);
    }

    const finalLog = await agentRequest<{ text: string }>(`/api/v1/runs/${run.id}/logs`)
      .then((result) => result.text)
      .catch(() => selectedRunLog);
    setSelectedRunLog(finalLog);

    let refreshedBundles: SupportBundle[] = [];
    let listError: unknown;
    try {
      const refreshed = await window.homelab.listSupportBundles(profile, secret);
      refreshedBundles = refreshed.bundles;
    } catch (error) {
      listError = error;
    }

    const logBundle = supportBundleFromRunLog(finalLog);
    const bundle =
      refreshedBundles.find((item) => !knownBundlePaths.has(item.path)) ??
      (logBundle ? refreshedBundles.find((item) => item.path === logBundle.path) : undefined) ??
      logBundle ??
      refreshedBundles[0];
    if (!bundle) {
      const detail = listError instanceof Error ? ` ${listError.message}` : '';
      throw new Error(`Support bundle completed, but no bundle was listed or found in the run log.${detail}`);
    }

    const visibleBundles =
      logBundle && !refreshedBundles.some((item) => item.path === logBundle.path) ? [logBundle, ...refreshedBundles] : refreshedBundles;
    setSupportBundles(visibleBundles.length > 0 ? visibleBundles : [bundle]);

    const result = await window.homelab.downloadSupportBundleToRemoteLogs(profile, secret, bundle, {
      runId: run.id,
      runLog: finalLog
    });
    setSupportDownload(result);
    await refreshSupportBundles().catch(() => undefined);
  }

  async function downloadSupportBundle(bundle: SupportBundle): Promise<void> {
    const result = await window.homelab.downloadSupportBundle(profile, secret, bundle);
    if (result) {
      setSupportDownload(result);
    }
  }

  async function openRemoteLogs(): Promise<void> {
    await window.homelab.openRemoteLogsFolder();
  }

  async function runGuidedStep(step: GuidedStep): Promise<void> {
    if (step.id === 'truenas' && !trueNasIso?.uploaded) {
      setStatusLine('Select and upload a TrueNAS auto-install ISO before running VM101.');
      return;
    }
    await startRun(step.target);
  }

  async function selectTrueNasIso(): Promise<void> {
    const selected = await window.homelab.selectTrueNasIso();
    if (!selected) return;
    setTrueNasIso(selected);
    setTrueNasIsoOverride(selected.warnings.length === 0);
  }

  async function uploadTrueNasIso(): Promise<void> {
    if (!trueNasIso) {
      throw new Error('Select a TrueNAS ISO first.');
    }
    if (trueNasIso.warnings.length > 0 && !trueNasIsoOverride) {
      throw new Error('Review the ISO warnings and enable manual override before upload.');
    }
    const uploaded = await window.homelab.uploadTrueNasIso(profile, secret, trueNasIso);
    setTrueNasIso(uploaded);
    setTrueNasIsoOverride(true);
  }

  function updateSecretsProfile(next: HomelabSecretsProfile): void {
    setSecretsProfile(next);
    if (next.truenas.adminPassword) {
      setSecret((current) => ({ ...current, trueNasAdminPassword: next.truenas.adminPassword }));
    }
  }

  async function saveHomelabSecrets(): Promise<void> {
    if (!secretsProfile) {
      throw new Error('Secrets profile is still loading.');
    }
    const saved = await window.homelab.saveHomelabSecrets(secretsProfile);
    updateSecretsProfile(saved);
  }

  async function uploadHomelabSecrets(): Promise<void> {
    if (!secretsProfile) {
      throw new Error('Secrets profile is still loading.');
    }
    const uploaded = await window.homelab.uploadHomelabSecrets(profile, secret, secretsProfile);
    setSecretsUpload(uploaded);
    const saved = await window.homelab.loadHomelabSecrets();
    updateSecretsProfile(saved);
  }

  function selectGithubRepo(repo: GithubRepoVersion): void {
    setSelectedGithubRepo(repo);
    setGithubOwner(repo.owner);
    setGithubRepoName(repo.repo);
    setGithubRepoDescription(`${repo.versionLabel} source package published from Windows panel.`);
  }

  async function saveGithubSettings(): Promise<void> {
    const saved = await window.homelab.saveGithubSettings({
      owner: githubOwner,
      token: githubToken || undefined
    });
    setGithubOwner(saved.owner);
    setGithubToken('');
    setGithubTokenSaved(Boolean(saved.tokenSaved));
  }

  async function scanGithubRepos(): Promise<void> {
    const repos = await window.homelab.listGithubHomelabRepos({
      owner: githubOwner,
      token: githubToken || undefined
    });
    setGithubRepos(repos);
    if (!selectedGithubRepo && repos[0]) {
      selectGithubRepo(repos[0]);
    }
  }

  function inferReleaseFromPackage(fileName: string): void {
    const match = /(homelabv\d+(?:\.\d+){0,3}(?:-r\d+)?)/i.exec(fileName);
    if (!match) return;
    const repoName = match[1].toLowerCase();
    setGithubRepoName(repoName);
    setGithubRepoDescription(`Homelab${repoName.slice('homelab'.length)} source package published from Windows panel.`);
  }

  async function selectGithubPackage(): Promise<void> {
    const selected = await window.homelab.selectGithubPackage();
    if (!selected) return;
    setGithubPackage(selected);
    inferReleaseFromPackage(selected.fileName);
    setGithubPublishResult(null);
  }

  async function publishGithubPackageToRepo(): Promise<void> {
    if (!githubPackage) {
      throw new Error('Select a .zip package file first.');
    }
    if (!githubPackage.fileName.toLowerCase().endsWith('.zip')) {
      throw new Error('Creating/updating a GitHub source repo requires a .zip package.');
    }
    const result = await window.homelab.publishGithubRepoFromPackage({
      owner: githubOwner,
      repo: githubRepoName,
      token: githubToken || undefined,
      packagePath: githubPackage.localPath,
      branch: githubBranch,
      description: githubRepoDescription,
      private: githubRepoPrivate,
      replaceContents: githubReplaceContents,
      stripSingleRootDirectory: true,
      commitMessage: `Publish ${githubPackage.fileName}`
    });
    setGithubToken('');
    setGithubTokenSaved(true);
    setGithubPublishResult(result);
  }

  async function refreshRunLog(runId: string, options?: { quiet?: boolean }): Promise<void> {
    try {
      const log = await agentRequest<{ text: string }>(`/api/v1/runs/${runId}/logs`, { timeoutMs: 10_000 });
      setSelectedRunId(runId);
      setSelectedRunLog(log.text);
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      setSelectedRunId(runId);
      setStatusLine(`Log refresh failed: ${message}`);
      if (!options?.quiet && !selectedRunLog) {
        setSelectedRunLog(`Log refresh failed.\n${message}`);
      }
    }
  }

  async function quickCheckAgent(): Promise<boolean> {
    try {
      await window.homelab.openTunnel(profile, secret);
      const health = await agentRequest<AgentHealth>('/api/v1/health');
      setAgentHealth(health);
      if (health.ok) {
        await refreshAgent();
      }
      return health.ok;
    } catch {
      return false;
    }
  }

  async function loadRemoteTrueNasIso(): Promise<TrueNasIsoSelection | null> {
    try {
      const state = await agentRequest<{ installProfile?: { truenasIso?: TrueNasIsoSelection } }>('/api/v1/state');
      const remoteIso = state.installProfile?.truenasIso ?? null;
      if (remoteIso) {
        setTrueNasIso(remoteIso);
        setTrueNasIsoOverride(Boolean(remoteIso.uploaded) || remoteIso.warnings.length === 0);
      }
      return remoteIso;
    } catch {
      return trueNasIso;
    }
  }

  async function smartFreshInstall(): Promise<void> {
    setStatusLine('Smart install: testing SSH...');
    const ssh = await window.homelab.testSsh(profile, secret);
    if (!ssh.ok) {
      throw new Error(`SSH test failed. ${ssh.output}`);
    }

    setStatusLine('Smart install: checking existing agent...');
    let agentReady = await quickCheckAgent();
    if (!agentReady) {
      setStatusLine('Smart install: bootstrapping agent payload...');
      const bootstrap = await window.homelab.bootstrapAgent(profile, secret);
      if (!bootstrap.ok) {
        throw new Error(bootstrap.output || 'Agent bootstrap failed.');
      }
      setStatusLine('Smart install: opening agent tunnel...');
      agentReady = await quickCheckAgent();
      if (!agentReady) {
        throw new Error('Agent bootstrap finished, but the agent health check did not respond.');
      }
    }

    setStatusLine('Smart install: verifying agent payload version...');
    await assertAgentPayloadFresh();

    setStatusLine('Smart install: checking Windows secrets...');
    const savedSecrets = secretsProfile ?? (await window.homelab.loadHomelabSecrets());
    updateSecretsProfile(savedSecrets);
    if (!homelabSecretsReady(savedSecrets)) {
      setActiveTab('secrets');
      throw new Error('Secrets profile is incomplete. Fill Secrets, save it, then press Smart Install again.');
    }

    setStatusLine('Smart install: uploading secrets to Proxmox...');
    const uploadedSecrets = await window.homelab.uploadHomelabSecrets(profile, secret, savedSecrets);
    setSecretsUpload(uploadedSecrets);

    setStatusLine('Smart install: checking TrueNAS ISO...');
    const remoteIso = await loadRemoteTrueNasIso();
    if (!remoteIso?.uploaded) {
      setActiveTab('install');
      throw new Error('TrueNAS ISO is not uploaded yet. Select/upload the ISO, then press Smart Install again.');
    }

    setActiveTab('install');
    setStatusLine('Smart install: starting full install...');
    await startFullInstall();
  }

  return (
    <div className="app-shell">
      <aside className="sidebar">
        <div className="brand-lockup">
          <img src={assetPath('/branding/source/bacmaster-logo.png')} alt="Bacmaster" />
          <div>
            <strong>Homelabv4</strong>
            <span>Windows Control Panel</span>
          </div>
        </div>
        <nav className="nav-list">
          {tabs.map((tab) => {
            const Icon = tab.icon;
            return (
              <button key={tab.key} className={activeTab === tab.key ? 'active' : ''} onClick={() => setActiveTab(tab.key)}>
                <Icon size={18} />
                <span>{tab.label}</span>
              </button>
            );
          })}
        </nav>
        <button className="sidebar-primary" disabled={busy} onClick={() => void runAction('Smart install', smartFreshInstall)}>
          <Play size={18} />
          <span>Smart Install</span>
        </button>
        <div className="agent-tile">
          <span className={agentHealth?.ok ? 'pulse ok' : 'pulse'} />
          <div>
            <strong>{agentHealth?.ok ? 'Agent online' : 'Agent offline'}</strong>
            <span>{agentHealth?.hostname ?? profile.host}</span>
            {agentHealth?.payloadManifest?.payloadHash && <small>payload {shortHash(agentHealth.payloadManifest.payloadHash)}</small>}
          </div>
        </div>
      </aside>

      <main className="workspace">
        <header className="topbar">
          <div>
            <span className="eyebrow">Bacmaster Homelab</span>
            <h1>{tabs.find((tab) => tab.key === activeTab)?.label}</h1>
          </div>
          <div className="status-strip">
            <Activity size={16} />
            <span>{statusLine}</span>
          </div>
        </header>

        {activeTab === 'connection' && (
          <section className="panel-grid two">
            <div className="section-panel">
              <h2>Proxmox Connection</h2>
              <div className="form-grid">
                <label>
                  Host
                  <input value={profile.host} onChange={(event) => setProfile({ ...profile, host: event.target.value })} />
                </label>
                <label>
                  SSH Port
                  <input
                    type="number"
                    value={profile.port}
                    onChange={(event) => setProfile({ ...profile, port: Number(event.target.value) || 22 })}
                  />
                </label>
                <label>
                  Agent Port
                  <input
                    type="number"
                    value={profile.agentPort}
                    onChange={(event) => setProfile({ ...profile, agentPort: Number(event.target.value) || 48114 })}
                  />
                </label>
                <label>
                  Root Password
                  <input
                    type="password"
                    value={secret.password ?? ''}
                    onChange={(event) => setSecret({ ...secret, password: event.target.value })}
                    placeholder="Stored with OS-backed encryption"
                  />
                </label>
                <label className="span-2">
                  Repository
                  <input value={profile.repoUrl} onChange={(event) => setProfile({ ...profile, repoUrl: event.target.value })} />
                </label>
                <label>
                  Ref
                  <input value={profile.repoRef} onChange={(event) => setProfile({ ...profile, repoRef: event.target.value })} />
                </label>
              </div>
              <div className="actions">
                <button onClick={() => void runAction('Save profile', () => window.homelab.saveProfile(profile, secret))}>
                  <ShieldCheck size={17} />
                  Save
                </button>
                <button onClick={() => void runAction('Test SSH', () => window.homelab.testSsh(profile, secret))}>
                  <TerminalSquare size={17} />
                  Test SSH
                </button>
                <button onClick={() => void runAction('Bootstrap agent', () => window.homelab.bootstrapAgent(profile, secret))}>
                  <Download size={17} />
                  Bootstrap Agent
                </button>
                <button
                  onClick={() =>
                    void runAction('Open tunnel', async () => {
                      await window.homelab.openTunnel(profile, secret);
                      await refreshAgent();
                    })
                  }
                >
                  <Cable size={17} />
                  Open Tunnel
                </button>
              </div>
            </div>
            <div className="section-panel quiet">
              <h2>Bootstrap Flow</h2>
              <ol className="process-list">
                <li>Connect with fresh Proxmox root password.</li>
                <li>Upload `/opt/homelabv4/agent` payload.</li>
                <li>Install `homelab-agent.service` on localhost only.</li>
                <li>Open SSH tunnel to the agent API.</li>
                <li>Continue with install, health, repair, support and branding.</li>
              </ol>
            </div>
          </section>
        )}

        {activeTab === 'install' && (
          <section className="panel-grid">
            <div className="install-stack">
              <FullInstallPanel
                completedWeight={completedWeight}
                completedStepCount={completedStepCount}
                totalStepCount={steps.length}
                isoReady={Boolean(trueNasIso?.uploaded)}
                secretsReady={secretsReady}
                busy={busy}
                activeRun={activeRun}
                failedStep={failedStep}
                runningStep={runningStep}
                nextStep={nextStep}
                onStart={() => runAction('Start full install', startFullInstall)}
                onRefresh={() => runAction('Refresh agent state', refreshAgent)}
                onReset={() => runAction('Reset install state', resetInstallState)}
              />
              <TrueNasIsoPanel
                iso={trueNasIso}
                secret={secret}
                overrideWarnings={trueNasIsoOverride}
                busy={busy}
                onSecretChange={(nextSecret) => {
                  setSecret(nextSecret);
                  if (secretsProfile && nextSecret.trueNasAdminPassword !== undefined) {
                    updateSecretsProfile({
                      ...secretsProfile,
                      truenas: { ...secretsProfile.truenas, adminPassword: nextSecret.trueNasAdminPassword }
                    });
                  }
                }}
                onOverrideChange={setTrueNasIsoOverride}
                onSelect={() => runAction('Select TrueNAS ISO', selectTrueNasIso)}
                onUpload={() => runAction('Upload TrueNAS ISO', uploadTrueNasIso)}
              />
              <ChiaDeferredPanel
                item={chiaDbBootstrapItem}
                status={scriptState.find((state) => state.id === 'service.chia_db_bootstrap_start')?.status ?? 'pending'}
                busy={busy}
                onRun={() => {
                  if (!chiaDbBootstrapItem) return;
                  return runAction('Copy Chia DB from tank & Start', () => startScript(chiaDbBootstrapItem));
                }}
              />
              <div className="section-panel">
                <div className="section-head">
                  <div>
                    <h2>Guided Install</h2>
                    <p>{completedWeight}% complete</p>
                  </div>
                  <button onClick={() => void runAction('Refresh agent state', refreshAgent)}>
                    <RotateCcw size={17} />
                    Refresh
                  </button>
                </div>
                <div className="progress-track">
                  <span style={{ width: `${completedWeight}%` }} />
                </div>
                <div className="step-list">
                  {steps.map((step) => {
                    const status = stepState.find((item) => item.id === step.id)?.status ?? 'pending';
                    return (
                      <div className="step-row" key={step.id}>
                        <span className={`state-dot ${status}`} />
                        <div>
                          <strong>{step.title}</strong>
                          <span>{step.target}</span>
                        </div>
                        {step.destructive && <em>Fresh wipe</em>}
                        {step.id === 'truenas' && <em>{trueNasIso?.uploaded ? 'auto ISO ready' : 'ISO required'}</em>}
                        <button onClick={() => void runAction(`Run ${step.id}`, () => runGuidedStep(step))}>
                          <Play size={15} />
                        </button>
                      </div>
                    );
                  })}
                </div>
              </div>
            </div>
            <RunConsole runs={runs} selectedRunId={selectedRunId} log={selectedRunLog} onRefreshLog={refreshRunLog} />
          </section>
        )}

        {activeTab === 'scripts' && (
          <section className="panel-grid">
            <ScriptCenter
              catalog={scriptCatalog}
              states={scriptState}
              category={scriptCategory}
              search={scriptSearch}
              busy={busy}
              onCategoryChange={setScriptCategory}
              onSearchChange={setScriptSearch}
              onRefresh={() => runAction('Refresh script catalog', refreshAgent)}
              onRunItem={(item) => runAction(`Run ${item.title}`, () => startScript(item))}
              onRunGroup={(group) => runAction(`Run ${group.title}`, () => startScriptGroup(group))}
            />
            <RunConsole runs={runs} selectedRunId={selectedRunId} log={selectedRunLog} onRefreshLog={refreshRunLog} />
          </section>
        )}

        {activeTab === 'hardware' && (
          <section className="panel-grid two">
            <div className="section-panel">
              <div className="section-head">
                <div>
                  <h2>Hardware Inventory</h2>
                  <p>NVMe, SATA, GPU and passthrough discovery.</p>
                </div>
                <button
                  onClick={() =>
                    void runAction('Collect hardware inventory', async () => {
                      const inventory = await agentRequest<HardwareInventory>('/api/v1/inventory/hardware');
                      setHardware(inventory);
                    })
                  }
                >
                  <HardDrive size={17} />
                  Collect
                </button>
              </div>
              <pre className="terminal-output">{hardware ? hardware.lsblk : 'No inventory collected yet.'}</pre>
            </div>
            <div className="section-panel">
              <h2>Passthrough Signals</h2>
              <pre className="terminal-output compact">{hardware ? `${hardware.nvme}\n\n${hardware.pci}\n\n${hardware.storage}\n\nVM Resources\n${hardware.vmResources}` : 'Open the tunnel, then collect inventory.'}</pre>
            </div>
          </section>
        )}

        {activeTab === 'secrets' && (
          <SecretsPanel
            secrets={secretsProfile}
            uploadResult={secretsUpload}
            busy={busy}
            onChange={updateSecretsProfile}
            onSave={() => runAction('Save secrets', saveHomelabSecrets)}
            onUpload={() => runAction('Upload secrets', uploadHomelabSecrets)}
          />
        )}

        {activeTab === 'health' && (
          <ActionPanel
            icon={HeartPulse}
            title="Health Checks"
            text="Run the allowlisted full health task on the Proxmox agent."
            actionLabel="Run Full Health"
            onAction={() => runAction('Run health check', () => startRun('tasks/health/full-health.sh'))}
          />
        )}

        {activeTab === 'repair' && (
          <ActionPanel
            icon={Wrench}
            title="Repair Center"
            text="GPU passthrough, Chia disks, NFS mounts, Cloudflared and service repairs are modeled as allowlisted agent targets."
            actionLabel="Run GPU Repair"
            onAction={() => runAction('Run GPU repair', () => startRun('tasks/repair/gpu-passthrough.sh'))}
          />
        )}

        {activeTab === 'branding' && (
          <section className="section-panel">
            <div className="section-head">
              <div>
                <h2>Bacmaster Branding Packs</h2>
                <p>Apply, inspect and restore service themes from the same Windows panel.</p>
              </div>
              <button onClick={() => void runAction('Refresh branding packs', refreshAgent)}>
                <RotateCcw size={17} />
                Refresh
              </button>
            </div>
            <div className="branding-grid">
              {brandingPacks.map((pack) => (
                <article className="brand-card" key={pack.id}>
                  <div className="brand-preview">
                    <img src={assetPath(pack.assets.wideLogo ?? pack.assets.transparentLogo ?? pack.assets.icon)} alt={pack.displayName} />
                  </div>
                  <div className="brand-body">
                    <span style={{ color: pack.accentColor }}>{pack.service}</span>
                    <strong>{pack.displayName}</strong>
                    <p>{pack.description}</p>
                    <div className="chip-row">
                      <em className={`risk ${pack.riskLevel}`}>{pack.riskLevel}</em>
                      <em>{pack.implementation}</em>
                      {pack.reapplyAfterUpdate && <em>reapply after update</em>}
                    </div>
                    <div className="actions small">
                      <button onClick={() => void runAction(`${pack.displayName} status`, () => startRun(pack.targets.status))}>
                        <BadgeCheck size={15} />
                        Status
                      </button>
                      <button onClick={() => void runAction(`${pack.displayName} apply`, () => startRun(pack.targets.apply))}>
                        <Paintbrush size={15} />
                        Apply
                      </button>
                      <button onClick={() => void runAction(`${pack.displayName} restore`, () => startRun(pack.targets.restore))}>
                        <RotateCcw size={15} />
                        Restore
                      </button>
                    </div>
                  </div>
                </article>
              ))}
            </div>
          </section>
        )}

        {activeTab === 'packages' && (
          <section className="panel-grid">
            <GithubPackagesPanel
              owner={githubOwner}
              token={githubToken}
              tokenSaved={githubTokenSaved}
              repos={githubRepos}
              selectedRepo={selectedGithubRepo}
              packageFile={githubPackage}
              repoName={githubRepoName}
              branch={githubBranch}
              repoDescription={githubRepoDescription}
              repoPrivate={githubRepoPrivate}
              replaceContents={githubReplaceContents}
              publishResult={githubPublishResult}
              busy={busy}
              onOwnerChange={setGithubOwner}
              onTokenChange={setGithubToken}
              onRepoNameChange={setGithubRepoName}
              onBranchChange={setGithubBranch}
              onRepoDescriptionChange={setGithubRepoDescription}
              onRepoPrivateChange={setGithubRepoPrivate}
              onReplaceContentsChange={setGithubReplaceContents}
              onSaveSettings={() => runAction('Save GitHub settings', saveGithubSettings)}
              onScan={() => runAction('Scan GitHub versions', scanGithubRepos)}
              onSelectRepo={selectGithubRepo}
              onSelectPackage={() => runAction('Select package', selectGithubPackage)}
              onPublish={() => runAction('Publish package to GitHub repo', publishGithubPackageToRepo)}
            />
            <div className="section-panel quiet">
              <h2>Package Publishing Flow</h2>
              <ol className="process-list">
                <li>Scan `github.com/bacproxmox/homelabv*` repositories.</li>
                <li>Select an existing version repo or type a new repo name like `homelabv4.1`.</li>
                <li>Select `homelabv4.1.zip`.</li>
                <li>Create the repo if missing and commit the ZIP contents to `main`.</li>
                <li>Use the published repo URL as the bootstrap source when needed.</li>
              </ol>
            </div>
          </section>
        )}

        {activeTab === 'support' && (
          <section className="panel-grid">
            <SupportPanel
              bundles={supportBundles}
              downloadResult={supportDownload}
              busy={busy}
              onCreate={() => runAction('Create support bundle', createSupportBundle)}
              onRefresh={() => runAction('Refresh support bundles', refreshSupportBundles)}
              onDownload={(bundle) => runAction('Download support bundle', () => downloadSupportBundle(bundle))}
              onOpenRemoteLogs={() => runAction('Open Remote-Logs', openRemoteLogs)}
            />
            <RunConsole runs={runs} selectedRunId={selectedRunId} log={selectedRunLog} onRefreshLog={refreshRunLog} />
          </section>
        )}
      </main>
    </div>
  );
}

function formatBytes(bytes: number): string {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  return `${value.toFixed(unit === 0 ? 0 : 1)} ${units[unit]}`;
}

function shortHash(hash?: string): string {
  if (!hash) return 'missing';
  if (hash.length <= 18) return hash;
  return `${hash.slice(0, 10)}...${hash.slice(-8)}`;
}

function chiaMnemonicWordCount(value: string): number {
  return value.trim().split(/\s+/).filter(Boolean).length;
}

function SupportPanel({
  bundles,
  downloadResult,
  busy,
  onCreate,
  onRefresh,
  onDownload,
  onOpenRemoteLogs
}: {
  bundles: SupportBundle[];
  downloadResult: SupportBundleDownloadResult | null;
  busy: boolean;
  onCreate: () => void | Promise<unknown>;
  onRefresh: () => void | Promise<unknown>;
  onDownload: (bundle: SupportBundle) => void | Promise<unknown>;
  onOpenRemoteLogs: () => void | Promise<unknown>;
}): JSX.Element {
  return (
    <div className="section-panel support-panel">
      <div className="section-head">
        <div>
          <h2>Support Bundle</h2>
          <p>Logs, agent state, VM configs and hardware inventory.</p>
        </div>
        <div className="actions inline">
          <button disabled={busy} onClick={() => void onRefresh()}>
            <RotateCcw size={17} />
            Refresh
          </button>
          <button disabled={busy} onClick={() => void onOpenRemoteLogs()}>
            <FolderOpen size={17} />
            Open Remote-Logs
          </button>
          <button className="primary-action" disabled={busy} onClick={() => void onCreate()}>
            <LifeBuoy size={17} />
            Create Bundle
          </button>
        </div>
      </div>

      <div className="support-note">
        <strong>Remote locations</strong>
        <code>/opt/homelabv4/logs/*.log</code>
        <code>/root/homelabv4-support-*.tar.gz</code>
        <strong>Local archive</strong>
        <code>Documents\Homelabv4\Remote-Logs</code>
      </div>

      {downloadResult && (
        <div className="success-block">
          <strong>Downloaded</strong>
          <span>{downloadResult.localPath}</span>
          {downloadResult.summaryPath && (
            <>
              <strong>Summary</strong>
              <span>{downloadResult.summaryPath}</span>
            </>
          )}
        </div>
      )}

      <div className="support-list">
        {bundles.length === 0 && <p>No support bundles listed yet. Create one, then refresh.</p>}
        {bundles.map((bundle) => (
          <div className="support-row" key={bundle.path}>
            <div>
              <strong>{bundle.fileName}</strong>
              <span>{bundle.path}</span>
              <em>{formatBytes(bundle.sizeBytes)} • {new Date(bundle.modifiedAt).toLocaleString()}</em>
            </div>
            <button disabled={busy} onClick={() => void onDownload(bundle)}>
              <Download size={16} />
              Download
            </button>
          </div>
        ))}
      </div>
    </div>
  );
}

function FullInstallPanel({
  completedWeight,
  completedStepCount,
  totalStepCount,
  isoReady,
  secretsReady,
  busy,
  activeRun,
  failedStep,
  runningStep,
  nextStep,
  onStart,
  onRefresh,
  onReset
}: {
  completedWeight: number;
  completedStepCount: number;
  totalStepCount: number;
  isoReady: boolean;
  secretsReady: boolean;
  busy: boolean;
  activeRun: RunInfo | null;
  failedStep: GuidedStep | null;
  runningStep: GuidedStep | null;
  nextStep: GuidedStep | null;
  onStart: () => void | Promise<unknown>;
  onRefresh: () => void | Promise<unknown>;
  onReset: () => void | Promise<unknown>;
}): JSX.Element {
  const isRunning = Boolean(activeRun);
  const blocked = !isoReady;
  const statusLabel = failedStep ? 'Needs attention' : isRunning ? 'Running' : completedWeight >= 100 ? 'Complete' : 'Ready';
  const focusStep = failedStep ?? runningStep ?? nextStep;
  const canStart = !busy && !isRunning && !blocked;

  return (
    <div className="section-panel full-install-panel">
      <div className="section-head">
        <div>
          <h2>Full Homelab Install</h2>
          <p>{completedStepCount}/{totalStepCount || 0} steps, {completedWeight}% complete</p>
        </div>
        <div className="actions inline">
          <button disabled={busy} onClick={() => void onRefresh()}>
            <RotateCcw size={17} />
            Refresh
          </button>
          <button className="danger-action" disabled={busy} onClick={() => void onReset()}>
            <RotateCcw size={17} />
            Reset State
          </button>
          <button className="primary-action" disabled={!canStart} onClick={() => void onStart()}>
            <Play size={17} />
            {isRunning ? 'Running' : 'Start Full Install'}
          </button>
        </div>
      </div>

      <div className="progress-track large">
        <span style={{ width: `${completedWeight}%` }} />
      </div>

      <div className="install-metrics">
        <div>
          <span>Status</span>
          <strong>{statusLabel}</strong>
        </div>
        <div>
          <span>Current</span>
          <strong>{focusStep?.title ?? 'Waiting for manifest'}</strong>
        </div>
        <div>
          <span>Run</span>
          <strong>{activeRun?.title ?? 'No active run'}</strong>
        </div>
      </div>

      {blocked && (
        <div className="warning-block compact-warning">
          <strong>TrueNAS ISO is required</strong>
          <p>Select and upload the Bacmasters-NAS ISO before starting the full install.</p>
        </div>
      )}
      {!secretsReady && (
        <div className="warning-block compact-warning">
          <strong>Secrets are incomplete</strong>
          <p>Fill and upload the Secrets profile before a fresh full install.</p>
        </div>
      )}
      {failedStep && (
        <div className="warning-block compact-warning failed-warning">
          <strong>{failedStep.title} failed</strong>
          <p>{activeRun?.needsRepair ? `${activeRun.needsRepair.title}: ${activeRun.needsRepair.reason}` : 'The latest run log is shown in the Runs & Logs panel.'}</p>
        </div>
      )}
      {activeRun?.needsRepair && !failedStep && (
        <div className="warning-block compact-warning failed-warning">
          <strong>Needs repair</strong>
          <p>{activeRun.needsRepair.title}: {activeRun.needsRepair.reason}</p>
        </div>
      )}
    </div>
  );
}

function TrueNasIsoPanel({
  iso,
  secret,
  overrideWarnings,
  busy,
  onSecretChange,
  onOverrideChange,
  onSelect,
  onUpload
}: {
  iso: TrueNasIsoSelection | null;
  secret: ConnectionSecret;
  overrideWarnings: boolean;
  busy: boolean;
  onSecretChange: (secret: ConnectionSecret) => void;
  onOverrideChange: (enabled: boolean) => void;
  onSelect: () => void | Promise<unknown>;
  onUpload: () => void | Promise<unknown>;
}): JSX.Element {
  const hasWarnings = Boolean(iso?.warnings.length);
  const canUpload = Boolean(iso && secret.trueNasAdminPassword && (!hasWarnings || overrideWarnings));
  const status = iso?.uploaded ? 'Uploaded and SHA256 verified' : iso ? 'Selected on Windows' : 'No ISO selected';
  const defaults = [
    ['VM', '101 / truenas'],
    ['SSH', 'truenas_admin@192.168.50.101'],
    ['MAC', '02:23:14:00:01:01'],
    ['Boot', '64GB disk, 32GB RAM, 4 cores']
  ];

  return (
    <div className="section-panel truenas-iso-panel">
      <div className="section-head">
        <div>
          <h2>TrueNAS Auto ISO</h2>
          <p>{status}</p>
        </div>
        <div className="actions inline">
          <button disabled={busy} onClick={() => void onSelect()}>
            <HardDrive size={17} />
            Select ISO
          </button>
          <button disabled={busy || !canUpload} onClick={() => void onUpload()}>
            <Download size={17} />
            Upload
          </button>
        </div>
      </div>

      <div className="truenas-defaults">
        {defaults.map(([label, value]) => (
          <div key={label}>
            <span>{label}</span>
            <strong>{value}</strong>
          </div>
        ))}
      </div>

      <div className="truenas-secret-row">
        <label>
          TrueNAS Admin Password
          <input
            type="password"
            value={secret.trueNasAdminPassword ?? ''}
            onChange={(event) => onSecretChange({ ...secret, trueNasAdminPassword: event.target.value })}
            placeholder="Must match the password embedded in the auto-install ISO"
          />
        </label>
        <div className="iso-status-badge">
          {iso?.uploaded ? <CheckCircle2 size={17} /> : <Box size={17} />}
          <span>{iso?.uploaded ? 'Ready for VM101 auto install' : 'Waiting for verified upload'}</span>
        </div>
      </div>

      {iso && (
        <div className="iso-detail-grid">
          <div>
            <span>File</span>
            <strong>{iso.fileName}</strong>
          </div>
          <div>
            <span>Size</span>
            <strong>{formatBytes(iso.sizeBytes)}</strong>
          </div>
          <div>
            <span>SHA256</span>
            <strong>{iso.sha256.slice(0, 12)}...{iso.sha256.slice(-10)}</strong>
          </div>
          <div>
            <span>Manifest</span>
            <strong>{iso.manifest ? `${iso.manifest.brand ?? 'Unknown'} ${iso.manifest.sourceVersion ?? ''}` : 'Missing'}</strong>
          </div>
        </div>
      )}

      {hasWarnings && (
        <div className="warning-block">
          <strong>ISO warnings</strong>
          <ul>
            {iso?.warnings.map((warning) => (
              <li key={warning}>{warning}</li>
            ))}
          </ul>
          <label className="checkline">
            <input type="checkbox" checked={overrideWarnings} onChange={(event) => onOverrideChange(event.target.checked)} />
            <span>Allow manual override for this ISO</span>
          </label>
        </div>
      )}

      <div className="fallback-box">
        <strong>Manual fallback</strong>
        <ol>
          <li>Open Proxmox VM101 Console.</li>
          <li>Finish the Bacmasters-NAS / TrueNAS installer manually.</li>
          <li>Make sure SSH is enabled and `truenas_admin` uses the password saved here.</li>
          <li>Run `qm set 101 --delete ide2; qm set 101 --boot order=scsi0; qm start 101` on Proxmox.</li>
          <li>Return to Homelabv4 and run the TrueNAS guided step again.</li>
        </ol>
      </div>
    </div>
  );
}

function ChiaDeferredPanel({
  item,
  status,
  busy,
  onRun
}: {
  item: ScriptCatalogItem | null;
  status: ScriptState['status'];
  busy: boolean;
  onRun: () => void | Promise<unknown>;
}): JSX.Element {
  return (
    <div className="section-panel">
      <div className="section-head">
        <div>
          <h2>Chia Deferred Start</h2>
          <p>Full install prepares VM107, plot mounts and Chia config. DB copy and farmer start run only from this action.</p>
        </div>
        <button className="primary-action" disabled={busy || !item} onClick={() => void onRun()}>
          <Play size={17} />
          Copy Chia DB from tank & Start
        </button>
      </div>
      <div className="install-metrics">
        <div>
          <span>Status</span>
          <strong><span className={`state-dot inline-dot ${status}`} /> {status}</strong>
        </div>
        <div>
          <span>Source</span>
          <strong>/mnt/tank/chia-db</strong>
        </div>
        <div>
          <span>Target</span>
          <strong>VM107 chia-farmer</strong>
        </div>
      </div>
    </div>
  );
}

function ScriptCenter({
  catalog,
  states,
  category,
  search,
  busy,
  onCategoryChange,
  onSearchChange,
  onRefresh,
  onRunItem,
  onRunGroup
}: {
  catalog: ScriptCatalog;
  states: ScriptState[];
  category: ScriptCategoryFilter;
  search: string;
  busy: boolean;
  onCategoryChange: (category: ScriptCategoryFilter) => void;
  onSearchChange: (search: string) => void;
  onRefresh: () => void | Promise<unknown>;
  onRunItem: (item: ScriptCatalogItem) => void | Promise<unknown>;
  onRunGroup: (group: ScriptCatalogGroup) => void | Promise<unknown>;
}): JSX.Element {
  const stateById = new Map(states.map((state) => [state.id, state]));
  const categories: ScriptCategoryFilter[] = ['all', 'install', 'vm', 'service', 'config', 'branding', 'health', 'repair', 'maintenance', 'support', 'additional'];
  const normalizedSearch = search.trim().toLowerCase();
  const filteredItems = catalog.items
    .filter((item) => category === 'all' || item.category === category)
    .filter((item) => {
      if (!normalizedSearch) return true;
      const haystack = [item.title, item.description, item.target, item.category, ...(item.tags ?? [])].join(' ').toLowerCase();
      return haystack.includes(normalizedSearch);
    })
    .sort((a, b) => a.defaultOrder - b.defaultOrder || a.title.localeCompare(b.title));
  const showGroups = category === 'all' && !normalizedSearch;
  const categoryCounts = new Map<ScriptCategoryFilter, number>(categories.map((entry) => [entry, entry === 'all' ? catalog.items.length : 0]));
  for (const item of catalog.items) {
    categoryCounts.set(item.category, (categoryCounts.get(item.category) ?? 0) + 1);
  }

  return (
    <div className="section-panel script-center">
      <div className="section-head">
        <div>
          <h2>Script Center</h2>
          <p>{catalog.items.length} scripts, {catalog.groups.length} run groups</p>
        </div>
        <button onClick={() => void onRefresh()}>
          <RotateCcw size={17} />
          Refresh
        </button>
      </div>

      <div className="script-toolbar">
        <input value={search} onChange={(event) => onSearchChange(event.target.value)} placeholder="Search VM106, Jellyfin, branding, repair..." />
        <div className="category-tabs">
          {categories.map((entry) => (
            <button key={entry} className={category === entry ? 'active' : ''} onClick={() => onCategoryChange(entry)}>
              {entry}
              <span>{categoryCounts.get(entry) ?? 0}</span>
            </button>
          ))}
        </div>
      </div>

      {showGroups && (
        <div className="script-groups">
          {catalog.groups.map((group) => (
            <div className="script-group-row" key={group.id}>
              <div>
                <strong>{group.title}</strong>
                <span>{group.description}</span>
              </div>
              <em className={`risk ${group.riskLevel}`}>{group.riskLevel}</em>
              <button disabled={busy} onClick={() => void onRunGroup(group)}>
                <Play size={15} />
                Run Group
              </button>
            </div>
          ))}
        </div>
      )}

      <div className="script-list">
        {filteredItems.length === 0 && <p>No scripts match the current filter.</p>}
        {filteredItems.map((item) => {
          const status = stateById.get(item.id)?.status ?? 'pending';
          return (
            <div className="script-row" key={item.id}>
              <span className={`state-dot ${status}`} />
              <div className="script-main">
                <strong>{item.title}</strong>
                <span>{item.description}</span>
                <code>{item.target}</code>
              </div>
              <div className="script-meta">
                <em>{item.category}</em>
                <em className={`risk ${item.riskLevel}`}>{item.riskLevel}</em>
                <em>{item.implementation}</em>
              </div>
              <button disabled={busy} onClick={() => void onRunItem(item)}>
                <Play size={15} />
                Run
              </button>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function GithubPackagesPanel({
  owner,
  token,
  tokenSaved,
  repos,
  selectedRepo,
  packageFile,
  repoName,
  branch,
  repoDescription,
  repoPrivate,
  replaceContents,
  publishResult,
  busy,
  onOwnerChange,
  onTokenChange,
  onRepoNameChange,
  onBranchChange,
  onRepoDescriptionChange,
  onRepoPrivateChange,
  onReplaceContentsChange,
  onSaveSettings,
  onScan,
  onSelectRepo,
  onSelectPackage,
  onPublish
}: {
  owner: string;
  token: string;
  tokenSaved: boolean;
  repos: GithubRepoVersion[];
  selectedRepo: GithubRepoVersion | null;
  packageFile: GithubPackageSelection | null;
  repoName: string;
  branch: string;
  repoDescription: string;
  repoPrivate: boolean;
  replaceContents: boolean;
  publishResult: GithubRepoPublishResult | null;
  busy: boolean;
  onOwnerChange: (owner: string) => void;
  onTokenChange: (token: string) => void;
  onRepoNameChange: (name: string) => void;
  onBranchChange: (branch: string) => void;
  onRepoDescriptionChange: (description: string) => void;
  onRepoPrivateChange: (isPrivate: boolean) => void;
  onReplaceContentsChange: (replace: boolean) => void;
  onSaveSettings: () => void | Promise<unknown>;
  onScan: () => void | Promise<unknown>;
  onSelectRepo: (repo: GithubRepoVersion) => void;
  onSelectPackage: () => void | Promise<unknown>;
  onPublish: () => void | Promise<unknown>;
}): JSX.Element {
  const canPublish = Boolean(packageFile && packageFile.fileName.toLowerCase().endsWith('.zip') && repoName.trim() && branch.trim() && (token || tokenSaved));

  return (
    <div className="section-panel github-packages">
      <div className="section-head">
        <div>
          <h2>GitHub Packages</h2>
          <p>Create version repos and commit Homelab ZIP contents.</p>
        </div>
        <div className="actions inline">
          <button disabled={busy} onClick={() => void onScan()}>
            <Github size={17} />
            Scan Versions
          </button>
        </div>
      </div>

      <div className="github-settings">
        <label>
          GitHub Owner
          <input value={owner} onChange={(event) => onOwnerChange(event.target.value)} placeholder="bacproxmox" />
        </label>
        <label>
          Token
          <input
            type="password"
            value={token}
            onChange={(event) => onTokenChange(event.target.value)}
            placeholder={tokenSaved ? 'Token saved in Windows protected storage' : 'GitHub PAT with repo creation and contents write'}
          />
        </label>
        <button disabled={busy} onClick={() => void onSaveSettings()}>
          <ShieldCheck size={17} />
          Save
        </button>
      </div>

      <div className="github-layout">
        <div className="github-version-list">
          <div className="mini-head">
            <strong>Detected Versions</strong>
            <span>{repos.length} repos</span>
          </div>
          {repos.length === 0 && <p>Scan `github.com/{owner}/homelabv*` to list available versions.</p>}
          {repos.map((repo) => (
            <button key={repo.fullName} className={selectedRepo?.fullName === repo.fullName ? 'active' : ''} onClick={() => onSelectRepo(repo)}>
              <div>
                <strong>{repo.versionLabel}</strong>
                <span>{repo.fullName}</span>
              </div>
              <em>{repo.private ? 'private' : 'public'}</em>
            </button>
          ))}
        </div>

        <div className="github-publish-card">
          <div className="mini-head">
            <strong>Repository Source Publish</strong>
            {selectedRepo && (
              <a href={selectedRepo.htmlUrl}>
                <ExternalLink size={14} />
                Selected repo
              </a>
            )}
          </div>

          <div className="form-grid">
            <label>
              Repository Name
              <input value={repoName} onChange={(event) => onRepoNameChange(event.target.value)} placeholder="homelabv4.1" />
            </label>
            <label>
              Branch
              <input value={branch} onChange={(event) => onBranchChange(event.target.value)} placeholder="main" />
            </label>
            <label className="span-2">
              Description
              <input value={repoDescription} onChange={(event) => onRepoDescriptionChange(event.target.value)} />
            </label>
          </div>

          <div className="github-checks">
            <label className="checkline">
              <input type="checkbox" checked={repoPrivate} onChange={(event) => onRepoPrivateChange(event.target.checked)} />
              <span>Keep/create repository as private</span>
            </label>
            <label className="checkline">
              <input type="checkbox" checked={replaceContents} onChange={(event) => onReplaceContentsChange(event.target.checked)} />
              <span>Replace repository contents with ZIP contents</span>
            </label>
          </div>

          <div className="package-file-card">
            <div>
              <Package size={20} />
              <div>
                <strong>{packageFile?.fileName ?? 'No package selected'}</strong>
                <span>{packageFile ? `${formatBytes(packageFile.sizeBytes)} / ${packageFile.sha256.slice(0, 12)}...${packageFile.sha256.slice(-10)}` : 'ZIP package with repository source files'}</span>
              </div>
            </div>
            <button disabled={busy} onClick={() => void onSelectPackage()}>
              <Package size={15} />
              Select Package
            </button>
          </div>

          {packageFile?.warnings.length ? (
            <div className="warning-block">
              <strong>Package warnings</strong>
              <ul>
                {packageFile.warnings.map((warning) => (
                  <li key={warning}>{warning}</li>
                ))}
              </ul>
            </div>
          ) : null}

          <div className="actions">
            <button disabled={busy || !canPublish} onClick={() => void onPublish()}>
              <Upload size={17} />
              Create / Update Repo
            </button>
          </div>

          {publishResult && (
            <div className="upload-result">
              <CheckCircle2 size={18} />
              <div>
                <strong>{publishResult.repoFullName} {publishResult.createdRepo ? 'created' : 'updated'}</strong>
                <span>{publishResult.uploadedFiles} files / {formatBytes(publishResult.totalBytes)} / {publishResult.private ? 'private' : 'public'} / {publishResult.commitSha.slice(0, 12)}</span>
                <a href={publishResult.commitUrl}>
                  <ExternalLink size={14} />
                  Open commit
                </a>
              </div>
            </div>
          )}

          {publishResult?.warnings.length ? (
            <div className="warning-block">
              <strong>Publish warnings</strong>
              <ul>
                {publishResult.warnings.map((warning) => (
                  <li key={warning}>{warning}</li>
                ))}
              </ul>
            </div>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function SecretsPanel({
  secrets,
  uploadResult,
  busy,
  onChange,
  onSave,
  onUpload
}: {
  secrets: HomelabSecretsProfile | null;
  uploadResult: HomelabSecretsUploadResult | null;
  busy: boolean;
  onChange: (secrets: HomelabSecretsProfile) => void;
  onSave: () => void | Promise<unknown>;
  onUpload: () => void | Promise<unknown>;
}): JSX.Element {
  if (!secrets) {
    return <PlaceholderPanel icon={KeyRound} title="Secrets Vault" text="Loading saved Homelab secrets profile." />;
  }

  function updateSection<K extends keyof HomelabSecretsProfile>(section: K, patch: Partial<HomelabSecretsProfile[K]>): void {
    if (!secrets) return;
    onChange({
      ...secrets,
      [section]: {
        ...(secrets[section] as Record<string, unknown>),
        ...patch
      }
    } as HomelabSecretsProfile);
  }

  const mnemonicWords = chiaMnemonicWordCount(secrets.chia.mnemonic);
  const requiredComplete = [
    secrets.users.bacmasterPass,
    secrets.users.tulumbaPass,
    secrets.users.mediaPass,
    secrets.users.backupPass,
    secrets.users.atlonPass,
    secrets.users.elifezelPass,
    secrets.truenas.adminPassword
  ].every((value) => value.trim());
  const chiaReady = mnemonicWords === 24;

  return (
    <section className="section-panel secrets-panel">
      <div className="section-head">
        <div>
          <h2>Secrets Vault</h2>
          <p>Generate v3-compatible env files and sync them to `/root/homelab-secrets`.</p>
        </div>
        <div className="actions inline">
          <button disabled={busy} onClick={() => void onSave()}>
            <ShieldCheck size={17} />
            Save to Windows
          </button>
          <button className="primary-action" disabled={busy || !requiredComplete} onClick={() => void onUpload()}>
            <Upload size={17} />
            Upload to Proxmox
          </button>
        </div>
      </div>

      <div className="secret-status-grid">
        <div>
          <span className={`state-dot ${requiredComplete ? 'done' : 'failed'}`} />
          <div>
            <strong>Core env</strong>
            <span>{requiredComplete ? 'users.env ready' : 'missing required passwords'}</span>
          </div>
        </div>
        <div>
          <span className={`state-dot ${chiaReady ? 'done' : 'warn'}`} />
          <div>
            <strong>Chia mnemonic</strong>
            <span>{mnemonicWords}/24 words</span>
          </div>
        </div>
        <div>
          <span className={`state-dot ${uploadResult?.ok ? 'done' : 'queued'}`} />
          <div>
            <strong>Remote sync</strong>
            <span>{uploadResult?.ok ? `${uploadResult.files.length} files uploaded` : 'not uploaded this session'}</span>
          </div>
        </div>
      </div>

      <div className="secrets-layout">
        <div className="secret-card">
          <h3>Core Users</h3>
          <div className="form-grid">
            <label>
              Bacmaster Password
              <input
                type="password"
                value={secrets.users.bacmasterPass}
                onChange={(event) => updateSection('users', { bacmasterPass: event.target.value })}
              />
            </label>
            <label>
              Tulumba Password
              <input
                type="password"
                value={secrets.users.tulumbaPass}
                onChange={(event) => updateSection('users', { tulumbaPass: event.target.value })}
              />
            </label>
            <label>
              Media Password
              <input
                type="password"
                value={secrets.users.mediaPass}
                onChange={(event) => updateSection('users', { mediaPass: event.target.value })}
              />
            </label>
            <label>
              Backup Password
              <input
                type="password"
                value={secrets.users.backupPass}
                onChange={(event) => updateSection('users', { backupPass: event.target.value })}
              />
            </label>
            <label>
              Jellyfin atlon Password
              <input
                type="password"
                value={secrets.users.atlonPass}
                onChange={(event) => updateSection('users', { atlonPass: event.target.value })}
              />
            </label>
            <label>
              Jellyfin elifezel Password
              <input
                type="password"
                value={secrets.users.elifezelPass}
                onChange={(event) => updateSection('users', { elifezelPass: event.target.value })}
              />
            </label>
            <label>
              Immich Admin Email
              <input value={secrets.users.immichAdminEmail} onChange={(event) => updateSection('users', { immichAdminEmail: event.target.value })} />
            </label>
            <label>
              Immich Second Email
              <input
                value={secrets.users.immichSecondUserEmail}
                onChange={(event) => updateSection('users', { immichSecondUserEmail: event.target.value })}
              />
            </label>
            <label className="span-2">
              OpenWebUI Admin Email
              <input
                value={secrets.users.openWebuiAdminEmail}
                onChange={(event) => updateSection('users', { openWebuiAdminEmail: event.target.value })}
              />
            </label>
          </div>
        </div>

        <div className="secret-card">
          <h3>TrueNAS</h3>
          <div className="form-grid">
            <label className="span-2">
              truenas_admin Password
              <input
                type="password"
                value={secrets.truenas.adminPassword}
                onChange={(event) => updateSection('truenas', { adminPassword: event.target.value })}
              />
            </label>
            <label>
              Host
              <input value={secrets.truenas.host} onChange={(event) => updateSection('truenas', { host: event.target.value })} />
            </label>
            <label>
              Gateway
              <input value={secrets.truenas.gateway} onChange={(event) => updateSection('truenas', { gateway: event.target.value })} />
            </label>
            <label>
              DNS 1
              <input value={secrets.truenas.dns1} onChange={(event) => updateSection('truenas', { dns1: event.target.value })} />
            </label>
            <label>
              DNS 3
              <input value={secrets.truenas.dns3} onChange={(event) => updateSection('truenas', { dns3: event.target.value })} />
            </label>
          </div>
        </div>

        <div className="secret-card span-2">
          <h3>Chia</h3>
          <div className="form-grid">
            <label className="span-2">
              24-word Mnemonic
              <textarea
                value={secrets.chia.mnemonic}
                onChange={(event) => updateSection('chia', { mnemonic: event.target.value })}
                rows={4}
                spellCheck={false}
              />
            </label>
            <label>
              Key Label
              <input value={secrets.chia.keyLabel} onChange={(event) => updateSection('chia', { keyLabel: event.target.value })} />
            </label>
            <label>
              DB Mode
              <select
                value={secrets.chia.dbBootstrapMode}
                onChange={(event) => updateSection('chia', { dbBootstrapMode: event.target.value as HomelabSecretsProfile['chia']['dbBootstrapMode'] })}
              >
                <option value="official_torrent">official_torrent</option>
                <option value="fresh">fresh</option>
                <option value="url">url</option>
                <option value="manual">manual</option>
              </select>
            </label>
            <label className="span-2">
              DB Download URL
              <input value={secrets.chia.dbDownloadUrl} onChange={(event) => updateSection('chia', { dbDownloadUrl: event.target.value })} />
            </label>
            <label>
              DB Cache NFS
              <input value={secrets.chia.dbCacheNfs} onChange={(event) => updateSection('chia', { dbCacheNfs: event.target.value })} />
            </label>
            <label>
              Expected Plot Disks
              <input value={secrets.chia.expectedPlotDisks} onChange={(event) => updateSection('chia', { expectedPlotDisks: event.target.value })} />
            </label>
          </div>
        </div>

        <div className="secret-card">
          <h3>SMTP</h3>
          <div className="form-grid">
            <label>
              SMTP From
              <input value={secrets.smtp.from} onChange={(event) => updateSection('smtp', { from: event.target.value })} />
            </label>
            <label>
              SMTP Host
              <input value={secrets.smtp.host} onChange={(event) => updateSection('smtp', { host: event.target.value })} />
            </label>
            <label>
              Nextcloud App Password
              <input
                type="password"
                value={secrets.smtp.zohoNextcloudAppPass}
                onChange={(event) => updateSection('smtp', { zohoNextcloudAppPass: event.target.value })}
              />
            </label>
            <label>
              Immich App Password
              <input
                type="password"
                value={secrets.smtp.zohoImmichAppPass}
                onChange={(event) => updateSection('smtp', { zohoImmichAppPass: event.target.value })}
              />
            </label>
            <label>
              Seerr App Password
              <input
                type="password"
                value={secrets.smtp.zohoSeerrAppPass}
                onChange={(event) => updateSection('smtp', { zohoSeerrAppPass: event.target.value })}
              />
            </label>
            <label>
              Uptime Kuma App Password
              <input
                type="password"
                value={secrets.smtp.zohoUptimeKumaAppPass}
                onChange={(event) => updateSection('smtp', { zohoUptimeKumaAppPass: event.target.value })}
              />
            </label>
            <label className="span-2">
              TrueNAS App Password
              <input
                type="password"
                value={secrets.smtp.zohoTruenasAppPass}
                onChange={(event) => updateSection('smtp', { zohoTruenasAppPass: event.target.value })}
              />
            </label>
          </div>
        </div>

        <div className="secret-card">
          <h3>Google & AI</h3>
          <div className="form-grid">
            <label className="span-2">
              Google Client ID
              <input value={secrets.google.clientId} onChange={(event) => updateSection('google', { clientId: event.target.value })} />
            </label>
            <label className="span-2">
              Google Client Secret
              <input
                type="password"
                value={secrets.google.clientSecret}
                onChange={(event) => updateSection('google', { clientSecret: event.target.value })}
              />
            </label>
            <label className="span-2">
              Nextcloud Allowed Domains
              <input
                value={secrets.google.nextcloudRegistrationAllowedDomains}
                onChange={(event) => updateSection('google', { nextcloudRegistrationAllowedDomains: event.target.value })}
              />
            </label>
            <label className="checkline span-2">
              <input
                type="checkbox"
                checked={secrets.google.nextcloudRegistrationEnabled}
                onChange={(event) => updateSection('google', { nextcloudRegistrationEnabled: event.target.checked })}
              />
              <span>Nextcloud registration enabled</span>
            </label>
            <label className="checkline span-2">
              <input
                type="checkbox"
                checked={secrets.ollama.pullModels}
                onChange={(event) => updateSection('ollama', { pullModels: event.target.checked })}
              />
              <span>Pull Ollama models during install</span>
            </label>
            <label className="span-2">
              Ollama Models
              <input value={secrets.ollama.models} onChange={(event) => updateSection('ollama', { models: event.target.value })} />
            </label>
          </div>
        </div>

        <div className="secret-card span-2">
          <h3>Global Defaults</h3>
          <div className="form-grid">
            <label>
              Domain
              <input value={secrets.global.domain} onChange={(event) => updateSection('global', { domain: event.target.value })} />
            </label>
            <label>
              Timezone
              <input value={secrets.global.timezone} onChange={(event) => updateSection('global', { timezone: event.target.value })} />
            </label>
            <label>
              VM Storage
              <input value={secrets.global.vmStorage} onChange={(event) => updateSection('global', { vmStorage: event.target.value })} />
            </label>
            <label>
              Media/Chia Storage
              <input
                value={secrets.global.mediaVmStorage}
                onChange={(event) =>
                  updateSection('global', {
                    mediaVmStorage: event.target.value,
                    chiaVmStorage: event.target.value
                  })
                }
              />
            </label>
            <label>
              Cloudflare Tunnel
              <input value={secrets.cloudflare.tunnelName} onChange={(event) => updateSection('cloudflare', { tunnelName: event.target.value })} />
            </label>
            <label>
              LAN DNS
              <input value={secrets.global.lanDns} onChange={(event) => updateSection('global', { lanDns: event.target.value })} />
            </label>
          </div>
        </div>
      </div>

      {uploadResult && (
        <div className="success-block">
          <strong>Uploaded to Proxmox</strong>
          <span>{uploadResult.uploadedAt}</span>
          <div className="secret-file-list">
            {uploadResult.files.map((file) => (
              <code key={file.path}>{file.path}</code>
            ))}
          </div>
        </div>
      )}

      {uploadResult?.warnings.length ? (
        <div className="warning-block">
          <strong>Secrets warnings</strong>
          <ul>
            {uploadResult.warnings.map((warning) => (
              <li key={warning}>{warning}</li>
            ))}
          </ul>
        </div>
      ) : null}
    </section>
  );
}

function PlaceholderPanel({ icon: Icon, title, text }: { icon: typeof Cloud; title: string; text: string }): JSX.Element {
  return (
    <section className="section-panel empty-state">
      <Icon size={42} />
      <h2>{title}</h2>
      <p>{text}</p>
    </section>
  );
}

function ActionPanel({
  icon: Icon,
  title,
  text,
  actionLabel,
  onAction
}: {
  icon: typeof MonitorCog;
  title: string;
  text: string;
  actionLabel: string;
  onAction: () => void;
}): JSX.Element {
  return (
    <section className="section-panel empty-state">
      <Icon size={42} />
      <h2>{title}</h2>
      <p>{text}</p>
      <button onClick={onAction}>
        <Play size={17} />
        {actionLabel}
      </button>
    </section>
  );
}

function RunConsole({
  runs,
  selectedRunId,
  log,
  onRefreshLog
}: {
  runs: RunInfo[];
  selectedRunId: string | null;
  log: string;
  onRefreshLog: (runId: string) => Promise<void>;
}): JSX.Element {
  const logRef = useRef<HTMLPreElement>(null);

  useEffect(() => {
    const element = logRef.current;
    if (!element) return;
    element.scrollTop = element.scrollHeight;
  }, [log, selectedRunId]);

  return (
    <div className="section-panel">
      <div className="section-head">
        <div>
          <h2>Runs & Logs</h2>
          <p>{runs.length ? `${runs.length} recorded runs` : 'No runs yet'}</p>
        </div>
        {selectedRunId && (
          <button onClick={() => void onRefreshLog(selectedRunId)}>
            <RotateCcw size={17} />
            Refresh Log
          </button>
        )}
      </div>
      <div className="run-list">
        {runs.length === 0 && <p>No runs yet.</p>}
        {runs.slice(0, 8).map((run) => (
          <button key={run.id} className={selectedRunId === run.id ? 'active' : ''} onClick={() => void onRefreshLog(run.id)}>
            <span className={`state-dot ${run.status}`} />
            <div>
              <strong>{run.title || run.target}</strong>
              <span>{run.status}</span>
            </div>
          </button>
        ))}
      </div>
      <pre ref={logRef} className="terminal-output log">{log || 'Select a run to read its log.'}</pre>
    </div>
  );
}

export default App;
