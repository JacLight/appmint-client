export function resolveConfig(c) {
    if (!c?.baseUrl)
        throw new Error('AppmintConfig: `baseUrl` is required');
    if (!c?.orgId)
        throw new Error('AppmintConfig: `orgId` is required');
    return {
        baseUrl: c.baseUrl.replace(/\/+$/, ''),
        orgId: c.orgId,
        appId: c.appId,
        appKey: c.appKey,
        appSecret: c.appSecret,
        domainAsOrg: c.domainAsOrg ?? false,
        proxyPrefix: (c.proxyPrefix ?? '/api').replace(/\/+$/, ''),
        timeoutMs: c.timeoutMs ?? 30_000,
        logRequests: c.logRequests ?? false,
        fetch: c.fetch ?? globalThis.fetch.bind(globalThis),
    };
}
