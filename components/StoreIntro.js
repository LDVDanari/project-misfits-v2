'use client';import {useEffect,useRef,useState} from 'react';import LeanPourCanvas from './LeanPourCanvas';import INTRO_ART from '../lib/introV6Art';

const VIDEO_ID='z0G04bgZHwc';

export default function StoreIntro(){
 const [visible,setVisible]=useState(false),[entering,setEntering]=useState(false),[playing,setPlaying]=useState(false),[muted,setMuted]=useState(false),[volume,setVolume]=useState(50);
 const playerRef=useRef(null);
 const command=(func,args=[])=>{try{playerRef.current?.contentWindow?.postMessage(JSON.stringify({event:'command',func,args}),'https://www.youtube.com')}catch{}};
 const syncVolume=()=>{command('setVolume',[volume]);command(muted?'mute':'unMute')};
 const play=()=>{syncVolume();command('playVideo');setPlaying(true)};
 const pause=()=>{command('pauseVideo');setPlaying(false)};
 useEffect(()=>{try{if(sessionStorage.getItem('pmv2-intro-v6-seen'))return;}catch{}setVisible(true);document.documentElement.classList.add('introLocked');return()=>document.documentElement.classList.remove('introLocked')},[]);
 useEffect(()=>{if(!visible)return;const t=setTimeout(()=>{syncVolume();command('playVideo');setPlaying(true)},650);return()=>clearTimeout(t)},[visible]);
 useEffect(()=>{if(!visible)return;command('setVolume',[volume])},[volume,visible]);
 useEffect(()=>{if(!visible)return;command(muted?'mute':'unMute')},[muted,visible]);
 const enter=()=>{if(entering)return;setEntering(true);try{sessionStorage.setItem('pmv2-intro-v6-seen','1')}catch{};setTimeout(()=>{pause();setVisible(false);document.documentElement.classList.remove('introLocked')},2150)};
 if(!visible)return null;
 return <div className={entering?'storeIntro introV6 entering':'storeIntro introV6'} role="dialog" aria-modal="true">
   <iframe ref={playerRef} className="introV6YT" title="Future - F*ck Up Some Commas" src={'https://www.youtube.com/embed/'+VIDEO_ID+'?enablejsapi=1&autoplay=1&controls=0&loop=1&playlist='+VIDEO_ID+'&playsinline=1&rel=0'} allow="autoplay; encrypted-media" onLoad={()=>{syncVolume();command('playVideo')}}/>
   <img className="introV6Scene" src={INTRO_ART} alt="" aria-hidden="true"/>
   <div className="introV6LogoMask" aria-hidden="true"/>
   <img className="introV6LogoClone" src={INTRO_ART} alt="" aria-hidden="true"/>
   <button className="introV6LogoHit" onClick={enter} aria-label="Enter Project Misfits Store"/>
   <div className="introV6Copy">
     <h1>Welcome to <span>Project Misfits</span> Store!</h1>
     <button onClick={enter}>CLICK THE LOGO TO CONTINUE.</button>
   </div>
   <div className="introV6Audio" onPointerDown={()=>{if(!playing)play()}}>
     <button onClick={()=>playing?pause():play()} aria-label={playing?'Pause music':'Play music'}>{playing?'❚❚':'▶'}</button>
     <button onClick={()=>setMuted(v=>!v)} aria-label={muted?'Unmute music':'Mute music'}>{muted?'🔇':'🔊'}</button>
     <input aria-label="Music volume" type="range" min="0" max="100" value={volume} onChange={e=>setVolume(Number(e.target.value))}/>
     <strong>{volume}</strong>
     <small>NOW PLAYING: FUTURE — F*CK UP SOME COMMAS</small>
   </div>
   <LeanPourCanvas active={entering}/>
 </div>
}