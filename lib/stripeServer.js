import crypto from 'crypto';import {allStoreItems} from './products';

const API=(process.env.STRIPE_API_BASE||'https://api.stripe.com/v1').replace(/\/$/,'');
export function stripeReady(){return Boolean(process.env.STRIPE_SECRET_KEY)}
export function stripeHeaders(){return{Authorization:'Bearer '+process.env.STRIPE_SECRET_KEY,'Content-Type':'application/x-www-form-urlencoded'}}
export async function stripeRequest(path,{method='GET',body}={}){if(!process.env.STRIPE_SECRET_KEY)throw new Error('Stripe is not configured');const res=await fetch(API+path,{method,headers:stripeHeaders(),body:body?new URLSearchParams(body):undefined,cache:'no-store'});const json=await res.json().catch(()=>({}));if(!res.ok)throw new Error(json?.error?.message||'Stripe request failed');return json}
export function priceToCents(price){const n=Number(String(price).replace(/[^0-9.]/g,''));if(!Number.isFinite(n))throw new Error('Invalid price');return Math.round(n*100)}
export function buildCheckoutItems(cart){if(!Array.isArray(cart)||!cart.length)throw new Error('Cart is empty');return cart.map(row=>{const product=allStoreItems.find(p=>p.slug===row.slug);if(!product||product.price==='COMING SOON')throw new Error('Invalid store item');const qty=Math.max(1,Math.min(10,Number(row.qty)||1));return{product,qty,unit_amount:priceToCents(product.price)}})}
// Accepts any of the v1 signatures Stripe sends (there are two while a signing secret is being rolled).
export function verifyStripeSignature(payload,signature,secret){
 if(!signature||!secret)return false;
 let t='';const sigs=[];
 for(const part of String(signature).split(',')){const i=part.indexOf('=');if(i<1)continue;const k=part.slice(0,i).trim(),v=part.slice(i+1).trim();if(k==='t')t=v;else if(k==='v1')sigs.push(v)}
 if(!t||!sigs.length)return false;
 if(Math.abs(Date.now()/1000-Number(t))>300)return false;
 const digest=Buffer.from(crypto.createHmac('sha256',secret).update(t+'.'+payload,'utf8').digest('hex'));
 return sigs.some(v=>{const b=Buffer.from(v);return b.length===digest.length&&crypto.timingSafeEqual(b,digest)});
}
