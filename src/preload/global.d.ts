import type { HomelabApi } from '../shared/types';

declare global {
  interface Window {
    homelab: HomelabApi;
  }
}

export {};
