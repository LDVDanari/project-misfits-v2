import OwnerStoreAdmin from '../../../components/OwnerStoreAdmin';
export const metadata = { title: 'Owner Dashboard', robots: { index: false, follow: false } };
export const dynamic = 'force-dynamic';
export default function Funds() {
  return <main className="inner ownerFundsPage">
    <div className="kicker">PRIVATE OWNER ACCESS</div>
    <h1>PMv2 <span>STORE DASHBOARD.</span></h1>
    <p className="lead">See which store items are live on Tebex. Money, orders, refunds and coupons live in the Tebex control panel.</p>
    <OwnerStoreAdmin />
  </main>;
}
