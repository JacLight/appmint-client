/** Everything the client needs to reach one Appmint organization. */
export interface AppmintConfig {
    /** Where appengine lives, no trailing slash. e.g. `https://appengine.appmint.io` */
    baseUrl: string;
    /** The organization every request is scoped to. There is no org-less call. */
    orgId: string;
    /**
     * Application credentials.
     *
     * SERVER ONLY. They are never sent from a browser — the browser transport
     * talks to your own app, not to appengine — so putting them in client code
     * publishes them for nothing.
     */
    appId?: string;
    appKey?: string;
    appSecret?: string;
    /** Resolve the org from the request domain instead of the header. Rare. */
    domainAsOrg?: boolean;
    /** Where the browser transport sends requests. Your proxy route. */
    proxyPrefix?: string;
    timeoutMs?: number;
    logRequests?: boolean;
    fetch?: typeof globalThis.fetch;
}
export type ResolvedConfig = Required<Omit<AppmintConfig, 'fetch' | 'appId' | 'appKey' | 'appSecret'>> & Pick<AppmintConfig, 'appId' | 'appKey' | 'appSecret'> & {
    fetch: typeof globalThis.fetch;
};
export declare function resolveConfig(c: AppmintConfig): ResolvedConfig;
