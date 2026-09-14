import { AppmintError, AppmintNetworkError } from './errors.js';
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
export function urlFor(cfg, path) {
    const clean = String(path).replace(/^\/+/, '').replace(/^api\//, '');
    return isBrowser() ? `${cfg.proxyPrefix}/${clean}` : `${cfg.baseUrl}/${clean}`;
}
export class Transport {
    cfg;
    appToken = null;
    pending = null;
    customerToken = null;
    constructor(cfg) {
        this.cfg = cfg;
    }
    setCustomerToken(token) { this.customerToken = token; }
    getCustomerToken() { return this.customerToken; }
    clearAppToken() { this.appToken = null; }
    /** The application's own token. Server side only; fetched once, shared. */
    async getAppToken() {
        if (isBrowser())
            return null;
        if (this.appToken)
            return this.appToken;
        this.pending ??= this.fetchAppToken().finally(() => { this.pending = null; });
        this.appToken = await this.pending;
        return this.appToken;
    }
    async fetchAppToken() {
        const { baseUrl, orgId, appId, appKey, appSecret, fetch: f } = this.cfg;
        if (!appId || !appKey || !appSecret)
            return null;
        try {
            const res = await f(`${baseUrl}/profile/app/key`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json', orgid: orgId },
                body: JSON.stringify({ appId, key: appKey, secret: appSecret }),
            });
            if (!res.ok)
                return null;
            const body = await res.json().catch(() => null);
            return body?.token ?? null;
        }
        catch {
            return null;
        }
    }
    async headers(withBody) {
        const h = { orgid: this.cfg.orgId };
        if (withBody)
            h['Content-Type'] = 'application/json';
        if (isBrowser()) {
            // The proxy attaches the application identity. The browser sends only
            // who the visitor is.
            if (this.customerToken)
                h.authorization = this.customerToken;
            return h;
        }
        if (this.cfg.domainAsOrg)
            h.domainAsOrg = 'true';
        h['shared-org-id'] = this.cfg.orgId;
        const token = await this.getAppToken();
        // The header called `Authorization` is the APPLICATION's, not the person's
        // — they answer different questions and ride separately.
        if (token)
            h.Authorization = `Bearer ${token}`;
        if (this.customerToken)
            h['x-client-authorization'] = this.customerToken;
        return h;
    }
    async request(method, path, body, query, retried = false) {
        const url = new URL(urlFor(this.cfg, path), isBrowser() ? window.location.origin : undefined);
        for (const [k, v] of Object.entries(query ?? {})) {
            if (v === undefined || v === null)
                continue;
            if (Array.isArray(v))
                v.forEach((x) => url.searchParams.append(k, String(x)));
            else
                url.searchParams.set(k, String(v));
        }
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), this.cfg.timeoutMs);
        let res;
        try {
            res = await this.cfg.fetch(url.toString(), {
                method,
                headers: await this.headers(body !== undefined),
                body: body === undefined ? undefined : JSON.stringify(body),
                signal: controller.signal,
                ...(isBrowser() ? { credentials: 'same-origin' } : { cache: 'no-store' }),
            });
        }
        catch (e) {
            throw new AppmintNetworkError(`Could not reach ${url.host || 'the server'}: ${e.message}`);
        }
        finally {
            clearTimeout(timer);
        }
        // A 401 on the server side is ambiguous — the app token may simply have
        // aged out. Renew it once before concluding anything about the visitor.
        if (res.status === 401 && !retried && !isBrowser()) {
            this.clearAppToken();
            return this.request(method, path, body, query, true);
        }
        const text = await res.text();
        let payload;
        try {
            payload = text ? JSON.parse(text) : undefined;
        }
        catch {
            payload = text;
        }
        if (this.cfg.logRequests) {
            console.log(`[appmint] ${method} ${url.pathname} → ${res.status}`);
        }
        if (!res.ok) {
            throw new AppmintError(payload?.error ?? payload?.message ?? res.statusText, res.status, payload?.code, payload);
        }
        return payload;
    }
}
