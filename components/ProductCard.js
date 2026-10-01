import Link from 'next/link';
export default function ProductCard({p}){return <article className="card"><div className="cardImg" style={{backgroundImage:`url(${p.image})`}}/><div className="cardBody"><small>{p.category}</small><h3>{p.title}</h3><p>{p.short}</p><div className="cardFoot"><b>{p.price}</b><Link href={`/store/${p.slug}`}>VIEW PACKAGE →</Link></div></div></article>}
