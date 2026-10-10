'use strict';

// Dynamic text is always inserted with textContent, never innerHTML. The only
// innerHTML use is for the constant SVG icons below, which contain no data.

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'pmv2_store';
const $ = (id) => document.getElementById(id);

const ICONS = {
    home: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M12 3 2.5 11h2.8v9h5.2v-6h3v6h5.2v-9h2.8z"/></svg>',
    box: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M12 2.8 20.5 7.5v9L12 21.2 3.5 16.5v-9z"/><path d="M3.5 7.5 12 12.2l8.5-4.7M12 12.2v9"/></svg>',
    target: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="9"/><circle cx="12" cy="12" r="5"/><circle cx="12" cy="12" r="1.4" fill="currentColor"/></svg>',
    gear: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><circle cx="12" cy="12" r="3.2"/><path d="M19.4 13.5a7.6 7.6 0 0 0 0-3l2-1.6-2-3.4-2.4 1a7.5 7.5 0 0 0-2.6-1.5L14 2.5h-4l-.4 2.5A7.5 7.5 0 0 0 7 6.5l-2.4-1-2 3.4 2 1.6a7.6 7.6 0 0 0 0 3l-2 1.6 2 3.4 2.4-1a7.5 7.5 0 0 0 2.6 1.5l.4 2.5h4l.4-2.5a7.5 7.5 0 0 0 2.6-1.5l2.4 1 2-3.4z"/></svg>',
    car: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M3 15.5V12l2.2-5h13.6L21 12v3.5"/><path d="M3 12h18M2.5 15.5h19v2.5h-19z"/><circle cx="7" cy="18" r="1.6"/><circle cx="17" cy="18" r="1.6"/></svg>',
    gift: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M3.5 8.5h17v4h-17zM5 12.5h14V21H5zM12 8.5V21"/><path d="M12 8.5S10.5 3.5 8 4.5 9 8.5 12 8.5zm0 0s1.5-5 4-4-1 4-4 4z"/></svg>',
    bag: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7" stroke-linejoin="round"><path d="M5 7.5h14l-1 13H6z"/><path d="M9 7.5V6a3 3 0 0 1 6 0v1.5"/></svg>',
    star: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="m12 2.8 2.8 5.9 6.4.8-4.7 4.4 1.2 6.4L12 17.2l-5.7 3.1 1.2-6.4-4.7-4.4 6.4-.8z"/></svg>',
    coin: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.7"><circle cx="12" cy="12" r="9"/><path d="M9 9.5h4.5a2 2 0 0 1 0 4H10.5a2 2 0 0 0 0 4H15M12 7.5v2M12 17.5v-2"/></svg>',
    gem: '<svg viewBox="0 0 24 24" fill="currentColor"><path d="M6.5 3h11L22 9l-10 12L2 9z" opacity=".9"/><path d="M2 9h20M12 21 8.5 9 11 3M12 21l3.5-12L13 3" stroke="rgba(0,0,0,.25)" stroke-width="1" fill="none"/></svg>',
};

const state = {
    data: null,
    page: null,
    cart: new Map(),             // item id -> qty
    method: 'credits',
    search: '',
    busy: false,
    prefs: { confirm: true, reduceMotion: false, scale: 1 },
};

