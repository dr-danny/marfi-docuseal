# Disabled-by-default Hexclave authentication pilot

This is a staged proof of concept. It does **not** replace DocuSeal's password, recovery, MFA, routes, account roles, or dashboard MFA enforcement. It is disabled unless every setting below is present and valid.

## Staged project

- Project: **MARFI Secure eSIGN staging**, project ID `a6098321-36cd-458a-bbd8-12366f698aac` (non-secret; the browser receives it anyway). Override with `HEXCLAVE_PILOT_PROJECT_ID` only for another reviewed staging project.
- API origin: `https://apigcp.hexclave.com`. The pilot never talks to any other provider origin.
- Trusted origin: exactly `https://secure.marfi.app`; pilot handler path `/hexclave/pilot`. The provider project must whitelist only `https://secure.marfi.app/hexclave/pilot` as a callback.
- The project enforces publishable-client-key access. **The secret server key is never requested, stored, sent, or exposed by this deployment.** Server-side token verification calls `/api/v1/users/me` with access type `client` plus the publishable client key and the user access token.

## Required environment

```dotenv
HEXCLAVE_PILOT_ENABLED=false
HEXCLAVE_PILOT_PROJECT_ID=a6098321-36cd-458a-bbd8-12366f698aac
HEXCLAVE_PILOT_PUBLISHABLE_CLIENT_KEY=
HEXCLAVE_PILOT_BINDINGS_JSON={"hexclave-provider-subject":"123"}
```

- Set `HEXCLAVE_PILOT_ENABLED=true` only for a reviewed, bounded pilot.
- `HEXCLAVE_PILOT_BINDINGS_JSON` is required and is a nonempty object of immutable provider subject to existing local `users.id`. It is not an email map; email-shaped keys are rejected at load.
- The client receives only the project ID and publishable client key. It uses `@hexclave/js` **1.0.67** and the supported in-memory `tokenStore: "memory"`. Access and refresh tokens are never stored by Rails; refresh tokens are not posted to Rails.
- Provider configuration must whitelist the exact same-origin callback `https://secure.marfi.app/hexclave/pilot`. Do not enable provider JIT signup, SSO force flags, or account provisioning.

## Identity restriction: existing @marfi.io users only

Pilot signup and login are restricted to **existing** MARFI identities whose email ends exactly in `@marfi.io`:

- The provider identity email must normalize to a single `@` with domain exactly `marfi.io`. Subdomains (`x@mail.marfi.io`), suffix lookalikes (`x@marfi.io.attacker.example`), and similar domains (`x@evilmarfi.io`, `x@marfi-io.com`) are rejected before any local lookup.
- The explicitly bound local user's own email must also be `@marfi.io`; a binding to a non-MARFI local account is refused.
- The pilot page performs the same domain check client-side as a convenience; the server check is authoritative.
- No public signup, no JIT provisioning, no email-only linking, no role injection. An unknown provider subject fails closed even when its verified email matches an existing local user.

## Passwordless methods only

The staged project must have **password authentication and password recovery disabled**, with exactly these methods enabled:

1. magic link / email OTP (`sendMagicLinkEmail` + `signInWithMagicLink` with the returned nonce)
2. GitHub OAuth (`signInWithOAuth('github')`, `callOAuthCallback()` on the fixed same-origin return)
3. passkeys (`signInWithPasskey()`)

Do not enable Google or Microsoft. The pilot UI exposes no password field and calls no password, password-reset, or credential SDK method; regression tests assert this.

## Explicit linking gate (no auto-link by email)

An existing bound `@marfi.io` user may sign in with an enabled provider only when the provider account is already explicitly linked to that local user. The explicit link is the operator-managed subject-to-local-ID binding (`HEXCLAVE_PILOT_BINDINGS_JSON`), populated out of band after the user's provider identity is confirmed. The provider user ID (`id` from `/api/v1/users/me`) is the only lookup key.

