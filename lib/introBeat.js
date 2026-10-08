// "Misfits After Dark" - the store intro beat, generated live in the browser.
// No music files and nothing to license: every drum, 808, bell and pad is synthesized here.
// Dark trap loop in F minor, 140 BPM half-time. First pass is a filtered intro, then the drop.
//
// Set NEXT_PUBLIC_INTRO_AUDIO_URL to play your own (licensed) track instead; createFileTrack()
// gives it the same controls and drives the visuals from the music.

const BPM = 140;
const STEP = 60 / BPM / 4; // one 16th note
const midi = m => 440 * Math.pow(2, (m - 69) / 12);

// 4-bar progression: Fm - Db - Bbm - C
const BARS = [
  { root: 29, pad: [53, 56, 60, 65], bell: [77, 80, 84, 80, 77] },
  { root: 37, pad: [53, 56, 61, 65], bell: [77, 80, 85, 80, 77] },
  { root: 34, pad: [53, 58, 61, 65], bell: [77, 82, 85, 82, 77] },
  { root: 36, pad: [52, 55, 60, 64], bell: [76, 79, 84, 79, 83] }
];
const KICKS = [[0, 10], [0, 7, 10], [0, 10, 13], [0, 3, 10, 14]];
const BELL_STEPS = [0, 3, 6, 10, 13];

function makeNoise(ctx, seconds = 1) {
  const buf = ctx.createBuffer(1, Math.floor(ctx.sampleRate * seconds), ctx.sampleRate);
  const d = buf.getChannelData(0);
  for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
  return buf;
}

function makeImpulse(ctx, seconds = 2.6, decay = 3.2) {
  const len = Math.floor(ctx.sampleRate * seconds);
  const buf = ctx.createBuffer(2, len, ctx.sampleRate);
  for (let ch = 0; ch < 2; ch++) {
    const d = buf.getChannelData(ch);
    for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, decay);
  }
  return buf;
}

function saturator(ctx, amount = 2.4) {
  const ws = ctx.createWaveShaper();
  const n = 1024, curve = new Float32Array(n);
  for (let i = 0; i < n; i++) { const x = (i / (n - 1)) * 2 - 1; curve[i] = Math.tanh(x * amount) / Math.tanh(amount); }
  ws.curve = curve;
  return ws;
}

// Shared output chain + controls for both the generated beat and a file track.
function createOutput(ctx) {
  const master = ctx.createGain();
  const exitFilter = ctx.createBiquadFilter();
  exitFilter.type = 'lowpass';
  exitFilter.frequency.value = 20000;
  const comp = ctx.createDynamicsCompressor();
  comp.threshold.value = -14; comp.ratio.value = 4; comp.attack.value = 0.003; comp.release.value = 0.22;
  const analyser = ctx.createAnalyser();
  analyser.fftSize = 256;
  analyser.smoothingTimeConstant = 0.72;
  const bus = ctx.createGain();
  bus.connect(exitFilter).connect(comp).connect(master).connect(analyser).connect(ctx.destination);
  return { bus, master, exitFilter, analyser };
}

function impact(ctx, out, t) {
  const o = ctx.createOscillator(), g = ctx.createGain();
  o.frequency.setValueAtTime(90, t);
  o.frequency.exponentialRampToValueAtTime(28, t + 1.4);
  g.gain.setValueAtTime(0.0001, t);
  g.gain.linearRampToValueAtTime(1.0, t + 0.01);
  g.gain.exponentialRampToValueAtTime(0.0001, t + 1.8);
  o.connect(g).connect(out.master);
  o.start(t); o.stop(t + 1.9);
}

