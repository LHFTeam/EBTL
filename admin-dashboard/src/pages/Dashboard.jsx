import {
  AlertTriangle,
  CheckCircle2,
  MapPin,
  RefreshCw,
  ShoppingBag,
  Sparkles,
  TrendingUp,
  Truck
} from 'lucide-react';
import { api } from '../api/client.js';
import { Loading, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { dt, money } from '../utils/format.js';

function normalizeStatus(value) {
  return String(value || 'unknown').toLowerCase().replace(/[^a-z0-9]+/g, '-');
}

function StatusPill({ value }) {
  const text = String(value || '-').replaceAll('_', ' ');
  return <span className={`statusPill status-${normalizeStatus(value)}`}>{text}</span>;
}

function DashboardMetric({ icon: Icon, label, value, helper, tone = 'navy' }) {
  return (
    <article className={`brandKpi brandKpi-${tone}`}>
      <div className="brandKpiIcon">
        <Icon size={20} />
      </div>
      <div>
        <span>{label}</span>
        <b>{value}</b>
        {helper ? <small>{helper}</small> : null}
      </div>
    </article>
  );
}

function numberValue(value) {
  return Number(value || 0).toLocaleString(undefined, {
    maximumFractionDigits: 2
  });
}

export default function Dashboard() {
  const { data, loading, error, reload } = useLoad(() => api('/api/dashboard'));

  if (loading || error) return <Loading error={error} onRetry={reload} />;

  const kpis = data?.kpis || {};
  const recentOrders = data?.recentOrders || [];
  const dailySales = data?.dailySales || [];
  const lowStock = data?.lowStock || [];

  const activeLocationNames = (data?.locations || [])
    .filter((location) => location.is_active)
    .slice(0, 3)
    .map((location) => location.name)
    .join(', ');

  return (
    <div className="dashboardPage">
      <section className="dashboardHero">
        <div className="dashboardHeroCopy">
          <div className="eyebrow">
            <Sparkles size={16} />
            EBTL Operations
          </div>

          <h2>
            You bring the bottle.
            <span>We bring the magic.</span>
          </h2>

          <p>
            A premium beachside command center for orders, sales, inventory, and
            compound cart readiness.
          </p>

          <div className="heroMeta">
            <span>Central warehouse</span>
            <span>Beach carts</span>
            <span>Fresh cocktail ingredients</span>
          </div>
        </div>

        <div className="dashboardHeroPanel">
          <span className="heroPanelLabel">Today’s pulse</span>
          <strong>{money(kpis.recentRevenue)}</strong>
          <p>Revenue from completed recent orders</p>

          <button className="heroRefreshButton" onClick={reload}>
            <RefreshCw size={16} />
            Refresh dashboard
          </button>
        </div>
      </section>

      <div className="brandKpis">
        <DashboardMetric
          icon={ShoppingBag}
          label="Recent Orders"
          value={kpis.recentOrders}
          helper="Latest 200 orders"
          tone="navy"
        />

        <DashboardMetric
          icon={CheckCircle2}
          label="Completed Orders"
          value={kpis.completedOrders}
          helper="Completed from recent orders"
          tone="teal"
        />

        <DashboardMetric
          icon={TrendingUp}
          label="Recent Revenue"
          value={money(kpis.recentRevenue)}
          helper="Completed order value"
          tone="coral"
        />

        <DashboardMetric
          icon={AlertTriangle}
          label="Low Stock Items"
          value={kpis.lowStockItems}
          helper="Needs replenishment"
          tone="gold"
        />

        <DashboardMetric
          icon={MapPin}
          label="Active Locations"
          value={kpis.activeLocations}
          helper={activeLocationNames || 'Operational locations'}
          tone="seafoam"
        />

        <DashboardMetric
          icon={Truck}
          label="Open Transfers"
          value={kpis.openTransfers}
          helper="Draft, picked, or in transit"
          tone="navy"
        />
      </div>

      <div className="dashboardTables">
        <Section
          title="Recent Orders"
          action={
            <button onClick={reload}>
              <RefreshCw size={16} />
              Refresh
            </button>
          }
        >
          <SimpleTable
            rows={recentOrders}
            columns={[
              'order_number',
              'status',
              'payment_status',
              'total_amount',
              'created_at'
            ]}
            format={{
              status: (value) => <StatusPill value={value} />,
              payment_status: (value) => <StatusPill value={value} />,
              total_amount: money,
              created_at: dt
            }}
          />
        </Section>

        <Section title="Sales by Location">
          <SimpleTable
            rows={dailySales}
            columns={[
              'sales_date',
              'location_name',
              'order_count',
              'gross_sales',
              'average_order_value'
            ]}
            format={{
              gross_sales: money,
              average_order_value: money
            }}
          />
        </Section>
      </div>

      <Section title="Low Stock Watchlist">
        <SimpleTable
          rows={lowStock}
          columns={[
            'location_name',
            'ingredient_name',
            'quantity_on_hand',
            'reorder_point',
            'par_level'
          ]}
          format={{
            quantity_on_hand: numberValue,
            reorder_point: numberValue,
            par_level: numberValue
          }}
        />
      </Section>
    </div>
  );
}
