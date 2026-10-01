import crypto from 'crypto';import {NextResponse} from 'next/server';
export const runtime='nodejs';
const COOKIE='pmv2_owner_session';
const b64=s=>Buffer.from(s).toString('base64url');
function normalizeEnv(value,key){
 let v=String(value??'').trim();
 if(v.toUpperCase().startsWith(key+'='))v=v.slice(key.length+1).trim();
 if((v.startsWith('"')&&v.endsWith('"'))||(v.startsWith("'")&&v.endsWith("'")))v=v.slice(1,-1).trim();
 return v;
}
function credentials(){
 const user=normalizeEnv(process.env.OWNER_USERNAME,'OWNER_USERNAME');
 const b64pass=normalizeEnv(process.env.OWNER_PASSWORD_B64,'OWNER_PASSWORD_B64');
 let pass='';
 if(b64pass){try{pass=Buffer.from(b64pass,'base64').toString('utf8').normalize('NFC').trim()}catch{}}
 if(!pass)pass=normalizeEnv(process.env.OWNER_PASSWORD,'OWNER_PASSWORD').normalize('NFC');
 return{user,pass};
}
function sign(payload,user,pass){
 const material=user+':'+pass+':pmv2-owner-session';
 return crypto.createHmac('sha256',material).update(payload).digest('base64url');
}
function safeEqual(a,b){
 const aa=Buffer.from(a),bb=Buffer.from(b);
 return aa.length===bb.length&&crypto.timingSafeEqual(aa,bb);
}
export async function POST(req){
 try{
  const {username,password}=await req.json();
  const {user:expectedUser,pass:expectedPass}=credentials();
  const suppliedUser=String(username??'').normalize('NFC').trim();
  const suppliedPass=String(password??'').normalize('NFC').trim();
  if(!expectedUser||!expectedPass)return NextResponse.json({error:'Owner login is not configured.'},{status:503});
  const normalizedExpectedUser=expectedUser.normalize('NFC');const normalizedExpectedPass=expectedPass.normalize('NFC');const userOk=safeEqual(suppliedUser.toLowerCase(),normalizedExpectedUser.toLowerCase());
  const passOk=safeEqual(suppliedPass,normalizedExpectedPass);
  if(!userOk)return NextResponse.json({error:'Owner username does not match the live Coolify value.',reason:'username'},{status:401});if(!passOk)return NextResponse.json({error:'Owner password does not match the live Coolify value.',reason:'password'},{status:401});
  const exp=Date.now()+12*60*60*1000;
  const payload=b64(normalizedExpectedUser+'|'+exp);
  const token=payload+'.'+sign(payload,normalizedExpectedUser,normalizedExpectedPass);
  const res=NextResponse.json({ok:true});
  res.cookies.set(COOKIE,token,{httpOnly:true,secure:true,sameSite:'strict',path:'/',maxAge:12*60*60});
  return res;
 }catch{return NextResponse.json({error:'Unable to sign in.'},{status:400})}
}
