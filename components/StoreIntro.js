'use client';import {useEffect,useRef,useState} from 'react';import LeanPourCanvas from './LeanPourCanvas';

const VIDEO_ID='z0G04bgZHwc';

export default function StoreIntro(){
 const [visible,setVisible]=useState(false),[entering,setEntering]=useState(false),[playing,setPlaying]=useState(false),[muted,setMuted]=useState(false),[volume,setVolume]=useState(50),[origin,setOrigin]=useState(''),[needsGesture,setNeedsGesture]=useState(false);
 const playerRef=useRef(null);

 const command=(func,args=[])=>{try{playerRef.current?.contentWindow?.postMessage(JSON.stringify({event:'command',func,args}),'https://www.youtube.com')}catch{}};
 const syncVolume=()=>{command('setVolume',[volume]);command(muted?'mute':'unMute')};
 const play=()=>{syncVolume();command('playVideo');setPlaying(true);setNeedsGesture(false)};
 const pause=()=>{command('pauseVideo');setPlaying(false)};

 useEffect(()=>{
   setOrigin(window.location.origin);
   try{if(sessionStorage.getItem('pmv2-intro-v8-seen'))return;}catch{}
   setVisible(true);
   document.documentElement.classList.add('introLocked');
   return()=>document.documentElement.classList.remove('introLocked');
 },[]);

 useEffect(()=>{
   if(!visible||!origin)return;
   const t=setTimeout(()=>{syncVolume();command('playVideo');setPlaying(true);setTimeout(()=>setNeedsGesture(true),1400)},850);
   return()=>clearTimeout(t);
 },[visible,origin]);

 useEffect(()=>{if(visible)command('setVolume',[volume])},[volume,visible]);
 useEffect(()=>{if(visible)command(muted?'mute':'unMute')},[muted,visible]);

 const ensureSound=()=>{if(!playing)play()};
 const enter=()=>{
   if(entering)return;
   setEntering(true);
   try{sessionStorage.setItem('pmv2-intro-v8-seen','1')}catch{}
   setTimeout(()=>{pause();setVisible(false);document.documentElement.classList.remove('introLocked')},2150);
 };

 if(!visible)return null;

 const src=origin?('https://www.youtube.com/embed/'+VIDEO_ID+'?enablejsapi=1&autoplay=1&controls=0&loop=1&playlist='+VIDEO_ID+'&playsinline=1&rel=0&origin='+encodeURIComponent(origin)):'';

 return <div className={entering?'storeIntro introV8 entering':'storeIntro introV8'} role="dialog" aria-modal="true" onPointerDownCapture={ensureSound}>
   {src&&<iframe ref={playerRef} className="introV8YT" title="Future - F*ck Up Some Commas" src={src} allow="autoplay; encrypted-media" onLoad={()=>{syncVolume();command('playVideo')}}/>}
   <img className="introV8Artwork" src="/images/intro/pmv2-exact.svg" alt="Project Misfits Store welcome"/>
   <div className="introV8LogoMask" aria-hidden="true"/>
   <img className="introV8LogoClone" src="/images/intro/pmv2-exact.svg" alt="" aria-hidden="true"/>

   <button className="introV8LogoHit" onClick={enter} aria-label="Enter Project Misfits Store"/>
   <button className="introV8ContinueHit" onClick={enter} aria-label="Continue to store"/>

   <div className="introV8Controls" onPointerDown={e=>e.stopPropagation()}>
     <button onClick={()=>playing?pause():play()} aria-label={playing?'Pause music':'Play music'}>{playing?'❚❚':'▶'}</button>
     <button onClick={()=>setMuted(v=>!v)} aria-label={muted?'Unmute music':'Mute music'}>{muted?'🔇':'🔊'}</button>
     <input aria-label="Music volume" type="range" min="0" max="100" value={volume} onChange={e=>setVolume(Number(e.target.value))}/>
     <strong>{volume}</strong>
     <small>NOW PLAYING: FUTURE — F*CK UP SOME COMMAS</small>
   </div>

   {needsGesture&&!playing&&<button className="introV8SoundPrompt" onClick={play}>CLICK FOR SOUND</button>}
   <LeanPourCanvas active={entering}/>
 </div>;
}