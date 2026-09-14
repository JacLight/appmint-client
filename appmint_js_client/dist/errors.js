/**
 * Anything the server refused to do.
 *
 * `code` is the machine-readable reason and is stable — `missing_orgid`,
 * `token_expired`, `missing_authorization_header`. Branch on it. `message` is
 * written for a person and may be reworded.
 */
export class AppmintError extends Error {
    status;
    code;
    body;
    constructor(message, status, code, body) {
        super(message);
        this.status = status;
        this.code = code;
        this.body = body;
        this.name = 'AppmintError';
    }
}
/** The request never reached the server — refused, timed out, DNS. */
export class AppmintNetworkError extends AppmintError {
    constructor(message) {
        super(message, 0);
        this.name = 'AppmintNetworkError';
    }
}
