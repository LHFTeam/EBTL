import { RefreshCw } from 'lucide-react';
import { api } from '../api/client.js';
import { Kpi, Loading, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { dt, money } from '../utils/format.js';

export default function Dashboard() {
  const { data, loading, error, reload } = useLoad(() => api('/api/dashboard'));
  if (loading || error) return <Loading error={error} />;
  return <div className="grid"><div className="kpis"><Kpi label="Recent Orders" value={data.kpis.recentOrders} /><Kpi label="Completed Orders" value={data.kpis.completedOrders} /><Kpi label="Recent Revenue" value={money(data.kpis.recentRevenue)} /><Kpi label="Low Stock Items" value={data.kpis.lowStockItems} /><Kpi label="Active Locations" value={data.kpis.activeLocations} /></div>
    <Section title="Recent Orders" action={<button onClick={reload}><RefreshCw size={16}/>Refresh</button>}><SimpleTable rows={data.recentOrders} columns={['order_number','status','payment_status','total_amount','created_at']} format={{ total_amount: money, created_at: dt }} /></Section>
    <Section title="Low Stock"><SimpleTable rows={data.lowStock} columns={['location_name','ingredient_name','quantity_on_hand','reorder_point','par_level']} /></Section></div>;
}