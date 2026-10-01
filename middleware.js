import {NextResponse} from 'next/server';

const COOKIE='pmv2_owner_session';
const encoder=new TextEncoder();

function b64urlDecode(value){
  value=value.replace(/-/g,'+').replace(/_/g,'/');
  while(value.length%4)value+='=';
  const raw=atob(value);
  return Uint8Array.from(raw,c=>c.charCodeAt(0));
}
async function sessionKey(){
  const material=(process.env.OWNER_USERNAME||'')+':'+(process.env.OWNER_PASSWORD||'')+':pmv2-owner-session';
  return crypto.subtle.importKey('raw',encoder.encode(material),{name:'HMAC',hash:'SHA-256'},false,['verify']);
}
async function validSession(token){
  if(!token||!process.env.OWNER_USERNAME||!process.env.OWNER_PASSWORD)return false;
  const dot=token.lastIndexOf('.');
  if(dot<1)return false;
  const payload=token.slice(0,dot),sig=token.slice(dot+1);
  let decoded='';
  try{decoded=new TextDecoder().decode(b64urlDecode(payload))}catch{return false}
  const [user,exp]=decoded.split('|');
  if(user!==process.env.OWNER_USERNAME||!exp||Date.now()>Number(exp))return false;
  try{
    const key=await sessionKey();
    return await crypto.subtle.verify('HMAC',key,b64urlDecode(sig),encoder.encode(payload));
  }catch{return false}
}

function basicAuth(request,user,pass,realm){
 if(!user||!pass)return new NextResponse('Not Found',{status:404});
 const auth=request.headers.get('authorization')||'';
 if(!auth.startsWith('Basic '))return new NextResponse('Authentication required',{status:401,headers:{'WWW-Authenticate':`Basic realm="${realm}"`}});
 try{
  const decoded=atob(auth.slice(6));
  const split=decoded.indexOf(':');
  const u=decoded.slice(0,split);
  const p=decoded.slice(split+1);
  if(u===user&&p===pass)return NextResponse.next();
 }catch{}
 return new NextResponse('Unauthorized',{status:401,headers:{'WWW-Authenticate':`Basic realm="${realm}"`}});
}

export async function middleware(request){
 const path=request.nextUrl.pathname;

 if(path==='/owner/login'||path==='/api/owner/login'||path==='/api/owner/logout')return NextResponse.next();

 if(path.startsWith('/owner')||path.startsWith('/api/owner')){
   const ok=await validSession(request.cookies.get(COOKIE)?.value||'');
   if(ok)return NextResponse.next();

   if(path.startsWith('/api/owner'))return NextResponse.json({error:'Owner authentication required.'},{status:401});

   const url=request.nextUrl.clone();
   url.pathname='/owner/login';
   url.searchParams.set('next',path);
   return NextResponse.redirect(url);
 }

 if(path.startsWith('/admin'))return basicAuth(request,process.env.ADMIN_USERNAME,process.env.ADMIN_PASSWORD,'PMv2 Admin');
 return NextResponse.next();
}
export const config={matcher:['/admin/:path*','/owner/:path*','/api/owner/:path*']};
