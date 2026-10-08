'use client';
import { useCallback, useEffect, useRef, useState } from 'react';
import LeanPourCanvas from './LeanPourCanvas';
import styles from './StoreIntro.module.css';
import { createFileTrack, createIntroBeat } from '../lib/introBeat';

const SEEN_KEY = 'pmv2-intro-v9-seen';
const VOLUME_KEY = 'pmv2-intro-volume';
const TRACK_URL = process.env.NEXT_PUBLIC_INTRO_AUDIO_URL || '';
const TRACK_TITLE = process.env.NEXT_PUBLIC_INTRO_AUDIO_TITLE || (TRACK_URL ? 'Store intro' : 'Misfits After Dark');
const TRACK_ARTIST = TRACK_URL ? (process.env.NEXT_PUBLIC_INTRO_AUDIO_ARTIST || '') : 'PMv2 Original';
const ENTER_MS = 2150; // matches the purple pour

// Where things sit on the artwork (fractions of the 2560x1441 image).
const LOGO = { x: 0.2656, y: 0.0694, w: 0.4492, h: 0.6246 };
const DRIP_TIPS = [[0.0039,0.1069],[0.0156,0.1722],[0.025,0.2819],[0.0891,0.3931],[0.0922,0.3403],[0.1125,0.0639],[0.1234,0.1014],[0.1344,0.1847],[0.1367,0.3042],[0.1391,0.2583],[0.1406,0.3417],[0.1523,0.2528],[0.1633,0.1236],[0.1984,0.1722],[0.2062,0.0722],[0.2266,0.3778],[0.2312,0.0944],[0.3078,0.1944],[0.3109,0.2806],[0.3141,0.1875],[0.332,0.375],[0.3719,0.1292],[0.457,0.2306],[0.4695,0.1736],[0.4758,0.1111],[0.4766,0.2042],[0.5062,0.1556],[0.5211,0.2042],[0.5289,0.3625],[0.5445,0.2431],[0.5859,0.2583],[0.618,0.1444],[0.6438,0.2667],[0.675,0.1819],[0.7203,0.3639],[0.7281,0.1583],[0.7305,0.3111],[0.75,0.0931],[0.8047,0.0667],[0.8242,0.3514],[0.8688,0.0708],[0.8938,0.1597],[0.9,0.2375],[0.9086,0.1431],[0.975,0.1611]];
const SPARKLES = [[0.8105,0.8903],[0.3725,0.194],[0.7962,0.8794],[0.373,0.113],[0.1934,0.506],[0.593,0.6552],[0.6199,0.2549],[0.1966,0.2405],[0.6477,0.065],[0.3732,0.3528],[0.8149,0.8035],[0.7933,0.9293],[0.6373,0.2285],[0.5115,0.0389],[0.5608,0.4242],[0.2176,0.8792],[0.7059,0.4729],[0.7109,0.066],[0.9808,0.1344],[0.0305,0.1549],[0.5278,0.2248],[0.677,0.334],[0.647,0.5969],[0.5634,0.4178],[0.6922,0.0941],[0.6395,0.6784],[0.1306,0.1633],[0.3094,0.5295],[0.9744,0.1319],[0.4148,0.5965],[0.6066,0.3104],[0.8083,0.8296],[0.7241,0.0958],[0.5578,0.1792],[0.6652,0.5951],[0.5133,0.6458],[0.3596,0.4451],[0.5528,0.3878],[0.2934,0.0263],[0.1062,0.0181],[0.5062,0.4583],[0.5247,0.3378],[0.2898,0.9471],[0.048,0.8785],[0.8953,0.7762],[0.7041,0.9118],[0.6909,0.0852],[0.4448,0.5014],[0.8898,0.1993],[0.1236,0.4281],[0.2669,0.9054],[0.2106,0.5998],[0.9002,0.2342],[0.6436,0.2217],[0.1459,0.3314],[0.7555,0.8076],[0.7829,0.7881],[0.4293,0.6021],[0.6617,0.5007],[0.6812,0.3418]];

