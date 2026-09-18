import { HexclaveClientApp } from '@hexclave/js'

const root = document.getElementById('hexclave-pilot')

if (root) {
  const csrf = document.querySelector('meta[name="csrf-token"]')?.content
  const signInPath = '/sign_in'
  const fixedCallbackUrl = `${window.location.origin}${signInPath}`
  const allowedDomain = root.dataset.allowedDomain || 'marfi.io'
  const app = new HexclaveClientApp({
    baseUrl: 'https://apigcp.hexclave.com',
    projectId: root.dataset.projectId,
    publishableClientKey: root.dataset.publishableClientKey,
    // The SDK type supports "memory". No access or refresh tokens persist in a
    // cookie, localStorage, sessionStorage, URL, or Rails session.
    tokenStore: 'memory',
    urls: {
      signIn: signInPath,
      afterSignIn: signInPath,
      magicLinkCallback: signInPath,
      mfa: signInPath,
      oauthCallback: '/handler/oauth-callback',
      error: signInPath
    }
  })

  const email = document.getElementById('hexclave-pilot-email')
  const nativeEmail = document.getElementById('native-signin-email')
  const code = document.getElementById('hexclave-pilot-otp')
  const mfaCode = document.getElementById('hexclave-pilot-mfa-code')
  const message = document.getElementById('hexclave-pilot-message')
  const start = document.getElementById('hexclave-pilot-start')
  const codeStep = document.getElementById('hexclave-pilot-code')
  const codeHint = document.getElementById('hexclave-pilot-code-hint')
  const resend = document.getElementById('hexclave-pilot-resend')
  const mfaStep = document.getElementById('hexclave-pilot-mfa')
  const linkStep = document.getElementById('hexclave-pilot-link')
  let nonce = ''
  let resendTimer = null
  let resendRemaining = 0
  const RESEND_SECONDS = 180

  const syncNativeEmail = () => {
    if (nativeEmail) nativeEmail.value = email.value
  }
  email.addEventListener('input', syncNativeEmail)
  syncNativeEmail()

  const show = (element) => element.classList.remove('hidden')
  const hide = (element) => element.classList.add('hidden')
  const setMessage = (text) => { message.textContent = text }
  const resultError = (result) => result?.status === 'error'

  // Client-side convenience check only. The server re-enforces the exact
  // @marfi.io domain on the verified provider identity and the bound user.
  const isAllowedEmail = (address) => {
    const at = address.lastIndexOf('@')
    return at > 0 && address.slice(at + 1).toLowerCase() === allowedDomain
  }

  const bindAsync = (id, handler) => {
    const button = document.getElementById(id)
    button.addEventListener('click', async () => {
      if (button.disabled) return
      button.disabled = true
      try { await handler() } finally { button.disabled = false }
    })
  }

  const exchange = async () => {
    const accessToken = await app.getAccessToken()
    if (!accessToken) throw new Error('The provider did not issue an access token.')

    const response = await fetch(root.dataset.exchangeUrl, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'X-CSRF-Token': csrf,
        Accept: 'text/html'
      }
    })
    const destination = new URL(response.url, window.location.origin)
    // Do not send Accept: application/json. Fetch would keep that header on the
    // followed GET /, and the HTML dashboard returns 406, which looked like a
    // failed sign-in after Hexclave already accepted the code.
    if (destination.origin === window.location.origin && (response.ok || response.redirected) && !destination.pathname.includes('/hexclave/pilot')) {
      window.location.assign('/')
      return
    }
    throw new Error('Sign-in was not accepted.')
  }

  const showMfaIfPending = (error) => {
    const attempt = window.sessionStorage.getItem('hexclave_mfa_attempt_code')
    if (!attempt) return false

    hide(start); hide(codeStep); hide(linkStep); show(mfaStep)
    setMessage(error?.humanReadableMessage || 'Enter the code from your authenticator.')
    return true
  }

  const formatCountdown = (seconds) => {
    const minutes = Math.floor(seconds / 60)
    const remainder = seconds % 60
    return `${minutes}:${String(remainder).padStart(2, '0')}`
  }

  const stopResendTimer = () => {
    if (resendTimer) window.clearInterval(resendTimer)
    resendTimer = null
  }

  const startResendTimer = () => {
    stopResendTimer()
    resendRemaining = RESEND_SECONDS
    resend.disabled = true
    resend.textContent = `Send a new code in ${formatCountdown(resendRemaining)}`
    resendTimer = window.setInterval(() => {
      resendRemaining -= 1
      if (resendRemaining <= 0) {
        stopResendTimer()
        resend.disabled = false
        resend.textContent = 'Send a new code'
        return
      }
      resend.textContent = `Send a new code in ${formatCountdown(resendRemaining)}`
    }, 1000)
  }

  const sendCode = async () => {
    const address = email.value.trim()
    syncNativeEmail()
    if (!isAllowedEmail(address)) {
      setMessage(`Only existing @${allowedDomain} identities can sign in.`)
      return false
    }

    setMessage('Sending code...')
    const result = await app.sendMagicLinkEmail(address, { callbackUrl: fixedCallbackUrl })
    if (resultError(result) || !result?.data?.nonce) throw result?.error || new Error('No verifier returned.')
    nonce = result.data.nonce
    hide(start); hide(mfaStep); hide(linkStep); show(codeStep)
    if (codeHint) codeHint.textContent = `Enter the code we emailed to ${address}.`
    setMessage('')
    code.value = ''
    startResendTimer()
    code.focus()
    return true
  }

  bindAsync('hexclave-pilot-send', async () => {
    try {
      await sendCode()
    } catch (error) {
      setMessage(error?.humanReadableMessage || error?.message || 'Could not send a code.')
    }
  })

  resend.addEventListener('click', async () => {
    if (resend.disabled) return
    resend.disabled = true
    try {
      await sendCode()
    } catch (error) {
      setMessage(error?.humanReadableMessage || error?.message || 'Could not send a code.')
      resend.disabled = false
      resend.textContent = 'Send a new code'
    }
  })

  bindAsync('hexclave-pilot-verify', async () => {
    const typedCode = code.value.trim().replace(/[^a-zA-Z0-9]/g, '')
    if (!nonce || typedCode.length !== 6) return setMessage('Enter the six-character code from the newest email.')

    setMessage('Verifying code...')
    try {
      // Hexclave verifies the visible OTP plus the nonce from sendMagicLinkEmail.
      // Keep the emailed case; lowercasing invalidates mixed-case codes.
      const result = await app.signInWithMagicLink(`${typedCode}${nonce}`, { noRedirect: true })
      if (resultError(result)) throw result.error
      await exchange()
    } catch (error) {
      if (!showMfaIfPending(error)) setMessage(error?.humanReadableMessage || error?.message || 'That code was not accepted.')
    }
  })

  bindAsync('hexclave-pilot-github', async () => {
    setMessage('Redirecting to GitHub...')
    try {
      // GitHub is the only enabled OAuth provider in the staged project.
      // Account creation is disabled there, so an unlinked identity cannot
      // provision an account; the server also requires the explicit binding.
      await app.signInWithOAuth('github', { returnTo: fixedCallbackUrl })
    } catch (error) {
      setMessage(error?.humanReadableMessage || 'Could not start GitHub sign-in.')
    }
  })

  bindAsync('hexclave-pilot-passkey', async () => {
    setMessage('Waiting for passkey...')
    try {
      const result = await app.signInWithPasskey()
      if (resultError(result)) throw result.error
      await exchange()
    } catch (error) {
      if (!showMfaIfPending(error)) setMessage(error?.humanReadableMessage || 'Passkey sign-in was not accepted.')
    }
  })

  bindAsync('hexclave-pilot-mfa-verify', async () => {
    const typedCode = mfaCode.value.trim().replace(/\D/g, '')
    const attempt = window.sessionStorage.getItem('hexclave_mfa_attempt_code')
    if (!attempt || typedCode.length !== 6) return setMessage('Enter the current authenticator code.')

    setMessage('Verifying authenticator...')
    try {
      const result = await app.signInWithMfa(typedCode, attempt, { noRedirect: true })
      if (resultError(result)) throw result.error
      window.sessionStorage.removeItem('hexclave_mfa_attempt_code')
      await exchange()
    } catch (error) {
      setMessage(error?.humanReadableMessage || 'Authenticator code was not accepted.')
    }
  })

  const query = new URLSearchParams(window.location.search)
  const linkCode = query.get('code')
  const oauthState = query.get('state')
  const oauthError = query.get('errorCode') || query.get('error')
  const stripQuery = () => window.history.replaceState({}, document.title, signInPath)
  if (oauthError) {
    const raw = query.get('message') || query.get('error_description') || ''
    stripQuery()
    setMessage(raw.includes('already used')
      ? 'GitHub uses an email already on this MARFI login. Try GitHub again.'
      : (raw || 'GitHub sign-in was not accepted.'))
  } else if (linkCode && oauthState) {
    stripQuery()
    hide(start); hide(codeStep)
    setMessage('Completing GitHub sign-in...')
    app.callOAuthCallback().then(async (handled) => {
      if (!handled) throw new Error('OAuth callback was not accepted.')
      await exchange()
    }).catch((error) => {
      if (!showMfaIfPending(error)) setMessage(error?.humanReadableMessage || 'GitHub sign-in was not accepted.')
    })
  } else if (linkCode) {
    stripQuery()
    hide(start); hide(codeStep); show(linkStep)
    bindAsync('hexclave-pilot-link-verify', async () => {
      setMessage('Verifying magic link...')
      try {
        const result = await app.signInWithMagicLink(linkCode, { noRedirect: true })
        if (resultError(result)) throw result.error
        await exchange()
      } catch (error) {
        if (!showMfaIfPending(error)) setMessage(error?.humanReadableMessage || 'Magic link was not accepted.')
      }
    })
  } else if (window.sessionStorage.getItem('hexclave_mfa_attempt_code')) {
    hide(start); hide(codeStep); hide(linkStep); show(mfaStep)
    setMessage('Enter the code from your authenticator.')
  }
}
