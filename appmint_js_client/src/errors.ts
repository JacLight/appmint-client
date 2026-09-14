/**
 * Anything the server refused to do.
 *
 * `code` is the machine-readable reason and is stable — `missing_orgid`,
 * `token_expired`, `missing_authorization_header`. Branch on it. `message` is
 * written for a person and may be reworded.
 */
export class AppmintError extends Error {
  constructor(
    message: string,
    readonly status: number,
    readonly code?: string,
    readonly body?: unknown,
  ) {
    super(message);
    this.name = 'AppmintError';
  }
}

/** The request never reached the server — refused, timed out, DNS. */
export class AppmintNetworkError extends AppmintError {
  constructor(message: string) {
    super(message, 0);
    this.name = 'AppmintNetworkError';
  }
}
