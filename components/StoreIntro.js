'use client';import {useEffect,useRef,useState} from 'react';import LeanPourCanvas from './LeanPourCanvas';

const VIDEO_ID='z0G04bgZHwc';
function LogoMark(){
 return <svg className="introV5LogoSvg" viewBox="0 0 700 700" role="img" aria-label="Project Misfits v2">
  <defs>
   <linearGradient id="pmvPurple" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#7a0fa6"/><stop offset=".35" stopColor="#ff42ff"/><stop offset=".65" stopColor="#9d19ff"/><stop offset="1" stopColor="#4b086f"/></linearGradient>
   <linearGradient id="pmvSilver" x1="0" y1="0" x2="1" y2="1"><stop offset="0" stopColor="#fff"/><stop offset=".33" stopColor="#bcb9c1"/><stop offset=".58" stopColor="#fff"/><stop offset="1" stopColor="#77717c"/></linearGradient>
   <filter id="pmvGlow"><feGaussianBlur stdDeviation="7" result="b"/><feMerge><feMergeNode in="b"/><feMergeNode in="SourceGraphic"/></feMerge></filter>
   <filter id="pmvRough"><feTurbulence type="fractalNoise" baseFrequency=".018" numOctaves="2" seed="7" result="noise"/><feDisplacementMap in="SourceGraphic" in2="noise" scale="7"/></filter>
  </defs>
  <circle cx="350" cy="355" r="270" fill="#0a0710" stroke="url(#pmvSilver)" strokeWidth="18"/>
  <circle cx="350" cy="355" r="246" fill="none" stroke="#7616a1" strokeWidth="10" opacity=".9"/>
  <g filter="url(#pmvGlow)">
   <path d="M216 148 L268 76 L332 154 L391 62 L452 153 L510 82 L489 205 L221 205 Z" fill="url(#pmvPurple)" stroke="#efc6ff" strokeWidth="8" strokeLinejoin="round"/>
   <path d="M350 80 L350 193" stroke="#fff" strokeOpacity=".55" strokeWidth="5"/>
  </g>
  <g filter="url(#pmvRough)" textAnchor="middle" fontFamily="Impact, Haettenschweiler, 'Arial Narrow Bold', sans-serif" fontWeight="900" fontStyle="italic">
   <text x="350" y="315" fontSize="126" fill="url(#pmvSilver)" stroke="#130c18" strokeWidth="11" paintOrder="stroke">PROJECT</text>
   <text x="350" y="458" fontSize="150" fill="url(#pmvPurple)" stroke="#16091e" strokeWidth="13" paintOrder="stroke">MISFITS</text>
   <text x="350" y="590" fontSize="126" fill="url(#pmvSilver)" stroke="#170c1c" strokeWidth="11" paintOrder="stroke">V2</text>
  </g>
  <g fill="url(#pmvPurple)" filter="url(#pmvGlow)">
   <path d="M190 393 h22 v92 q0 28-11 39 q-11-11-11-39z"/><circle cx="201" cy="535" r="13"/>
   <path d="M286 455 h18 v72 q0 24-9 34 q-9-10-9-34z"/><circle cx="295" cy="569" r="11"/>
   <path d="M430 448 h20 v94 q0 24-10 34 q-10-10-10-34z"/><circle cx="440" cy="587" r="12"/>
   <path d="M505 387 h18 v70 q0 22-9 31 q-9-9-9-31z"/><circle cx="514" cy="497" r="10"/>
  </g>
 </svg>
}

export default function StoreIntro(){
 const [visible,setVisible]=useState(false),[entering,setEntering]=useState(false),[playing,setPlaying]=useState(false),[muted,setMuted]=useState(false),[volume,setVolume]=useState(50);
 const playerRef=useRef(null);
 const command=(func,args=[])=>{try{playerRef.current?.contentWindow?.postMessage(JSON.stringify({event:'command',func,args}),'https://www.youtube.com')}catch{}};
 const syncVolume=()=>{command('setVolume',[volume]);command(muted?'mute':'unMute')};
 const play=()=>{syncVolume();command('playVideo');setPlaying(true)};
 const pause=()=>{command('pauseVideo');setPlaying(false)};
 useEffect(()=>{try{if(sessionStorage.getItem('pmv2-intro-v5-seen'))return;}catch{}setVisible(true);document.documentElement.classList.add('introLocked');return()=>document.documentElement.classList.remove('introLocked')},[]);
 useEffect(()=>{if(!visible)return;const t=setTimeout(()=>{syncVolume();command('playVideo');setPlaying(true)},900);return()=>clearTimeout(t)},[visible]);
 useEffect(()=>{if(!visible)return;command('setVolume',[volume])},[volume,visible]);
 useEffect(()=>{if(!visible)return;command(muted?'mute':'unMute')},[muted,visible]);
 const enter=()=>{if(entering)return;setEntering(true);try{sessionStorage.setItem('pmv2-intro-v5-seen','1')}catch{};setTimeout(()=>{pause();setVisible(false);document.documentElement.classList.remove('introLocked')},2150)};
 if(!visible)return null;
 return <div className={entering?'storeIntro introV5 entering':'storeIntro introV5'} role="dialog" aria-modal="true">
  <iframe ref={playerRef} className="introV5YT" title="Future - F*ck Up Some Commas" src={'https://www.youtube.com/embed/'+VIDEO_ID+'?enablejsapi=1&autoplay=1&controls=0&loop=1&playlist='+VIDEO_ID+'&playsinline=1&rel=0'} allow="autoplay; encrypted-media" onLoad={()=>{syncVolume();command('playVideo')}}/>
  <div className="introV5TopDrip" aria-hidden="true"><i/><i/><i/><i/><i/><i/></div>
  <div className="introV5Cup introV5CupLeft" aria-hidden="true"><b/><span/></div>
  <div className="introV5Cup introV5CupRight" aria-hidden="true"><b/><span/></div>
  <div className="introV5Ice introV5IceA"/><div className="introV5Ice introV5IceB"/><div className="introV5Ice introV5IceC"/>
  <div className="introV5Center">
   <button className="introV5LogoButton" onClick={enter}><LogoMark/></button>
   <h1>Welcome to <span>Project Misfits</span> Store!</h1>
   <button className="introV5Continue" onClick={enter}>CLICK THE LOGO TO CONTINUE.</button>
  </div>
  <div className="introV5Audio" onPointerDown={()=>{if(!playing)play()}}>
   <button onClick={()=>playing?pause():play()} aria-label={playing?'Pause music':'Play music'}>{playing?'❚❚':'▶'}</button>
   <button onClick={()=>setMuted(v=>!v)} aria-label={muted?'Unmute music':'Mute music'}>{muted?'🔇':'🔊'}</button>
   <input aria-label="Music volume" type="range" min="0" max="100" value={volume} onChange={e=>setVolume(Number(e.target.value))}/>
   <strong>{volume}</strong>
   <small>NOW PLAYING: FUTURE — F*CK UP SOME COMMAS</small>
  </div>
  <div className="introV5BrowserNote">If your browser blocks autoplay, tap ▶ once.</div>
  <LeanPourCanvas active={entering}/>
 </div>
}