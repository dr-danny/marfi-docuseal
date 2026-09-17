# Disabled-by-default Hexclave authentication pilot

This is a staged proof of concept. It does **not** replace DocuSeal's password, recovery, MFA, routes, account roles, or dashboard MFA enforcement. It is disabled unless every setting below is present and valid.

## Required environment

```dotenv
HEXCLAVE_PILOT_ENABLED=false
HEXCLAVE_PILOT_PROJECT_ID=
HEXCLAVE_PILOT_PUBLISHABLE_CLIENT_KEY=
HEXCLAVE_PILOT_SECRET_SERVER_KEY=
HEXCLAVE_PILOT_BINDINGS_JSON={"hexclave-provider-subject":"123"}
```

- Set `HEXCLAVE_PILOT_ENABLED=true` only for a reviewed, bounded pilot.
- `HEXCLAVE_PILOT_SECRET_SERVER_KEY` is backend-only. Never put it in a pack, view, browser config, issue, or log.
- `HEXCLAVE_PILOT_BINDINGS_JSON` is required and is a nonempty object of immutable provider subject to existing local `users.id`. It is not an email map.
- The pilot uses the fixed provider endpoint `https://api.hexclave.com/api/v1/users/me` with short timeouts and rejects every non-200 or malformed response. It does not follow redirects.
- The client receives only the project ID and publishable client key. It uses `@hexclave/js` **1.0.67** and the supported in-memory `tokenStore: "memory"`. Access and refresh tokens are never stored by Rails; refresh tokens are not posted to Rails.
- Provider configuration must whitelist the exact same-origin callback `https://YOUR-PORTAL-ORIGIN/hexclave/pilot`. Do not enable password removal, provider JIT signup, SSO force flags, or account provisioning.

## What is allowed

The pilot page appears only when the full configuration validates. It uses `sendMagicLinkEmail(email, { callbackUrl })`, typed OTP plus returned nonce with `signInWithMagicLink`, and provider MFA completion with `signInWithMfa`. A successful client session sends only its short-lived access token, plus the Rails CSRF token, to the same-origin exchange endpoint.

The server validates the token at the fixed provider endpoint, requires `primaryEmailVerified`, then requires all of the following before a Rails session is created:

1. exact subject binding to an existing local user ID
2. exact normalized provider email match to that local user's email
3. local user and account currently eligible for authentication
4. local user does **not** have native `otp_required_for_login`

Native-MFA users are deliberately refused by the pilot and must use the existing native sign-in flow. Existing role authorization and the account `force_mfa` dashboard enforcement remain in force. Pilot success always redirects to `/`; it ignores `redir` and any external destination.

## Recovery and pilot operation

Keep native password, reset-password, authenticator, and recovery routes usable for every pilot user. Do not remove credentials or change native MFA while this pilot exists. If the provider is unavailable, configuration is incomplete, an identity is malformed, an email is unverified/mismatched, a subject is unknown, or a local user is archived/ineligible, the exchange fails closed and shows the native sign-in fallback.

The pilot action also cannot create local users, link by email, grant roles/admin, update user fields, modify signers/API routes, or retain provider tokens.

## Exact cutover gate

This branch is **not** authorization to activate or cut over authentication. Before any activation or password-removal proposal, separately obtain explicit approval and verify in a non-production pilot:

1. two existing, bound test users can complete magic-link OTP and provider MFA
2. a native-MFA user is refused and can still complete native MFA
3. invalid, expired, unverified, mismatched, unknown, archived, locked, and account-archived cases fail closed
4. native password reset and recovery are tested end to end
5. account `force_mfa` and role authorization still apply after a pilot login
6. secrets are injected through the deployment secret store and are absent from browser responses and logs
7. a rollback consists solely of `HEXCLAVE_PILOT_ENABLED=false`, with native sign-in already verified

Do not treat a disabled page, installed SDK, or this commit as activation approval.
