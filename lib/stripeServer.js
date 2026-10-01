import crypto from 'crypto';import {allStoreItems} from './products';

const API='https://api.stripe.com/v1';
export function stripeReady(){return Boolean(process.env.STRIPE_SECRET_KEY)}
export function stripeHeaders(){return{Authorization:'Bearer '+process.env.STRIPE_SECRET_KEY,'Content-Type':'application/x-www-form-urlencoded'}}
export async function stripeRequest(path,{method='GET',body}={}){if(!process.env.STRIPE_SECRET_KEY)throw new Error('Stripe is not configured');const res=await fetch(API+path,{method,headers:stripeHeaders(),body:body?new URLSearchParams(body):undefined,cache:'no-store'});const json=await res.json().catch(()=>({}));if(!res.ok)throw new Error(json?.error?.message||'Stripe request failed');return json}
export function priceToCents(price){const n=Number(String(price).replace(/[^0-9.]/g,''));if(!Number.isFinite(n))throw new Error('Invalid price');return Math.round(n*100)}
export function buildCheckoutItems(cart){if(!Array.isArray(cart)||!cart.length)throw new Error('Cart is empty');return cart.map(row=>{const product=allStoreItems.find(p=>p.slug===row.slug);if(!product||product.price==='COMING SOON')throw new Error('Invalid store item');const qty=Math.max(1,Math.min(10,Number(row.qty)||1));return{product,qty,unit_amount:priceToCents(product.price)}})}
export function verifyStripeSignature(payload,signature,secret){if(!signature||!secret)return false;const parts=Object.fromEntries(signature.split(',').map(x=>x.split('=')));const t=parts.t,v1=parts.v1;if(!t||!v1)return false;const age=Math.abs(Date.now()/1000-Number(t));if(age>300)return false;const digest=crypto.createHmac('sha256',secret).update(t+'.'+payload,'utf8').digest('hex');try{return crypto.timingSafeEqual(Buffer.from(digest),Buffer.from(v1))}catch{return false}}