// ── helpers ──────────────────────────────────────────────────
function el(tag, cls, text) {
    const n = document.createElement(tag);
    if (cls) n.className = cls;
    if (text !== undefined && text !== null) n.textContent = text;
    return n;
}
function icon(name, cls) {
    const s = el('span', cls || '');
    s.innerHTML = ICONS[name] || ICONS.box;   // constant markup only
    return s;
}
async function post(name, body) {
    try {
        const r = await fetch(`https://${RES}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(body || {}),
        });
        return await r.json();
    } catch (e) {
        return null;
    }
}
const t = (key, fallback) => (state.data && state.data.ui && state.data.ui[key]) || fallback || key;
const fmt = (n) => Number(n || 0).toLocaleString('en-US');

function toast(msg, kind) {
    const n = el('div', 'toast ' + (kind || ''), msg);
    $('toasts').appendChild(n);
    setTimeout(() => n.remove(), 4200);
}
function fmtDate(sec) {
    return new Date(sec * 1000).toLocaleDateString(undefined, { year: 'numeric', month: 'short', day: 'numeric' });
}
function resolveImage(img) {
    if (!img) return null;
    if (/^(https?:|nui:)/i.test(img)) return img;
    if (img.includes('/')) return img;
    return (state.data.imageBase || '') + img;
}
function imageOr(img, rarityIcon) {
    const src = resolveImage(img);
    if (!src) return icon(rarityIcon || 'gift', 'ph');
    const im = document.createElement('img');
    im.alt = '';
    im.src = src;
    im.onerror = () => im.replaceWith(icon(rarityIcon || 'gift', 'ph'));
    return im;
}

// ── preferences (per player, stored in the NUI's own localStorage) ──
function loadPrefs() {
    try {
        const raw = localStorage.getItem('misfits_vip_prefs');
        if (raw) Object.assign(state.prefs, JSON.parse(raw));
    } catch (e) { /* storage unavailable: keep defaults */ }
}
function savePrefs() {
    try { localStorage.setItem('misfits_vip_prefs', JSON.stringify(state.prefs)); } catch (e) { /* ignore */ }
    applyPrefs();
}
function applyPrefs() {
    document.body.classList.toggle('reduce-motion', !!state.prefs.reduceMotion);
    fitFrame();
}
function fitFrame() {
    const fit = Math.min(window.innerWidth * 0.95 / 1240, window.innerHeight * 0.93 / 690, 1.4);
    document.documentElement.style.setProperty('--scale', String(fit * (state.prefs.scale || 1)));
}
window.addEventListener('resize', fitFrame);

// ── theme ────────────────────────────────────────────────────
function applyTheme(th) {
    const root = document.documentElement.style;
    for (const k in (th.colors || {})) root.setProperty('--' + k, th.colors[k]);
    for (const r in (th.rarity || {})) root.setProperty('--r-' + r, th.rarity[r]);
    $('brandA').textContent = th.brandA || '';
    $('brandB').textContent = th.brandB || '';
    $('tagline').textContent = th.tagline || '';
    const logo = $('logo');
    logo.style.visibility = 'visible';
    logo.onerror = () => { logo.style.visibility = 'hidden'; };
    logo.src = th.logo || 'img/logo.png';
    const ws = $('webstore');
    ws.textContent = th.webstoreLabel || '';
    ws.classList.toggle('hidden', !th.webstoreUrl);
}

// ── derived ──────────────────────────────────────────────────
const itemById = (id) => state.data.items.find((i) => i.id === id);
const pageById = (id) => state.data.pages.find((p) => p.id === id);
const methods = () => (state.data.economy.mode === 'both' ? ['credits', 'voucher'] : [state.data.economy.mode]);
const totalPicks = () => state.data.player.vouchers.reduce((s, v) => s + v.left, 0);
const balance = () => (state.method === 'voucher' ? totalPicks() : state.data.player.credits);
const unitOf = (item) => (state.method === 'voucher' ? item.pickCost : item.price);
const currencyName = () => (state.method === 'voucher' ? t('picks') : state.data.economy.creditsName);

function buyable(item) {
    if (item.locked || item.soldOut) return false;
    return state.method === 'voucher' ? !!item.canVoucher : !!item.canCredits;
}
function cartEntries() {
    return [...state.cart.entries()].map(([id, qty]) => ({ item: itemById(id), qty })).filter((e) => e.item);
}
function cartTotal(entries) {
    return entries.reduce((s, { item, qty }) => s + (unitOf(item) || 0) * qty, 0);
}
function cartCount() {
    let n = 0; state.cart.forEach((q) => { n += q; }); return n;
}

function priceTag(item) {
    const p = el('span', 'price');
    if (state.method === 'voucher') {
        p.textContent = `${item.pickCost ?? '-'} ${t('picks')}`;
    } else {
        p.appendChild(icon('gem'));
        p.appendChild(document.createTextNode(item.price != null ? fmt(item.price) : '-'));
    }
    return p;
}

// ── chrome ───────────────────────────────────────────────────
function renderNav() {
    const nav = $('nav');
    nav.replaceChildren();
    state.data.pages.forEach((p) => {
        const b = el('button', 'nav-btn' + (state.page === p.id ? ' active' : ''));
        b.append(icon(p.icon), el('span', '', p.label));
        b.onclick = () => { if (state.page !== p.id) { state.page = p.id; state.search = ''; renderPage(); renderNav(); } };
        nav.appendChild(b);
    });
}
function renderCoins() {
    const mode = state.data.economy.mode;
    $('gem').innerHTML = ICONS.gem;
    if (mode === 'voucher') {
        $('coinValue').textContent = fmt(totalPicks());
        $('coinName').textContent = t('picks');
    } else {
        $('coinValue').textContent = fmt(state.data.player.credits);
        $('coinName').textContent = state.data.economy.creditsName;
    }
}

// ── pages ────────────────────────────────────────────────────
function openWebstore() {
    const url = state.data && state.data.theme && state.data.theme.webstoreUrl;
    if (!url) return;
    if (typeof window.invokeNative === 'function') window.invokeNative('openUrl', url);
    else window.open(url, '_blank');
}

function pageHome() {
    const h = state.data.hero || {};
    const p = state.data.player;
    const wrap = el('div', 'hero');
    const left = el('div');
    left.appendChild(el('div', 'kicker', h.kicker || ''));
    const h1 = el('h1');
    (h.title || []).forEach((line, i) => { if (i) h1.appendChild(document.createElement('br')); h1.appendChild(document.createTextNode(line)); });
    left.appendChild(h1);
    if (h.text) left.appendChild(el('p', '', h.text));
    if (h.note && h.note.length) {
        const note = el('div', 'note');
        h.note.forEach((line, i) => { if (i) note.appendChild(document.createElement('br')); note.appendChild(document.createTextNode(line)); });
        left.appendChild(note);
    }

    // balance card: same wallet as the webstore and /coins
    const card = el('div', 'redeem-card home-card');
    card.appendChild(el('div', 'hint', t('home_balance')));
    const bal = el('div', 'home-balance');
    bal.append(icon('gem'), el('b', '', fmt(p.credits)));
    card.appendChild(bal);
    card.appendChild(el('h2', '', state.data.economy.creditsName));
    if (p.tier) {
        const tier = el('div', 'home-tier', `${p.tierLabel} VIP · ${p.expiresAt ? fmtDate(p.expiresAt) : t('lifetime')}`);
        if (p.tierColor) tier.style.color = p.tierColor;
        card.appendChild(tier);
    }
    card.appendChild(el('div', 'hint' + (p.noDiscord ? ' warn' : ''), p.noDiscord ? t('home_no_discord') : t('home_hint')));

    const firstShop = state.data.pages.find((pg) => pg.kind === 'category');
    if (firstShop) {
        const shop = el('button', 'btn-cyan', t('home_shop'));
        shop.onclick = () => { state.page = firstShop.id; state.search = ''; renderNav(); renderPage(); };
        card.appendChild(shop);
    }
    if (state.data.theme && state.data.theme.webstoreUrl) {
        const buy = el('button', 'btn-ghost wide', t('home_buy'));
        buy.onclick = openWebstore;
        card.appendChild(buy);
    }

    wrap.append(left, card);
    return wrap;
}

function makeCard(item, idx) {
    const can = buyable(item);
    const card = el('div', 'card' + (state.cart.has(item.id) ? ' in-basket' : '') + (can ? '' : ' off'));
    card.style.setProperty('--rc', `var(--r-${item.rarity})`);
    card.style.animationDelay = `${Math.min(idx, 12) * 25}ms`;

    if (item.locked) card.appendChild(el('div', 'badge lock', item.minTierLabel ? `${item.minTierLabel} VIP` : t('locked')));
    else if (item.soldOut) card.appendChild(el('div', 'badge own', t('owned')));

    const img = el('div', 'img');
    img.appendChild(imageOr(item.image));
    card.appendChild(img);

    const body = el('div', 'body');
    body.append(el('div', 'rar', item.rarity), el('h3', '', item.label));
    if (item.description) body.appendChild(el('p', '', item.description));
    const foot = el('div', 'foot');
    foot.appendChild(priceTag(item));
    const inCart = state.cart.has(item.id);
    const add = el('button', 'add' + (inCart ? ' on' : ''), inCart ? t('added') : t('add'));
    add.disabled = !can;
    add.onclick = () => {
        if (state.cart.has(item.id)) state.cart.delete(item.id);
        else state.cart.set(item.id, 1);
        renderPage();
    };
    if (item.locked) add.title = item.lockReason || '';
    foot.appendChild(add);
    body.appendChild(foot);
    card.appendChild(body);
    return card;
}

function basketPanel() {
    const box = el('div', 'basket');
    box.appendChild(el('h3', '', t('basket')));

    const list = el('div', 'basket-list');
    const entries = cartEntries();
    if (!entries.length) list.appendChild(el('div', 'empty', t('basket_empty')));
    entries.forEach(({ item, qty }) => {
        const row = el('div', 'b-row');
        row.appendChild(el('span', 'nm', item.label));
        if (item.stackable && item.maxQty > 1) {
            const q = el('div', 'qty');
            const minus = el('button', 'mini', '−');
            const plus = el('button', 'mini', '+');
            minus.onclick = () => { state.cart.set(item.id, Math.max(1, qty - 1)); renderPage(); };
            plus.onclick = () => { state.cart.set(item.id, Math.min(item.maxQty, qty + 1)); renderPage(); };
            q.append(minus, el('span', '', String(qty)), plus);
            row.appendChild(q);
        }
        row.appendChild(el('span', 'pr', fmt((unitOf(item) || 0) * qty)));
        const rm = el('button', 'mini x', '✕');
        rm.onclick = () => { state.cart.delete(item.id); renderPage(); };
        row.appendChild(rm);
        list.appendChild(row);
    });
    box.appendChild(list);

    if (methods().length > 1) {
        const pay = el('div', 'pay');
        methods().forEach((m) => {
            const b = el('button', state.method === m ? 'on' : '', m === 'voucher' ? t('picks') : state.data.economy.creditsName);
            b.onclick = () => { state.method = m; renderAll(); };
            pay.appendChild(b);
        });
        box.appendChild(pay);
    }

    const total = cartTotal(entries);
    const bal = balance();
    const s1 = el('div', 'sum'); s1.append(el('span', '', t('total')), el('b', '', `${fmt(total)} ${currencyName()}`));
    const s2 = el('div', 'sum'); s2.append(el('span', '', t('balance')), el('b', '', fmt(bal)));
    const s3 = el('div', 'sum' + (total > bal ? ' bad' : '')); s3.append(el('span', '', t('after')), el('b', '', fmt(bal - total)));
    box.append(s1, s2, s3);

    const valid = entries.length > 0 && total <= bal && entries.every(({ item }) => buyable(item))
        && cartCount() <= (state.data.maxCart || 10);
    const btn = el('button', 'btn-cyan', t('purchase'));
    btn.disabled = !valid || state.busy;
    btn.onclick = () => checkout(entries);
    box.appendChild(btn);
    return box;
}

function pageCategory(page) {
    const wrap = el('div', 'shop');
    const main = el('div', 'shop-main');
    const head = el('div', 'shop-head');
    const titles = el('div');
    titles.append(el('div', 'kicker', state.data.store.label || ''), el('h2', '', page.label));
    const search = document.createElement('input');
    search.className = 'search';
    search.placeholder = t('search');
    search.value = state.search;
    search.oninput = () => { state.search = search.value; renderGrid(gridWrap, page); };
    head.append(titles, search);

    const gridWrap = el('div', 'grid-wrap');
    renderGrid(gridWrap, page);
    main.append(head, gridWrap);
    wrap.append(main, basketPanel());
    return wrap;
}

function renderGrid(container, page) {
    container.replaceChildren();
    const q = state.search.trim().toLowerCase();
    const items = state.data.items.filter((i) => i.category === page.category
        && (!q || i.label.toLowerCase().includes(q) || (i.description || '').toLowerCase().includes(q)));
    if (!items.length) { container.appendChild(el('div', 'empty', t('no_items'))); return; }
    const grid = el('div', 'grid');
    items.forEach((item, i) => grid.appendChild(makeCard(item, i)));
    container.appendChild(grid);
}

function pageVehicle(page) {
    const item = itemById(page.item);
    const wrap = el('div', 'vehicle');
    if (!item) { wrap.appendChild(el('div', 'empty', t('no_items'))); return wrap; }
    wrap.style.setProperty('--rc', `var(--r-${item.rarity})`);

    const left = el('div');
    left.appendChild(el('div', 'kicker', t('showroom_kicker')));
    left.appendChild(el('h1', '', item.label));
    left.appendChild(el('div', 'rar', item.rarity));
    if (item.description) left.appendChild(el('p', '', item.description));
    if (item.specs && item.specs.length) {
        const specs = el('div', 'specs');
        item.specs.forEach(([k, v]) => {
            const s = el('div', 'spec');
            s.append(el('small', '', k), el('b', '', v));
            specs.appendChild(s);
        });
        left.appendChild(specs);
    }

    const card = el('div', 'v-card');
    const img = el('div', 'v-img');
    img.appendChild(imageOr(item.image, 'car'));
    card.appendChild(img);
    const pr = el('div', 'v-price');
    pr.append(priceTag(item), el('span', 'kicker', item.limit ? `${item.owned}/${item.limit}` : ''));
    card.appendChild(pr);
    if (item.locked) card.appendChild(el('div', 'lock-msg', item.lockReason || t('locked')));
    else if (item.soldOut) card.appendChild(el('div', 'lock-msg', t('owned')));
    const cost = unitOf(item) || 0;
    const btn = el('button', 'btn-cyan', t('buy_vehicle'));
    btn.disabled = !buyable(item) || cost > balance() || state.busy;
    btn.onclick = () => checkout([{ item, qty: 1 }]);
    card.appendChild(btn);
    card.appendChild(el('div', 'v-note', t('vehicle_note')));

    wrap.append(left, card);
    return wrap;
}

function pageSettings() {
    const p = state.data.player;
    const wrap = el('div', 'settings');

    const acc = el('div', 's-card');
    acc.appendChild(el('span', 'kicker', t('settings_account')));
    const row = (k, v, color) => {
        const r = el('div', 's-row');
        const val = el('span', '', v);
        if (color) val.style.color = color;
        r.append(el('span', '', k), val);
        return r;
    };
    acc.appendChild(row('Character', p.name));
    acc.appendChild(row(t('vip_tier'), p.tierLabel || t('none'), p.tierColor));
    if (p.tier) acc.appendChild(row(t('expires'), p.expiresAt ? fmtDate(p.expiresAt) : t('lifetime')));
    if (state.data.economy.mode !== 'voucher') acc.appendChild(row(state.data.economy.creditsName, fmt(p.credits)));
    if (state.data.economy.mode !== 'credits') acc.appendChild(row(t('picks'), fmt(totalPicks())));

    const prefs = el('div', 's-card');
    prefs.appendChild(el('span', 'kicker', t('settings_prefs')));
    const toggle = (label, key) => {
        const r = el('div', 's-row');
        const b = el('button', 'toggle' + (state.prefs[key] ? ' on' : ''));
        b.onclick = () => { state.prefs[key] = !state.prefs[key]; savePrefs(); renderPage(); };
        r.append(el('span', '', label), b);
        return r;
    };
    prefs.appendChild(toggle(t('pref_confirm'), 'confirm'));
    prefs.appendChild(toggle(t('pref_motion'), 'reduceMotion'));
    const sr = el('div', 's-row');
    const seg = el('div', 'seg');
    [['S', 0.9], ['M', 1], ['L', 1.1]].forEach(([lbl, v]) => {
        const b = el('button', state.prefs.scale === v ? 'on' : '', lbl);
        b.onclick = () => { state.prefs.scale = v; savePrefs(); renderPage(); };
        seg.appendChild(b);
    });
    sr.append(el('span', '', t('pref_scale')), seg);
    prefs.appendChild(sr);

    wrap.append(acc, prefs);
    return wrap;
}

function renderPage() {
    const page = pageById(state.page) || state.data.pages[0];
    const host = $('page');
    host.replaceChildren();
    host.style.animation = 'none'; void host.offsetWidth; host.style.animation = '';
    let node;
    if (page.kind === 'home' || page.kind === 'redeem') node = pageHome();
    else if (page.kind === 'category') node = pageCategory(page);
    else if (page.kind === 'vehicle') node = pageVehicle(page);
    else node = pageSettings();
    host.appendChild(node);
}

function renderAll() {
    if (!state.data) return;
    renderNav(); renderCoins(); renderPage();
}

// ── checkout ─────────────────────────────────────────────────
function checkout(entries) {
    if (!state.prefs.confirm) return doCheckout(entries);
    const modal = $('modal');
    modal.replaceChildren();
    const box = el('div', 'box');
    const total = cartTotal(entries);
    box.append(el('h3', '', t('confirm')), el('p', '', t('confirm_text').replace('%s', `${fmt(total)} ${currencyName()}`)));
    const ul = el('ul');
    entries.forEach(({ item, qty }) => {
        const li = el('li');
        li.append(el('span', '', qty > 1 ? `${qty}× ${item.label}` : item.label), el('span', '', fmt((unitOf(item) || 0) * qty)));
        ul.appendChild(li);
    });
    box.appendChild(ul);
    const actions = el('div', 'actions');
    const cancel = el('button', 'btn-ghost', t('cancel'));
    const ok = el('button', 'btn-cyan', t('confirm'));
    cancel.onclick = () => modal.classList.add('hidden');
    ok.onclick = () => { modal.classList.add('hidden'); doCheckout(entries); };
    actions.append(cancel, ok);
    box.appendChild(actions);
    modal.appendChild(box);
    modal.classList.remove('hidden');
}

async function doCheckout(entries) {
    if (state.busy) return;
    state.busy = true; renderPage();
    const cart = entries.map(({ item, qty }) => ({ id: item.id, qty }));
    const res = await post('purchase', { cart, method: state.method });
    state.busy = false;

    if (!res) { toast('No response from server.', 'bad'); renderPage(); return; }
    if (res.message && (!res.results || !res.results.length)) toast(res.message, 'bad');
    (res.results || []).forEach((r) => {
        toast(`${r.label}: ${r.message}`, r.ok ? 'good' : 'bad');
        if (r.ok) state.cart.delete(r.id);
    });
    await refresh();
}

async function refresh() {
    const fresh = await post('refresh');
    if (fresh) {
        state.data = fresh;
        [...state.cart.keys()].forEach((id) => { const i = itemById(id); if (!i || !buyable(i)) state.cart.delete(id); });
    }
    renderAll();
}

// ── lifecycle ────────────────────────────────────────────────
function openUI(data) {
    state.data = data;
    state.cart.clear();
    state.search = '';
    state.busy = false;
    state.method = methods()[0];
    state.page = data.startPage || (data.pages[0] && data.pages[0].id);
    loadPrefs();
    applyTheme(data.theme || {});
    applyPrefs();
    $('modal').classList.add('hidden');
    $('app').classList.remove('hidden');
    renderAll();
}
function closeUI() {
    $('app').classList.add('hidden');
    $('modal').classList.add('hidden');
    $('toasts').replaceChildren();
}

$('closeBtn').addEventListener('click', () => post('close'));
$('webstore').addEventListener('click', openWebstore);
document.addEventListener('keydown', (e) => {
    if (e.key !== 'Escape' || $('app').classList.contains('hidden')) return;
    const modal = $('modal');
    if (!modal.classList.contains('hidden')) { modal.classList.add('hidden'); return; }
    post('close');
});
window.addEventListener('message', (e) => {
    const m = e.data;
    if (!m || !m.action) return;
    if (m.action === 'open') openUI(m.data);
    else if (m.action === 'close') closeUI();
});
