import crypto from 'crypto';import {NextResponse} from 'next/server';
export const runtime='nodejs';
const COOKIE='pmv2_owner_session';
const b64=s=>Buffer.from(s).toString('base64url');
function sign(payload){
 const material=(process.env.OWNER_USERNAME||'')+':'+(process.env.OWNER_PASSWORD||'')+':pmv2-owner-session';
 return crypto.createHmac('sha256',material).update(payload).digest('base64url');
}
export async function POST(req){
 try{
  const {username,password}=await req.json();
  const expectedUser=process.env.OWNER_USERNAME||'';
  const expectedPass=process.env.OWNER_PASSWORD||'';
  if(!expectedUser||!expectedPass)return NextResponse.json({error:'Owner login is not configured.'},{status:503});
  const userOk=Buffer.byteLength(String(username))===Buffer.byteLength(expectedUser)&&crypto.timingSafeEqual(Buffer.from(String(username)),Buffer.from(expectedUser));
  const passOk=Buffer.byteLength(String(password))===Buffer.byteLength(expectedPass)&&crypto.timingSafeEqual(Buffer.from(String(password)),Buffer.from(expectedPass));
  if(!userOk||!passOk)return NextResponse.json({error:'Invalid owner credentials.'},{status:401});
  const exp=Date.now()+12*60*60*1000;
  const payload=b64(expectedUser+'|'+exp);
  const token=payload+'.'+sign(payload);
  const res=NextResponse.json({ok:true});
  res.cookies.set(COOKIE,token,{httpOnly:true,secure:true,sameSite:'strict',path:'/',maxAge:12*60*60});
  return res;
 }catch{return NextResponse.json({error:'Unable to sign in.'},{status:400})}
}
