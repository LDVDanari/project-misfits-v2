'use client';
import { useEffect, useState } from 'react';

const TEBEX_PANEL = 'https://creator.tebex.io';

export default function OwnerStoreAdmin() {
  const [data, setData] = useState(null), [error, setError] = useState('');
  const load = () => {
    setError('');
    fetch('/api/owner/catalog', { cache: 'no-store' })
      .then(r => r.json())
      .then(j => (j.error ? setError(j.error) : setData(j)))
      .catch(() => setError('Could not load the store status.'));
  };
  useEffect(() => { load(); }, []);

  return <section className="ownerStoreAdmin">
    <div className="sectionTitle compact">
      <div><div className="kicker">STORE CONTROL</div><h2>TEBEX <span>STORE.</span></h2></div>
      <p>Payments run through Tebex. Prices, sales, coupons, refunds, payouts and delivery commands are managed in the Tebex control panel.</p>
    </div>

    <div className="actions leftActions">
      <a className="primary" href={TEBEX_PANEL} target="_blank" rel="noreferrer">OPEN TEBEX CONTROL PANEL</a>
      <button className="gold" onClick={load}>REFRESH</button>
    </div>

    {error && <div className="adminStoreMsg">{error}</div>}
    {!data && !error && <div className="fundsLoading">Loading store status…</div>}
    {data && data.configured === false && <div className="notice">TEBEX_PUBLIC_TOKEN isn&apos;t set in Coolify yet, so the store shows everything as COMING SOON.</div>}

    {data?.configured && <>
      <div className="kicker">SITE PRODUCTS</div>
      <p>A site product goes live when a Tebex package has the <b>same name</b> (or is linked in TEBEX_PACKAGE_MAP). Everything else shows COMING SOON.</p>
      <div className="catalogAdminGrid">
        {data.items.map(x => <article key={x.slug} className="catalogAdminCard">
          <div className="catalogAdminHead">
            <div><small>{x.category}</small><h3>{x.title}</h3></div>
            <span className={x.tebex ? 'liveBadge' : 'offBadge'}>{x.tebex ? 'LIVE' : 'NOT IN TEBEX'}</span>
          </div>
          <p>{x.tebex ? <>Tebex package <b>#{x.tebex.id}</b> “{x.tebex.name}” · <b>{x.tebex.price}</b></> : 'No matching Tebex package.'}</p>
        </article>)}
      </div>
      {data.unmatchedTebex.length > 0 && <>
        <div className="kicker">IN TEBEX BUT NOT ON THE SITE</div>
        <p>These Tebex packages don&apos;t match a site product name. Rename them in Tebex to match, or link them with TEBEX_PACKAGE_MAP.</p>
        <div className="promoList">{data.unmatchedTebex.map(p => <article key={p.id}><b>#{p.id}</b><span>{p.name}</span><small>{p.price}</small></article>)}</div>
      </>}
    </>}
  </section>;
}
