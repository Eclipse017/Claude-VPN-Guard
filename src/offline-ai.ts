// Deliberately no model SDK, credentials, or network implementation in this distribution.
export type AiFetch = typeof fetch;
export interface AiRequest { system: string; messages: unknown[] }
export interface AiTransportEvent { text?: string; refusal?: boolean }
export function isolatedFetch(): typeof fetch { return async () => { throw new Error('Offline companion'); }; }
export async function* sdkTextStream(): AsyncGenerator<AiTransportEvent> { throw new Error('Offline companion'); }
export function isAuthenticationFailure(): boolean { return false; }
export function isRateLimitFailure(): boolean { return false; }
