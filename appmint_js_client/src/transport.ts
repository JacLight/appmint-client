import { AppmintError, AppmintNetworkError } from './errors.js';
import type { ResolvedConfig } from './config.js';

const isBrowser = () => typeof window !== 'undefined';

/**
 * Where a request goes, decided by where the code runs.
 *
 * In a browser  → your own app's proxy. No credentials leave the page.
 * On a server   → appengine directly, with the application's token attached.
 *
 * This is the whole security model: browser code physically cannot reach
 * appengine, so credentials cannot leak by forgetting something.
 */
export function urlFor(cfg: ResolvedConfig, path: string): string {
  const clean = String(path).replace(/^\/+/, '').replace(/^api\//, '');
  return isBrowser() ? `${cfg.proxyPrefix}/${clean}` : `${cfg.baseUrl}/${clean}`;
}

export class Transport {
  private appToken: string | null = null;
  private pending: Promise<string | null> | null = null;
  private customerToken: string | null = null;

  constructor(private cfg: ResolvedConfig) {}

  setCustomerToken(token: string | null) { this.customerToken = token; }
  getCustomerToken() { return this.customerToken; }
  clearAppToken() { this.appToken = null; }

  /** The application's own token. Server side only; fetched once, shared. */
  private async getAppToken(): Promise<string | null> {
    if (isBrowser()) return null;
    if (this.appToken) return this.appToken;
    this.pending ??= this.fetchAppToken().finally(() => { this.pending = null; });
    this.appToken = await this.pending;
    return this.appToken;
  }

  private async fetchAppToken(): Promise<string | null> {
    const { baseUrl, orgId, appId, appKey, appSecret, fetch: f } = this.cfg;
    if (!appId || !appKey || !appSecret) return null;
    try {
      const res = await f(`${baseUrl}/profile/app/key`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', orgid: orgId },
        body: JSON.stringify({ appId, key: appKey, secret: appSecret }),
      });
      if (!res.ok) return null;
      const body: any = await res.json().catch(() => null);
      return body?.token ?? null;
    } catch {
      return null;
    }
  }

  private async headers(withBody: boolean): Promise<Record<string, string>> {
    const h: Record<string, string> = { orgid: this.cfg.orgId };
    if (withBody) h['Content-Type'] = 'application/json';

    if (isBrowser()) {
      // The proxy attaches the application identity. The browser sends only
      // who the visitor is.
      if (this.customerToken) h.authorization = this.customerToken;
      return h;
    }

    if (this.cfg.domainAsOrg) h.domainAsOrg = 'true';
    h['shared-org-id'] = this.cfg.orgId;
    const token = await this.getAppToken();
    // The header called `Authorization` is the APPLICATION's, not the person's
    // — they answer different questions and ride separately.
    if (token) h.Authorization = `Bearer ${token}`;
    if (this.customerToken) h['x-client-authorization'] = this.customerToken;
    return h;
  }

  async request<T = unknown>(
    method: string,
    path: string,
    body?: unknown,
    query?: Record<string, unknown>,
    retried = false,
  ): Promise<T> {
    const url = new URL(urlFor(this.cfg, path), isBrowser() ? window.location.origin : undefined);
    for (const [k, v] of Object.entries(query ?? {})) {
      if (v === undefined || v === null) continue;
      if (Array.isArray(v)) v.forEach((x) => url.searchParams.append(k, String(x)));
      else url.searchParams.set(k, String(v));
    }

    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), this.cfg.timeoutMs);

    let res: Response;
    try {
      res = await this.cfg.fetch(url.toString(), {
        method,
        headers: await this.headers(body !== undefined),
        body: body === undefined ? undefined : JSON.stringify(body),
        signal: controller.signal,
        ...(isBrowser() ? { credentials: 'same-origin' as const } : { cache: 'no-store' as const }),
      });
    } catch (e) {
      throw new AppmintNetworkError(`Could not reach ${url.host || 'the server'}: ${(e as Error).message}`);
    } finally {
      clearTimeout(timer);
    }

    // A 401 on the server side is ambiguous — the app token may simply have
    // aged out. Renew it once before concluding anything about the visitor.
    if (res.status === 401 && !retried && !isBrowser()) {
      this.clearAppToken();
      return this.request<T>(method, path, body, query, true);
    }

    const text = await res.text();
    let payload: any;
    try { payload = text ? JSON.parse(text) : undefined; } catch { payload = text; }

    if (this.cfg.logRequests) {
      console.log(`[appmint] ${method} ${url.pathname} → ${res.status}`);
    }

    if (!res.ok) {
      throw new AppmintError(
        payload?.error ?? payload?.message ?? res.statusText,
        res.status,
        payload?.code,
        payload,
      );
    }
    return payload as T;
  }
}
