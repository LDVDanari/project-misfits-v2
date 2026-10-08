'use client';
import { useCallback, useEffect, useState } from 'react';

export const LOGIN_URL = '/api/auth/discord/login?next=' + encodeURIComponent('/checkout');

const LOGIN_ERRORS = {
  not_configured: 'Discord login isn\'t set up yet. Please try again soon.',
  cancelled: 'Discord login was cancelled.',
  expired: 'That login took too long. Please try again.',
  failed: 'Discord login didn\'t work. Please try again.'
};

export function useDiscordAccount() {
  const [state, setState] = useState({ loading: true, user: null, loginAvailable: true });
  const load = useCallback(() => {
    fetch('/api/auth/me', { cache: 'no-store' })
      .then(r => r.json())
      .then(j => setState({ loading: false, user: j.user || null, loginAvailable: j.loginAvailable !== false }))
      .catch(() => setState({ loading: false, user: null, loginAvailable: false }));
  }, []);
  useEffect(() => { load(); }, [load]);
  return { ...state, reload: load };
}

export default function DiscordAccount({ account }) {
  const [error, setError] = useState('');
  useEffect(() => {
    const code = new URLSearchParams(window.location.search).get('login_error');
    if (code) setError(LOGIN_ERRORS[code] || LOGIN_ERRORS.failed);
  }, []);

  const switchAccount = async () => {
    await fetch('/api/auth/logout', { method: 'POST' }).catch(() => {});
    window.location.href = LOGIN_URL;
  };

  if (account.loading) return <div className="discordAccount"><small>Checking your Discord login…</small></div>;

  if (account.user) {
    const u = account.user;
    return (
      <div className="discordAccount linked">
        <img src={u.avatarUrl} alt="" width="44" height="44" />
        <div className="who">
          <small>DELIVERING TO</small>
          <b>{u.username}</b>
          {typeof u.coins === 'number' && <span>{u.coins} Misfit Coins on this account</span>}
        </div>
        <button type="button" onClick={switchAccount}>SWITCH</button>
      </div>
    );
  }

  return (
    <div className="discordAccount">
      <p>Log in with the Discord account you play with. Coins and packages are delivered to that account in the city.</p>
      {account.loginAvailable
        ? <a className="primary discordLogin" href={LOGIN_URL}>LOG IN WITH DISCORD</a>
        : <p className="checkoutError">Discord login isn&apos;t available yet. Please try again soon.</p>}
      {error && <p className="checkoutError">{error}</p>}
    </div>
  );
}