export function createIntroBeat() {
  const AC = typeof window !== 'undefined' && (window.AudioContext || window.webkitAudioContext);
  if (!AC) return null;
  const ctx = new AC();
  const out = createOutput(ctx);
  const noise = makeNoise(ctx, 1.5);

  // effects
  const reverb = ctx.createConvolver();
  reverb.buffer = makeImpulse(ctx);
  const reverbSend = ctx.createGain(); reverbSend.gain.value = 0.32;
  reverbSend.connect(reverb).connect(out.bus);
  const delay = ctx.createDelay(1);
  delay.delayTime.value = STEP * 3;
  const fb = ctx.createGain(); fb.gain.value = 0.34;
  const delayTone = ctx.createBiquadFilter(); delayTone.type = 'lowpass'; delayTone.frequency.value = 3200;
  delay.connect(delayTone).connect(fb).connect(delay);
  const delayOut = ctx.createGain(); delayOut.gain.value = 0.42;
  delayTone.connect(delayOut).connect(out.bus);
  delayOut.connect(reverbSend);
  // hats + bells run through a filter that opens up at the drop
  const introFilter = ctx.createBiquadFilter();
  introFilter.type = 'lowpass'; introFilter.frequency.value = 900; introFilter.Q.value = 0.8;
  introFilter.connect(out.bus);
  const sat = saturator(ctx, 2.6);
  const subBus = ctx.createGain(); subBus.gain.value = 0.9;
  sat.connect(subBus).connect(out.bus);

  const events = [];
  const pushEvent = (t, type, v = 1) => events.push({ t, type, v });

  function noiseSrc(t, dur) {
    const s = ctx.createBufferSource();
    s.buffer = noise;
    if (dur > 0.6) { s.loop = true; s.start(t); s.stop(t + dur + 0.05); }
    else s.start(t, Math.random() * 0.8, dur + 0.05);
    return s;
  }

  function kick(t, vel = 1) {
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.frequency.setValueAtTime(165, t);
    o.frequency.exponentialRampToValueAtTime(46, t + 0.11);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.95 * vel, t + 0.004);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.42);
    o.connect(g).connect(out.bus);
    o.start(t); o.stop(t + 0.45);
    const c = noiseSrc(t, 0.02), cg = ctx.createGain(), hp = ctx.createBiquadFilter();
    hp.type = 'highpass'; hp.frequency.value = 3000;
    cg.gain.setValueAtTime(0.25 * vel, t); cg.gain.exponentialRampToValueAtTime(0.0001, t + 0.015);
    c.connect(hp).connect(cg).connect(out.bus);
    pushEvent(t, 'kick', vel);
  }

  function bass808(t, note, dur, slideTo) {
    const o = ctx.createOscillator(), g = ctx.createGain();
    o.type = 'sine';
    o.frequency.setValueAtTime(midi(note), t);
    if (slideTo) o.frequency.exponentialRampToValueAtTime(midi(slideTo), t + Math.min(0.18, dur * 0.6));
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.75, t + 0.008);
    g.gain.setTargetAtTime(0.55, t + 0.05, 0.25);
    g.gain.exponentialRampToValueAtTime(0.0001, t + Math.max(0.3, dur));
    o.connect(g).connect(sat);
    o.start(t); o.stop(t + dur + 0.05);
  }

  function clap(t, vel = 1) {
    for (let k = 0; k < 3; k++) {
      const tt = t + k * 0.011;
      const s = noiseSrc(tt, 0.2), bp = ctx.createBiquadFilter(), g = ctx.createGain();
      bp.type = 'bandpass'; bp.frequency.value = 1500; bp.Q.value = 0.9;
      g.gain.setValueAtTime(0.0001, tt);
      g.gain.linearRampToValueAtTime((k === 2 ? 0.55 : 0.3) * vel, tt + 0.002);
      g.gain.exponentialRampToValueAtTime(0.0001, tt + (k === 2 ? 0.24 : 0.03));
      s.connect(bp).connect(g);
      g.connect(out.bus);
      if (k === 2) g.connect(reverbSend);
    }
    const o = ctx.createOscillator(), og = ctx.createGain();
    o.type = 'triangle';
    o.frequency.setValueAtTime(210, t); o.frequency.exponentialRampToValueAtTime(150, t + 0.08);
    og.gain.setValueAtTime(0.3 * vel, t); og.gain.exponentialRampToValueAtTime(0.0001, t + 0.12);
    o.connect(og).connect(out.bus);
    o.start(t); o.stop(t + 0.14);
    pushEvent(t, 'snare', vel);
  }

  function hat(t, vel = 1, open = false, dest = introFilter) {
    const s = noiseSrc(t, open ? 0.35 : 0.06), hp = ctx.createBiquadFilter(), g = ctx.createGain();
    hp.type = 'highpass'; hp.frequency.value = 7200;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.16 * vel, t + 0.002);
    g.gain.exponentialRampToValueAtTime(0.0001, t + (open ? 0.32 : 0.045));
    s.connect(hp).connect(g).connect(dest);
  }

  function bell(t, note, vel = 1, dest = introFilter) {
    const f = midi(note);
    const car = ctx.createOscillator(), mod = ctx.createOscillator(), modG = ctx.createGain(), g = ctx.createGain();
    car.frequency.value = f; mod.frequency.value = f * 3.5;
    modG.gain.setValueAtTime(f * 2.2, t); modG.gain.exponentialRampToValueAtTime(f * 0.05, t + 0.9);
    mod.connect(modG).connect(car.frequency);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.11 * vel, t + 0.004);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 1.4);
    car.connect(g);
    g.connect(dest); g.connect(delay); g.connect(reverbSend);
    car.start(t); mod.start(t); car.stop(t + 1.5); mod.stop(t + 1.5);
  }

  function pad(t, notes, dur) {
    const lp = ctx.createBiquadFilter(), g = ctx.createGain();
    lp.type = 'lowpass'; lp.frequency.value = 1050; lp.Q.value = 0.4;
    g.gain.setValueAtTime(0.0001, t);
    g.gain.linearRampToValueAtTime(0.045, t + 0.5);
    g.gain.setValueAtTime(0.045, t + dur - 0.3);
    g.gain.linearRampToValueAtTime(0.0001, t + dur + 0.6);
    lp.connect(g); g.connect(out.bus); g.connect(reverbSend);
    for (const n of notes) {
      for (const det of [-7, 7]) {
        const o = ctx.createOscillator();
        o.type = 'sawtooth'; o.frequency.value = midi(n); o.detune.value = det;
        o.connect(lp); o.start(t); o.stop(t + dur + 0.7);
      }
    }
  }

  function riser(t, dur) {
    const s = noiseSrc(t, dur), bp = ctx.createBiquadFilter(), g = ctx.createGain();
    bp.type = 'bandpass'; bp.Q.value = 3;
    bp.frequency.setValueAtTime(300, t); bp.frequency.exponentialRampToValueAtTime(7000, t + dur);
    g.gain.setValueAtTime(0.0001, t); g.gain.linearRampToValueAtTime(0.22, t + dur);
    g.gain.linearRampToValueAtTime(0.0001, t + dur + 0.05);
    s.connect(bp).connect(g).connect(out.bus);
  }

  // ---- sequencer ----
  let step = 0, loop = 0, nextTime = 0, timer = null, running = false;

  function scheduleStep(t) {
    const barIdx = Math.floor(step / 16) % 4, s = step % 16, bar = BARS[barIdx];
    const intro = loop === 0, breakdown = loop % 4 === 3 && barIdx === 0;

    if (s === 0) pad(t, bar.pad, STEP * 16);
    const bi = BELL_STEPS.indexOf(s);
    if (bi >= 0) bell(t, bar.bell[bi], bi === 0 ? 1 : 0.8);

    // hats: 8ths, with rolls on bars 2 and 4
    const rollBar = barIdx === 1 || barIdx === 3;
    if (rollBar && s >= 12) {
      const parts = barIdx === 3 ? 3 : 2;
      for (let k = 0; k < parts; k++) hat(t + (STEP / parts) * k, 0.55 + 0.1 * k);
    } else if (s % 2 === 0) {
      hat(t, s % 4 === 0 ? 1 : 0.6, barIdx === 2 && s === 6);
    }

    if (intro) {
      if (barIdx === 3 && s === 0) riser(t, STEP * 16);
      if (barIdx === 3 && s >= 8) clap(t, 0.25 + (s - 8) * 0.07);
      return;
    }
    if (!breakdown && KICKS[barIdx].includes(s)) {
      kick(t);
      const ks = KICKS[barIdx], next = ks[ks.indexOf(s) + 1] ?? 16;
      const slide = barIdx === 3 && s === 14 ? bar.root + 12 : null;
      bass808(t, bar.root, (next - s) * STEP, slide);
    }
    if (s === 8) clap(t);
    if (barIdx === 3 && s === 15) clap(t, 0.35);
  }

  function tick() {
    while (nextTime < ctx.currentTime + 0.14) {
      scheduleStep(nextTime);
      nextTime += STEP;
      step++;
      if (step % 64 === 0) {
        loop++;
        if (loop === 1) {
          // the drop: open the filter
          introFilter.frequency.setTargetAtTime(16000, nextTime, 0.05);
        }
      }
    }
  }

  return {
    ctx,
    analyser: out.analyser,
    get running() { return running && ctx.state === 'running'; },
    async start() {
      try { await ctx.resume(); } catch { /* blocked until a tap */ }
      if (ctx.state !== 'running') return false;
      if (!running) {
        running = true;
        nextTime = ctx.currentTime + 0.08;
        timer = setInterval(tick, 25);
        tick();
      }
      return true;
    },
    pause() { ctx.suspend(); },
    resume() { return ctx.resume(); },
    setVolume(v) { out.master.gain.setTargetAtTime(Math.max(0, Math.min(1, v)) * 0.9, ctx.currentTime, 0.03); },
    // visual cues (kick/snare) whose time has come
    takeEvents() {
      const now = ctx.currentTime, due = [];
      while (events.length && events[0].t <= now) due.push(events.shift());
      if (events.length > 200) events.splice(0, events.length - 200);
      return due;
    },
    exit() {
      const t = ctx.currentTime;
      if (ctx.state === 'running') impact(ctx, out, t);
      out.exitFilter.frequency.setTargetAtTime(160, t, 0.35);
      out.master.gain.setTargetAtTime(0.0001, t + 0.6, 0.35);
      setTimeout(() => { clearInterval(timer); running = false; ctx.close().catch(() => {}); }, 2600);
    },
    destroy() { clearInterval(timer); running = false; ctx.close().catch(() => {}); }
  };
}

