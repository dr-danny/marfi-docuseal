import { HexclaveClientApp } from '@hexclave/js'

const root = document.getElementById('hexclave-pilot')

if (root) {
  const csrf = document.querySelector('meta[name="csrf-token"]')?.content
  const fixedCallbackUrl = `${window.location.origin}/hexclave/pilot`
  const app = new HexclaveClientApp({
    baseUrl: 'https://api.hexclave.com',
    projectId: root.dataset.projectId,
    publishableClientKey: root.dataset.publishableClientKey,
    // The SDK type supports "memory". No access or refresh tokens persist in a
    // cookie, localStorage, sessionStorage, URL, or Rails session.
    tokenStore: 'memory',
    urls: {
      signIn: '/hexclave/pilot',
      afterSignIn: '/hexclave/pilot',
      magicLinkCallback: '/hexclave/pilot',
      mfa: '/hexclave/pilot'
    }
  })

  const email = document.getElementById('hexclave-pilot-email')
  const code = document.getElementById('hexclave-pilot-otp')
  const mfaCode = document.getElementById('hexclave-pilot-mfa-code')
  const message = document.getElementById('hexclave-pilot-message')
  const start = document.getElementById('hexclave-pilot-start')
  const codeStep = document.getElementById('hexclave-pilot-code')
  const mfaStep = document.getElementById('hexclave-pilot-mfa')
  const linkStep = document.getElementById('hexclave-pilot-link')
  let nonce = ''

  const show = (element) => element.classList.remove('hidden')
  const hide = (element) => element.classList.add('hidden')
  const setMessage = (text) => { message.textContent = text }
  const resultError = (result) => result?.status === 'error'

  const exchange = async () => {
    const accessToken = await app.getAccessToken()
    if (!accessToken) throw new Error('The provider did not issue an access token.')

    const response = await fetch(root.dataset.exchangeUrl, {
      method: 'POST',
      credentials: 'same-origin',
      headers: {
        Authorization: `Bearer ${accessToken}`,
        'X-CSRF-Token': csrf,
        Accept: 'application/json'
      }
    })
    const destination = new URL(response.url, window.location.origin)
    if (response.redirected && response.ok && destination.origin === window.location.origin && destination.pathname === '/') {
      window.location.assign('/')
      return
    }
    throw new Error('Pilot sign-in was not accepted. Use native sign-in.')
  }

  const showMfaIfPending = (error) => {
    const attempt = window.sessionStorage.getItem('hexclave_mfa_attempt_code')
    if (!attempt) return false

    hide(start); hide(codeStep); hide(linkStep); show(mfaStep)
    setMessage(error?.humanReadableMessage || 'Enter the code from your authenticator.')
    return true
  }

  document.getElementById('hexclave-pilot-send').addEventListener('click', async () => {
    const address = email.value.trim()
    if (!address) return setMessage('Enter your approved email address.')

    setMessage('Sending code...')
    try {
      const result = await app.sendMagicLinkEmail(address, { callbackUrl: fixedCallbackUrl })
      if (resultError(result) || !result?.data?.nonce) throw result?.error || new Error('No verifier returned.')
      nonce = result.data.nonce
      hide(start); show(codeStep)
      setMessage('Enter the six-character code from the email.')
      code.focus()
    } catch (error) {
      setMessage(error?.humanReadableMessage || 'Could not send a pilot code.')
    }
  })

  document.getElementById('hexclave-pilot-verify').addEventListener('click', async () => {
    const typedCode = code.value.trim().replace(/[^a-z0-9]/gi, '').toLowerCase()
    if (!nonce || typedCode.length !== 6) return setMessage('Enter the six-character code from the newest email.')

    setMessage('Verifying code...')
    try {
      // Hexclave SDK 1.0.67 verifies the visible OTP plus sendMagicLinkEmail nonce.
      const result = await app.signInWithMagicLink(`${typedCode}${nonce}`, { noRedirect: true })
      if (resultError(result)) throw result.error
      await exchange()
    } catch (error) {
      if (!showMfaIfPending(error)) setMessage(error?.humanReadableMessage || 'Pilot code was not accepted.')
    }
  })

  document.getElementById('hexclave-pilot-mfa-verify').addEventListener('click', async () => {
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

  const linkCode = new URLSearchParams(window.location.search).get('code')
  if (linkCode) {
    // Do not leave an email-link verifier in the address bar or browser history.
    window.history.replaceState({}, document.title, '/hexclave/pilot')
    hide(start); hide(codeStep); show(linkStep)
    document.getElementById('hexclave-pilot-link-verify').addEventListener('click', async () => {
      setMessage('Verifying magic link...')
      try {
        const result = await app.signInWithMagicLink(linkCode, { noRedirect: true })
        if (resultError(result)) throw result.error
        await exchange()
      } catch (error) {
        if (!showMfaIfPending(error)) setMessage(error?.humanReadableMessage || 'Magic link was not accepted.')
      }
    })
  }
}
