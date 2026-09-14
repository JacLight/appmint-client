import type { ResolvedConfig } from './config.js';
/**
 * Where a request goes, decided by where the code runs.
 *
 * In a browser  → your own app's proxy. No credentials leave the page.
 * On a server   → appengine directly, with the application's token attached.
 *
 * This is the whole security model: browser code physically cannot reach
 * appengine, so credentials cannot leak by forgetting something.
 */
export declare function urlFor(cfg: ResolvedConfig, path: string): string;
export declare class Transport {
    private cfg;
    private appToken;
    private pending;
    private customerToken;
    constructor(cfg: ResolvedConfig);
    setCustomerToken(token: string | null): void;
    getCustomerToken(): string | null;
    clearAppToken(): void;
    /** The application's own token. Server side only; fetched once, shared. */
    private getAppToken;
    private fetchAppToken;
    private headers;
    request<T = unknown>(method: string, path: string, body?: unknown, query?: Record<string, unknown>, retried?: boolean): Promise<T>;
}