// Same controls for a real audio file (NEXT_PUBLIC_INTRO_AUDIO_URL).
export function createFileTrack(url) {
  const AC = typeof window !== 'undefined' && (window.AudioContext || window.webkitAudioContext);
  if (!AC) return null;
  const ctx = new AC();
  const out = createOutput(ctx);
  const el = new Audio(url);
  el.loop = true; el.crossOrigin = 'anonymous'; el.preload = 'auto';
  ctx.createMediaElementSource(el).connect(out.bus);
  const data = new Uint8Array(out.analyser.frequencyBinCount);
  let avg = 0, last = 0;
  return {
    ctx,
    analyser: out.analyser,
    get running() { return !el.paused && ctx.state === 'running'; },
    async start() {
      try { await ctx.resume(); await el.play(); } catch { return false; }
      return ctx.state === 'running';
    },
    pause() { el.pause(); },
    resume() { return el.play(); },
    setVolume(v) { out.master.gain.setTargetAtTime(Math.max(0, Math.min(1, v)), ctx.currentTime, 0.03); },
    takeEvents() {
      if (el.paused) return [];
      out.analyser.getByteFrequencyData(data);
      const bass = (data[1] + data[2] + data[3]) / 765;
      avg = avg * 0.92 + bass * 0.08;
      const now = ctx.currentTime;
      if (bass > 0.55 && bass > avg * 1.2 && now - last > 0.25) { last = now; return [{ t: now, type: 'kick', v: 1 }]; }
      return [];
    },
    exit() {
      const t = ctx.currentTime;
      impact(ctx, out, t);
      out.exitFilter.frequency.setTargetAtTime(160, t, 0.35);
      out.master.gain.setTargetAtTime(0.0001, t + 0.6, 0.35);
      setTimeout(() => { el.pause(); ctx.close().catch(() => {}); }, 2600);
    },
    destroy() { el.pause(); ctx.close().catch(() => {}); }
  };
}