const TITLE_A = 'PROJECT MISFITS';
const TITLE_B = 'STORE';

function Letters({ text, offset = 0 }) {
  return [...text].map((ch, i) => (
    <span key={i} className={styles.letter} style={{ '--i': offset + i }}>{ch === ' ' ? ' ' : ch}</span>
  ));
}

export default function StoreIntro() {
  const [visible, setVisible] = useState(false);
  const [ready, setReady] = useState(false);
  const [entering, setEntering] = useState(false);
  const [playing, setPlaying] = useState(false);
  const [muted, setMuted] = useState(false);
  const [volume, setVolume] = useState(55);
  const [needsTap, setNeedsTap] = useState(false);

  const rootRef = useRef(null), stageRef = useRef(null), logoRef = useRef(null), bloomRef = useRef(null);
  const fxRef = useRef(null), eqRef = useRef(null), enterRef = useRef(null);
  const audioRef = useRef(null), userPausedRef = useRef(false), kickRef = useRef(0);
  const mouse = useRef({ x: 0, y: 0, sx: 0, sy: 0 });

  // ---- show once per browser session ----
  useEffect(() => {
    try { if (sessionStorage.getItem(SEEN_KEY)) return; } catch { /* storage blocked */ }
    try { const v = Number(localStorage.getItem(VOLUME_KEY)); if (v >= 0 && v <= 100 && localStorage.getItem(VOLUME_KEY) !== null) setVolume(v); } catch { /* storage blocked */ }
    setVisible(true);
    document.documentElement.classList.add('introLocked');
    return () => document.documentElement.classList.remove('introLocked');
  }, []);

  // ---- wait for the art, then run the entrance ----
  useEffect(() => {
    if (!visible) return;
    const srcs = ['/images/intro/intro-bg.webp', '/images/intro/intro-logo.webp'];
    let done = false;
    const go = () => { if (!done) { done = true; setReady(true); } };
    Promise.all(srcs.map(src => new Promise(res => { const im = new Image(); im.onload = im.onerror = res; im.src = src; }))).then(go);
    const t = setTimeout(go, 2500);
    return () => clearTimeout(t);
  }, [visible]);


  // ---- music ----
  const startMusic = useCallback(async () => {
    if (!audioRef.current) audioRef.current = TRACK_URL ? createFileTrack(TRACK_URL) : createIntroBeat();
    const a = audioRef.current;
    if (!a) return;
    a.setVolume(muted ? 0 : volume / 100);
    const ok = await a.start();
    setPlaying(ok);
    setNeedsTap(!ok);
  }, [muted, volume]);

  useEffect(() => {
    if (!ready) return;
    const t = setTimeout(() => { if (!userPausedRef.current) startMusic(); }, 900);
    return () => clearTimeout(t);
  }, [ready]); // eslint-disable-line react-hooks/exhaustive-deps

  useEffect(() => {
    audioRef.current?.setVolume(muted ? 0 : volume / 100);
    try { localStorage.setItem(VOLUME_KEY, String(volume)); } catch { /* storage blocked */ }
  }, [volume, muted]);

  useEffect(() => () => { audioRef.current?.destroy(); }, []);

  const togglePlay = async () => {
    const a = audioRef.current;
    if (!a || !playing) { userPausedRef.current = false; await startMusic(); return; }
    userPausedRef.current = true;
    a.pause();
    setPlaying(false);
  };

  // Browsers only allow sound after a tap: the first tap anywhere starts it.
  const onFirstTouch = e => {
    if (e.target.closest?.('.' + styles.player)) return; // the player's own buttons handle themselves
    if (!playing && !userPausedRef.current) startMusic();
  };

  // ---- enter the store ----
  const enter = useCallback(() => {
    if (entering) return;
    setEntering(true);
    try { sessionStorage.setItem(SEEN_KEY, '1'); } catch { /* storage blocked */ }
    audioRef.current?.exit();
    setTimeout(() => {
      setVisible(false);
      document.documentElement.classList.remove('introLocked');
    }, ENTER_MS);
  }, [entering]);

  useEffect(() => {
    if (!visible) return;
    const onKey = e => {
      if (e.key === 'Escape') enter();
      if ((e.key === 'm' || e.key === 'M') && !e.ctrlKey && !e.metaKey) setMuted(v => !v);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [visible, enter]);

  // ---- animation loop: beat pulse, parallax, drips, sparkles, EQ ----
  useEffect(() => {
    if (!visible) return;
    const reduce = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const fx = fxRef.current, eq = eqRef.current;
    const g = fx.getContext('2d'), eg = eq.getContext('2d');
    let raf = 0, last = performance.now(), dripTimer = 0.6, W = 0, H = 0, dpr = 1;
    const drops = [], flashes = [];
    const tw = SPARKLES.map(() => ({ ph: Math.random() * Math.PI * 2, sp: 0.6 + Math.random() * 1.4, boost: 0 }));
    const eqBars = new Float32Array(18);
    const freq = new Uint8Array(128);

    const size = () => {
      const r = stageRef.current.getBoundingClientRect();
      dpr = Math.min(window.devicePixelRatio || 1, 1.75);
      W = r.width; H = r.height;
      fx.width = Math.round(W * dpr); fx.height = Math.round(H * dpr);
      g.setTransform(dpr, 0, 0, dpr, 0, 0);
      const er = eq.getBoundingClientRect();
      eq.width = Math.round(er.width * dpr); eq.height = Math.round(er.height * dpr);
      eg.setTransform(dpr, 0, 0, dpr, 0, 0);
    };
    size();
    window.addEventListener('resize', size);
    const onMove = e => { mouse.current.x = e.clientX / window.innerWidth * 2 - 1; mouse.current.y = e.clientY / window.innerHeight * 2 - 1; };
    window.addEventListener('pointermove', onMove);

    const spawnDrip = (big) => {
      const [x, y] = DRIP_TIPS[(Math.random() * DRIP_TIPS.length) | 0];
      drops.push({ x: x * W, y: y * H, r: 0, max: (big ? 5 : 3 + Math.random() * 2.5) * (W / 1600), grow: 0.35 + Math.random() * 0.5, vy: 0, fall: false, a: 1, dist: 0 });
    };

    const frame = now => {
      const dt = Math.min(0.05, (now - last) / 1000);
      last = now;
      const a = audioRef.current;

      // beat cues
      if (a) for (const ev of a.takeEvents()) {
        if (ev.type === 'kick') {
          kickRef.current = Math.max(kickRef.current, ev.v);
          if (!reduce) { spawnDrip(true); for (let k = 0; k < 3; k++) tw[(Math.random() * tw.length) | 0].boost = 1; }
        } else if (ev.type === 'snare') {
          kickRef.current = Math.max(kickRef.current, 0.45);
          flashes.push({ t: 0 });
        }
      }
      kickRef.current *= Math.exp(-dt * 7);
      const k = reduce ? 0 : kickRef.current;

      // logo + glow follow the beat
      if (logoRef.current) {
        logoRef.current.style.transform = `scale(${(1 + k * 0.035).toFixed(4)})`;
        logoRef.current.style.filter = `brightness(${(1 + k * 0.32).toFixed(3)}) saturate(${(1 + k * 0.25).toFixed(3)})`;
      }
      if (bloomRef.current) bloomRef.current.style.opacity = (0.28 + k * 0.55).toFixed(3);

      // parallax
      const m = mouse.current;
      m.sx += (m.x - m.sx) * Math.min(1, dt * 2.5);
      m.sy += (m.y - m.sy) * Math.min(1, dt * 2.5);
      if (stageRef.current && !reduce) stageRef.current.style.setProperty('--px', `${(-m.sx * 12).toFixed(2)}px`), stageRef.current.style.setProperty('--py', `${(-m.sy * 8).toFixed(2)}px`);

      // drips + sparkles
      g.clearRect(0, 0, W, H);
      if (!reduce) {
        dripTimer -= dt;
        if (dripTimer <= 0) { spawnDrip(false); dripTimer = 0.35 + Math.random() * 0.75; }
      }
      for (let i = drops.length - 1; i >= 0; i--) {
        const d = drops[i];
        if (!d.fall) { d.r = Math.min(d.max, d.r + (d.max / d.grow) * dt); if (d.r >= d.max) d.fall = true; }
        else { d.vy += 1600 * (H / 900) * dt; d.y += d.vy * dt; d.dist += d.vy * dt; if (d.dist > H * 0.18) d.a -= dt * 2.2; }
        if (d.a <= 0 || d.y > H) { drops.splice(i, 1); continue; }
        const st = d.fall ? 1 + Math.min(2.2, d.vy / 600) : 1 + (d.r / d.max) * 0.5;
        const gr = g.createRadialGradient(d.x - d.r * 0.3, d.y - d.r * 0.4, d.r * 0.1, d.x, d.y, d.r * 1.4);
        gr.addColorStop(0, `rgba(255,214,255,${d.a})`);
        gr.addColorStop(0.35, `rgba(196,64,255,${d.a * 0.95})`);
        gr.addColorStop(1, `rgba(98,0,150,${d.a * 0.85})`);
        g.fillStyle = gr;
        g.beginPath(); g.ellipse(d.x, d.y + d.r * st * 0.4, d.r, d.r * st, 0, 0, Math.PI * 2); g.fill();
      }
      g.globalCompositeOperation = 'lighter';
      tw.forEach((s, i) => {
        s.boost *= Math.exp(-dt * 3);
        const base = Math.max(0, Math.sin(now / 1000 * s.sp + s.ph)) ** 8;
        const v = reduce ? base * 0.4 : Math.min(1, base + s.boost);
        if (v < 0.04) return;
        const [x, y] = SPARKLES[i], px = x * W, py = y * H, len = (6 + v * 16) * (W / 1600);
        g.globalAlpha = v;
        const rg = g.createRadialGradient(px, py, 0, px, py, len);
        rg.addColorStop(0, 'rgba(255,255,255,1)'); rg.addColorStop(0.25, 'rgba(240,190,255,0.6)'); rg.addColorStop(1, 'rgba(200,90,255,0)');
        g.fillStyle = rg;
        g.fillRect(px - len, py - 1, len * 2, 2);
        g.fillRect(px - 1, py - len, 2, len * 2);
        g.beginPath(); g.arc(px, py, len * 0.28, 0, Math.PI * 2); g.fill();
      });
      for (let i = flashes.length - 1; i >= 0; i--) {
        const f = flashes[i]; f.t += dt;
        if (f.t > 0.25) { flashes.splice(i, 1); continue; }
        g.globalAlpha = (1 - f.t / 0.25) * 0.12;
        g.fillStyle = '#d06bff'; g.fillRect(0, 0, W, H);
      }
      g.globalAlpha = 1;
      g.globalCompositeOperation = 'source-over';

      // EQ bars in the music pill
      const ew = eq.width / dpr, eh = eq.height / dpr;
      eg.clearRect(0, 0, ew, eh);
      const live = a && a.running;
      if (live) a.analyser.getByteFrequencyData(freq);
      const n = eqBars.length, gap = 2, bw = (ew - gap * (n - 1)) / n;
      for (let i = 0; i < n; i++) {
        const target = live ? Math.pow(freq[Math.floor(1 + i * 2.6)] / 255, 1.3) : 0.08 + 0.05 * Math.sin(now / 600 + i);
        eqBars[i] += (target - eqBars[i]) * Math.min(1, dt * (target > eqBars[i] ? 20 : 7));
        const bh = Math.max(2, eqBars[i] * eh);
        const lg = eg.createLinearGradient(0, eh, 0, 0);
        lg.addColorStop(0, '#7a12d6'); lg.addColorStop(1, '#f2c2ff');
        eg.fillStyle = lg;
        eg.fillRect(i * (bw + gap), eh - bh, bw, bh);
      }

      raf = requestAnimationFrame(frame);
    };
    raf = requestAnimationFrame(frame);
    return () => { cancelAnimationFrame(raf); window.removeEventListener('resize', size); window.removeEventListener('pointermove', onMove); };
  }, [visible]);

  if (!visible) return null;

  const cls = [styles.intro, ready && styles.ready, entering && styles.entering].filter(Boolean).join(' ');
  const pct = muted ? 0 : volume;

  return (
    <div ref={rootRef} className={cls} role="dialog" aria-modal="true" aria-label="Welcome to the Project Misfits store" onPointerDownCapture={onFirstTouch}>
      <div ref={stageRef} className={styles.stage}>
        <div className={styles.parallax}>
          <img className={styles.bg} src="/images/intro/intro-bg.webp" alt="" draggable="false" />
          <div className={styles.logoWrap} style={{ left: LOGO.x * 100 + '%', top: LOGO.y * 100 + '%', width: LOGO.w * 100 + '%', height: LOGO.h * 100 + '%' }}>
            <div ref={bloomRef} className={styles.bloom} />
            <div ref={logoRef} className={styles.pulse}>
              <img className={styles.logo} src="/images/intro/intro-logo.webp" alt="Project Misfits v2" draggable="false" />
            </div>
            <div className={styles.shine} />
            <button type="button" className={styles.logoHit} onClick={enter} aria-label="Enter the store" tabIndex={-1} />
          </div>
          <canvas ref={fxRef} className={styles.fx} aria-hidden="true" />
        </div>
      </div>
      <div className={styles.vignette} aria-hidden="true" />

      <button type="button" className={styles.skip} onClick={enter}>Skip intro</button>

      <div className={styles.copy}>
        <p className={styles.welcome}>WELCOME TO</p>
        <h1 className={styles.title}>
          <span className={styles.brand}><Letters text={TITLE_A} /></span>
          <span className={styles.word}><Letters text={TITLE_B} offset={TITLE_A.length + 1} /></span>
        </h1>
        <button ref={enterRef} type="button" className={styles.enter} onClick={enter}>
          <span>ENTER THE STORE</span>
        </button>
        {needsTap && <p className={styles.tap}>Tap anywhere for sound</p>}
      </div>

      <div className={styles.player}>
        <button type="button" className={styles.play} onClick={togglePlay} aria-label={playing ? 'Pause music' : 'Play music'}>
          {playing
            ? <svg viewBox="0 0 24 24" aria-hidden="true"><rect x="6.5" y="5" width="3.6" height="14" rx="1" /><rect x="13.9" y="5" width="3.6" height="14" rx="1" /></svg>
            : <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M8 5.2v13.6a.8.8 0 0 0 1.2.7l10.6-6.8a.8.8 0 0 0 0-1.4L9.2 4.5A.8.8 0 0 0 8 5.2z" /></svg>}
        </button>
        <div className={styles.track}>
          <b>{TRACK_TITLE}</b>
          {TRACK_ARTIST && <small>{TRACK_ARTIST}</small>}
        </div>
        <canvas ref={eqRef} className={styles.eq} aria-hidden="true" />
        <button type="button" className={styles.mute} onClick={() => setMuted(v => !v)} aria-label={muted ? 'Unmute' : 'Mute'}>
          {muted
            ? <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9h4l5-4v14l-5-4H4z" /><path className={styles.stroke} d="M16 9l5 6M21 9l-5 6" /></svg>
            : <svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 9h4l5-4v14l-5-4H4z" /><path className={styles.stroke} d="M16 9.5a3.5 3.5 0 0 1 0 5M18.5 7a7 7 0 0 1 0 10" /></svg>}
        </button>
        <input
          className={styles.volume}
          type="range" min="0" max="100" value={pct}
          style={{ '--v': pct + '%' }}
          onChange={e => { setVolume(Number(e.target.value)); if (muted) setMuted(false); }}
          aria-label="Music volume"
        />
      </div>

      <LeanPourCanvas active={entering} />
    </div>
  );
}