If the provider response cannot prove an existing explicit link (unknown subject), the exchange fails closed: no account is created, no email matching is attempted, no session is issued, and the user is sent to the controlled linking path (contact an administrator to bind the provider subject). New provider identities are bound only by operator action.

## What is allowed

The pilot page appears only when the full configuration validates. A successful client session (magic-link OTP, GitHub OAuth return, or passkey, plus provider MFA when enrolled) sends only its short-lived access token, plus the Rails CSRF token, to the same-origin exchange endpoint.

The server validates the token at the fixed staging endpoint, then requires **all** of the following before a Rails session is created:

1. exact `@marfi.io` domain on the verified provider identity
2. `primaryEmailVerified` is true
3. exact subject binding to an existing local user ID
4. exact `@marfi.io` domain on the bound local user
5. exact normalized provider email match to that local user's email
6. local user and account currently eligible for authentication
7. local user does **not** have native `otp_required_for_login`

Native-MFA users are deliberately refused by the pilot and must use the existing native sign-in flow. Existing role authorization and the account `force_mfa` dashboard enforcement remain in force. Pilot success always redirects to `/`; it ignores `redir` and any external destination.

## Recovery and pilot operation

Keep native password, reset-password, authenticator, and recovery routes usable for every pilot user. Do not remove credentials or change native MFA while this pilot exists. If the provider is unavailable, configuration is incomplete, an identity is malformed, an email is unverified/mismatched/outside `@marfi.io`, a subject is unknown, or a local user is archived/ineligible, the exchange fails closed and shows the native sign-in fallback.

The pilot action also cannot create local users, link by email, grant roles/admin, update user fields, modify signers/API routes, or retain provider tokens.

## Portal UI changes shipped with the pilot

- The language selector is removed from all native authentication pages and from the portal account settings. Stored account locales still apply server-side; the setup wizard is unchanged.
- The auth footer keeps the `Forked from DocuSeal OSS` attribution but no longer renders a `Source` link. AGPL/corresponding-source notices remain intact on the landing page attribution and in transactional email footers.

## Exact cutover gate

This branch is **not** authorization to activate or cut over authentication. Before any activation or password-removal proposal, separately obtain explicit approval and verify in a non-production pilot:

1. every explicitly approved in-scope pilot user can complete magic-link OTP, GitHub OAuth, and passkey sign-in and any enrolled provider MFA; do not bind emergency accounts
2. non-`@marfi.io` and lookalike-domain identities are refused at both the UI and the exchange
3. a native-MFA user is refused and can still complete native MFA
4. invalid, expired, unverified, mismatched, unknown, archived, locked, and account-archived cases fail closed
5. native password reset and recovery are tested end to end
6. account `force_mfa` and role authorization still apply after a pilot login
7. secrets are injected through the deployment secret store and are absent from browser responses and logs
8. a rollback consists solely of `HEXCLAVE_PILOT_ENABLED=false`, with native sign-in already verified

Do not treat a disabled page, installed SDK, or this commit as activation approval.

## Pilot security limits

- The pilot sends `Cache-Control: no-store` and `Referrer-Policy: no-referrer`; only this page permits browser connections to `https://apigcp.hexclave.com`. Its link performs a full navigation rather than inheriting the native page's stricter CSP through Turbo.
- Each process permits 10 exchange attempts per IP per minute and 30 total per minute, using the existing app `RateLimit` store. A nonblocking mutex allows only one in-flight provider request per process. Excess work is rejected, not queued. These are **per-process**, not distributed limits; review aggregate limits and any shared ingress control before production activation. No Cloudflare rule is changed here.
- Tokens longer than 8192 bytes are rejected before network activity. Successful exchanges reset the old session before signing in the mapped local user. Native SessionsController is unchanged.
- Pilot action buttons suppress duplicate in-flight clicks. Email-link verifiers still reach the initial callback request, so deployment/proxy access-log redaction for callback query strings remains an operator gate; no browser script can erase a request already logged upstream.
- Two independent vaulted native emergency administrators must be tested in an isolated browser and kept outside all provider bindings. This branch neither provisions them nor authorizes disabling their password routes.
