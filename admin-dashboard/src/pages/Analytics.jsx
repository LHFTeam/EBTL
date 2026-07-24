import { useState } from 'react';
import {
  ArrowDownRight,
  ArrowRight,
  ArrowUpRight,
  CheckCircle2,
  Clock,
  MapPin,
  Package,
  RefreshCw,
  ShoppingBag,
  TrendingUp,
  UserPlus,
  Wallet
} from 'lucide-react';
import { api } from '../api/client.js';
import { Loading, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { money } from '../utils/format.js';

function normalizeStatus(value) {
  return String(value || 'unknown').toLowerCase().replace(/[^a-z0-9]+/g, '-');
}

function StatusPill({ value }) {
  const text = String(value || '-').replaceAll('_', ' ');
  return <span className={`statusPill status-${normalizeStatus(value)}`}>{text}</span>;
}

function count(value) {
  return Number(value || 0).toLocaleString();
}

function pct(value, digits = 0) {
  return `${Number(value || 0).toFixed(digits)}%`;
}

function duration(minutes) {
  if (minutes === null || minutes === undefined) return '—';
  const total = Math.max(0, Math.round(Number(minutes)));
  if (total < 60) return `${total}m`;
  const hours = Math.floor(total / 60);
  const mins = total % 60;
  return mins ? `${hours}h ${mins}m` : `${hours}h`;
}

// A KPI whose value grows is "good", except for metrics where lower is better
// (invert = true) such as cancellation rate or prep time.
function DeltaChip({ deltaPct, invert = false }) {
  if (deltaPct === null || deltaPct === undefined) {
    return <span className="deltaChip deltaChip-flat">New</span>;
  }

  const rounded = Math.round(deltaPct);
  if (rounded === 0) {
    return <span className="deltaChip deltaChip-flat"><ArrowRight size={13} /> 0%</span>;
  }

  const positive = deltaPct > 0;
  const good = invert ? !positive : positive;
  const Icon = positive ? ArrowUpRight : ArrowDownRight;

  return (
    <span className={`deltaChip ${good ? 'deltaChip-up' : 'deltaChip-down'}`}>
      <Icon size={13} />
      {Math.abs(rounded)}%
    </span>
  );
}

function KpiCard({ icon: Icon, label, value, kpi, invert = false, tone = 'navy' }) {
  return (
    <article className={`analyticsKpi analyticsKpi-${tone}`}>
      <div className="analyticsKpiTop">
        <span className="analyticsKpiIcon"><Icon size={18} /></span>
        {kpi ? <DeltaChip deltaPct={kpi.deltaPct} invert={invert} /> : null}
      </div>
      <span className="analyticsKpiLabel">{label}</span>
      <b className="analyticsKpiValue">{value}</b>
      <small className="analyticsKpiHelper">vs previous period</small>
    </article>
  );
}

function BarChart({ data }) {
  const max = Math.max(1, ...data.map((point) => point.revenue));
  return (
    <div className="analyticsBars" style={{ '--bar-count': data.length }}>
      {data.map((point) => {
        const height = Math.round((point.revenue / max) * 100);
        const [, month, day] = point.date.split('-');
        return (
          <div className="analyticsBar" key={point.date} title={`${point.date}: ${money(point.revenue)} · ${point.orders} orders`}>
            <div className="analyticsBarTrack">
              <div className="analyticsBarFill" style={{ height: `${Math.max(height, point.revenue > 0 ? 4 : 0)}%` }} />
            </div>
            <span className="analyticsBarLabel">{Number(day)}/{Number(month)}</span>
          </div>
        );
      })}
    </div>
  );
}

function FunnelRow({ status, value, max }) {
  const width = Math.round((value / Math.max(1, max)) * 100);
  return (
    <div className="funnelRow">
      <div className="funnelRowHead">
        <StatusPill value={status} />
        <b>{count(value)}</b>
      </div>
      <div className="funnelTrack">
        <div className={`funnelFill status-${normalizeStatus(status)}`} style={{ width: `${width}%` }} />
      </div>
    </div>
  );
}

function SpeedStat({ icon: Icon, label, value, sampleSize }) {
  return (
    <div className="speedStat">
      <span className="speedStatIcon"><Icon size={16} /></span>
      <div>
        <span className="speedStatLabel">{label}</span>
        <b className="speedStatValue">{value}</b>
        <small className="speedStatMeta">{sampleSize ? `${count(sampleSize)} orders` : 'No data yet'}</small>
      </div>
    </div>
  );
}

export default function Analytics() {
  const [range, setRange] = useState('7d');
  const { data, loading, error, reload } = useLoad(() => api(`/api/analytics?range=${range}`), [range]);

  const presets = data?.presets || [
    { key: 'today', label: 'Today' },
    { key: '7d', label: 'Last 7 days' },
    { key: '30d', label: 'Last 30 days' },
    { key: '90d', label: 'Last 90 days' }
  ];

  const kpis = data?.kpis || {};
  const trend = data?.revenueTrend || [];
  const statusBreakdown = data?.statusBreakdown || [];
  const speed = data?.fulfillment?.speed || {};
  const typeSplit = data?.fulfillment?.typeSplit || [];
  const topProducts = data?.topProducts || [];
  const revenueByLocation = data?.revenueByLocation || [];
  const health = data?.health || {};

  const maxStatus = Math.max(1, ...statusBreakdown.map((entry) => entry.count));
  const trendTotal = trend.reduce((sum, point) => sum + Number(point.revenue || 0), 0);

  return (
    <div className="analyticsPage">
      <div className="analyticsToolbar">
        <div className="rangeSwitcher">
          {presets.map((preset) => (
            <button
              key={preset.key}
              type="button"
              className={range === preset.key ? 'active' : ''}
              onClick={() => setRange(preset.key)}
            >
              {preset.label}
            </button>
          ))}
        </div>
        <button className="analyticsRefresh" type="button" onClick={reload}>
          <RefreshCw size={15} /> Refresh
        </button>
      </div>

      {loading || error ? (
        <Loading error={error} onRetry={reload} />
      ) : (
        <>
          <div className="analyticsKpis">
            <KpiCard icon={TrendingUp} tone="teal" label="Revenue" value={money(kpis.revenue?.value)} kpi={kpis.revenue} />
            <KpiCard icon={ShoppingBag} tone="navy" label="Paid Orders" value={count(kpis.paidOrders?.value)} kpi={kpis.paidOrders} />
            <KpiCard icon={Wallet} tone="coral" label="Avg Order Value" value={money(kpis.avgOrderValue?.value)} kpi={kpis.avgOrderValue} />
            <KpiCard icon={UserPlus} tone="gold" label="New Customers" value={count(kpis.newCustomers?.value)} kpi={kpis.newCustomers} />
            <KpiCard icon={CheckCircle2} tone="seafoam" label="Active Customers" value={count(kpis.activeCustomers?.value)} kpi={kpis.activeCustomers} />
          </div>

          <div className="analyticsGrid analyticsGrid-primary">
            <Section title="Revenue Trend" action={<span className="sectionMeta">{money(trendTotal)} total</span>}>
              {trend.length ? <BarChart data={trend} /> : <div className="empty">No revenue in this period.</div>}
            </Section>

            <Section title="Fulfillment Speed">
              <div className="speedStats">
                <SpeedStat icon={Clock} label="Queue wait (confirmed → preparing)" value={duration(speed.queueWait?.minutes)} sampleSize={speed.queueWait?.sampleSize} />
                <SpeedStat icon={Clock} label="Prep time (preparing → ready)" value={duration(speed.prepTime?.minutes)} sampleSize={speed.prepTime?.sampleSize} />
                <SpeedStat icon={Clock} label="Handoff (ready → completed)" value={duration(speed.handoff?.minutes)} sampleSize={speed.handoff?.sampleSize} />
                <SpeedStat icon={CheckCircle2} label="Total (confirmed → completed)" value={duration(speed.total?.minutes)} sampleSize={speed.total?.sampleSize} />
              </div>
            </Section>
          </div>

          <div className="analyticsGrid analyticsGrid-secondary">
            <Section title="Order Status Breakdown">
              {statusBreakdown.length ? (
                <div className="funnel">
                  {statusBreakdown.map((entry) => (
                    <FunnelRow key={entry.status} status={entry.status} value={entry.count} max={maxStatus} />
                  ))}
                </div>
              ) : <div className="empty">No orders in this period.</div>}
            </Section>

            <Section title="Operational Health">
              <div className="healthGrid">
                <div className="healthStat">
                  <span>Total orders</span>
                  <b>{count(health.totalOrders)}</b>
                </div>
                <div className="healthStat">
                  <span>Completion rate</span>
                  <b>{pct(health.completionRate)}</b>
                </div>
                <div className="healthStat">
                  <span>Cancellation rate</span>
                  <b className={Number(health.cancellationRate) > 0 ? 'healthWarn' : ''}>{pct(health.cancellationRate)}</b>
                </div>
                <div className="healthStat">
                  <span>Paid</span>
                  <b>{count(health.payments?.paid)}</b>
                </div>
                <div className="healthStat">
                  <span>Failed payments</span>
                  <b className={Number(health.payments?.failed) > 0 ? 'healthWarn' : ''}>{count(health.payments?.failed)}</b>
                </div>
                <div className="healthStat">
                  <span>Refunded</span>
                  <b>{count(health.refundedOrders)}</b>
                </div>
              </div>

              {typeSplit.length ? (
                <div className="typeSplit">
                  {typeSplit.map((entry) => (
                    <div className="typeSplitRow" key={entry.type}>
                      <span>{String(entry.type).replaceAll('_', ' ')}</span>
                      <b>{count(entry.orders)} · {money(entry.revenue)}</b>
                    </div>
                  ))}
                </div>
              ) : null}
            </Section>
          </div>

          <div className="analyticsGrid analyticsGrid-secondary">
            <Section title="Top Products" action={<Package size={16} />}>
              <SimpleTable
                rows={topProducts}
                columns={['name', 'quantity', 'revenue']}
                format={{
                  quantity: count,
                  revenue: money
                }}
              />
            </Section>

            <Section title="Revenue by Location" action={<MapPin size={16} />}>
              <SimpleTable
                rows={revenueByLocation}
                columns={['location', 'orders', 'revenue']}
                format={{
                  orders: count,
                  revenue: money
                }}
              />
            </Section>
          </div>
        </>
      )}
    </div>
  );
}
