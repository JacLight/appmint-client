/**
 * Anything the server refused to do.
 *
 * `code` is the machine-readable reason and is stable — `missing_orgid`,
 * `token_expired`, `missing_authorization_header`. Branch on it. `message` is
 * written for a person and may be reworded.
 */
export declare class AppmintError extends Error {
    readonly status: number;
    readonly code?: string | undefined;
    readonly body?: unknown | undefined;
    constructor(message: string, status: number, code?: string | undefined, body?: unknown | undefined);
}
/** The request never reached the server — refused, timed out, DNS. */
export declare class AppmintNetworkError extends AppmintError {
    constructor(message: string);
}
