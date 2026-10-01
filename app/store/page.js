import ProductCard from '../../components/ProductCard';
import {products,coins,priorities} from '../../lib/products';
export default function Store(){return <main className="inner">
<div className="kicker">PMv2 STORE</div><h1>EXPAND YOUR <span>STORY.</span></h1><p className="lead">Defined packages, clear deliverables, and dedicated pages for every store item.</p>
<section className="storeSection"><div className="kicker">PACKAGES</div><h2>BUILD YOUR LEGACY.</h2><div className="grid">{products.map(p=><ProductCard key={p.slug} p={p}/>)}</div></section>
<section id="coins" className="storeSection"><div className="kicker">MISFIT COINS</div><h2>FUEL YOUR STORY.</h2><div className="grid storeGrid3">{coins.map(p=><ProductCard key={p.slug} p={p}/>)}</div></section>
<section id="priority" className="storeSection"><div className="kicker">QUEUE ACCESS</div><h2>PRIORITY.</h2><div className="grid storeGrid3">{priorities.map(p=><ProductCard key={p.slug} p={p}/>)}</div></section>
</main>}
