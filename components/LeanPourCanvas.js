'use client';import {useEffect,useRef} from 'react';

const DRIPS=[
  {x:.08,w:.052,lag:.00,len:.18},{x:.19,w:.036,lag:.08,len:.27},{x:.32,w:.061,lag:.03,len:.15},
  {x:.46,w:.043,lag:.12,len:.31},{x:.58,w:.055,lag:.05,len:.22},{x:.71,w:.039,lag:.14,len:.29},
  {x:.83,w:.064,lag:.02,len:.19},{x:.93,w:.034,lag:.09,len:.25}
];
const BUBBLES=[
  [.12,.19,12],[.24,.34,7],[.38,.16,9],[.51,.28,14],[.67,.13,8],[.79,.31,11],[.9,.2,6],
  [.18,.53,8],[.33,.61,13],[.49,.49,7],[.63,.58,10],[.81,.52,15],[.92,.66,7]
];
const clamp=n=>Math.max(0,Math.min(1,n));
const ease=n=>1-Math.pow(1-clamp(n),3);

export default function LeanPourCanvas({active}){
 const ref=useRef(null);
 useEffect(()=>{
   if(!active)return;
   const canvas=ref.current;if(!canvas)return;
   const ctx=canvas.getContext('2d',{alpha:true});
   let raf=0,start=0,w=0,h=0,dpr=1;
   const resize=()=>{dpr=Math.min(window.devicePixelRatio||1,2);w=window.innerWidth;h=window.innerHeight;canvas.width=Math.round(w*dpr);canvas.height=Math.round(h*dpr);canvas.style.width=w+'px';canvas.style.height=h+'px';ctx.setTransform(dpr,0,0,dpr,0,0)};
   const front=(x,y,t)=>y+Math.sin(x*.011+t*.006)*15+Math.sin(x*.023-t*.004)*8+Math.sin(x*.004+t*.003)*10;
   const draw=(ts)=>{
     if(!start)start=ts;
     const elapsed=ts-start,p=clamp(elapsed/2150);
     ctx.clearRect(0,0,w,h);
     const fall=ease(p/.72);
     const y=-h*.16+(h*1.22)*fall;
     const topFade=p>.83?1-clamp((p-.83)/.17):1;
     ctx.globalAlpha=topFade;

     const grad=ctx.createLinearGradient(0,0,w,h);
     grad.addColorStop(0,'#260033');grad.addColorStop(.26,'#47005f');grad.addColorStop(.5,'#6d078d');grad.addColorStop(.72,'#8b16ad');grad.addColorStop(1,'#3c044f');

     ctx.beginPath();ctx.moveTo(0,-30);ctx.lineTo(w,-30);
     for(let x=w;x>=0;x-=12)ctx.lineTo(x,front(x,y,elapsed));
     ctx.closePath();ctx.fillStyle=grad;ctx.fill();

     ctx.save();
     ctx.globalCompositeOperation='screen';
     const shine=ctx.createLinearGradient(0,0,w,0);
     shine.addColorStop(0,'rgba(255,255,255,0)');shine.addColorStop(.28,'rgba(230,151,255,.05)');
     shine.addColorStop(.5,'rgba(255,226,255,.22)');shine.addColorStop(.62,'rgba(210,108,255,.05)');shine.addColorStop(1,'rgba(255,255,255,0)');
     ctx.fillStyle=shine;ctx.globalAlpha=.7*topFade;
     ctx.fillRect(0,0,w,Math.max(0,y-h*.08));
     ctx.restore();

     DRIPS.forEach((d,i)=>{
       const local=clamp((p-d.lag)/.72);if(local<=0)return;
       const fx=d.x*w,fw=Math.max(18,d.w*w),base=front(fx,y,elapsed)-4;
       const extra=h*d.len*Math.sin(local*Math.PI)*Math.min(1,local*2.2);
       if(base<-80||base>h+120)return;
       const yy=base+extra;
       ctx.beginPath();
       ctx.moveTo(fx-fw*.55,base-18);
       ctx.bezierCurveTo(fx-fw*.62,base+extra*.25,fx-fw*.42,yy-24,fx,yy);
       ctx.bezierCurveTo(fx+fw*.42,yy-24,fx+fw*.62,base+extra*.25,fx+fw*.55,base-18);
       ctx.closePath();ctx.fillStyle=i%2?'#65077f':'#79109a';ctx.fill();
       ctx.beginPath();ctx.ellipse(fx,yy,fw*.38,Math.max(12,fw*.48),0,0,Math.PI*2);ctx.fillStyle='#8613aa';ctx.fill();
       ctx.save();ctx.globalCompositeOperation='screen';ctx.globalAlpha=.34*topFade;ctx.beginPath();ctx.ellipse(fx-fw*.12,base+extra*.52,Math.max(2,fw*.08),Math.max(10,extra*.22),-.1,0,Math.PI*2);ctx.fillStyle='#efb9ff';ctx.fill();ctx.restore();
     });

     ctx.save();
     ctx.globalCompositeOperation='screen';
     BUBBLES.forEach(([bx,by,r],i)=>{
       const px=bx*w+Math.sin(elapsed*.0017+i)*13,py=by*Math.max(y,0)+Math.cos(elapsed*.0012+i)*8;
       if(py<8||py>Math.min(y-10,h))return;
       ctx.globalAlpha=.18*topFade;
       ctx.beginPath();ctx.arc(px,py,r,0,Math.PI*2);ctx.strokeStyle='#f5d8ff';ctx.lineWidth=1.2;ctx.stroke();
       ctx.globalAlpha=.08*topFade;ctx.beginPath();ctx.arc(px-r*.22,py-r*.2,r*.5,0,Math.PI*2);ctx.fillStyle='#fff';ctx.fill();
     });
     ctx.restore();

     ctx.save();
     ctx.globalCompositeOperation='screen';ctx.globalAlpha=.32*topFade;
     ctx.strokeStyle='#dc8dff';ctx.lineWidth=3;ctx.lineCap='round';
     for(let k=0;k<4;k++){const yy=Math.max(24,y-(90+k*78));if(yy<0||yy>h)continue;ctx.beginPath();for(let x=0;x<=w;x+=24){const sy=yy+Math.sin(x*.009+elapsed*.004+k)*7+(k%2?3:-3);if(x===0)ctx.moveTo(x,sy);else ctx.lineTo(x,sy)}ctx.stroke()}
     ctx.restore();

     if(p<1)raf=requestAnimationFrame(draw);
   };
   resize();window.addEventListener('resize',resize);raf=requestAnimationFrame(draw);
   return()=>{cancelAnimationFrame(raf);window.removeEventListener('resize',resize)}
 },[active]);
 return <canvas ref={ref} className="leanPourCanvas" aria-hidden="true"/>;
}