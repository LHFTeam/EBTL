import { useMemo, useState } from 'react';
import { AlertTriangle, Megaphone, RefreshCw, Target } from 'lucide-react';
import { api } from '../api/client.js';
import { Loading, Message, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { money } from '../utils/format.js';

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

function units(value) {
  return Number(value || 0).toLocaleString(undefined, { maximumFractionDigits: 1 });
}

function weekdayOf(dateKey) {
  const [year, month, day] = dateKey.split('-').map(Number);
  return WEEKDAYS[new Date(Date.UTC(year, month - 1, day, 12)).getUTCDay()];
}

// Sample size and confidence travel with every number on this page, on purpose.
// A forecast built from two observations must not look like one built from two
// hundred, and the honest way to prevent that is to show the difference rather
// than to suppress the forecast.
function ConfidencePill({ level, sampleSize }) {
  const label = { low: 'Low confidence', medium: 'Fair confidence', high: 'Good confidence' }[level] || 'Low confidence';
  return (
    <span className={`forecastConfidence forecastConfidence-${level || 'low'}`} title={`${sampleSize} trading day${sampleSize === 1 ? '' : 's'} of history behind this estimate`}>
      {label} · n={sampleSize}
    </span>
  );
}

function UpliftBadge({ uplift, campaigns }) {
  if (!campaigns?.length || Math.abs(uplift - 1) < 0.005) return null;
  const pct = Math.round((uplift - 1) * 100);
  return (
    <span className="forecastUplift" title={campaigns.map((c) => c.name).join(', ')}>
      <Megaphone size={12} /> {pct > 0 ? '+' : ''}{pct}%
    </span>
  );
}

function DayCard({ day }) {
  return (
    <div className="forecastDay">
      <div className="forecastDayHead">
        <div>
          <b>{weekdayOf(day.business_date)}</b>
          <span className="muted"> {day.business_date}</span>
        </div>
        <div className="forecastDayBadges">
          <UpliftBadge uplift={day.campaign_uplift} campaigns={day.campaigns} />
          <ConfidencePill level={day.confidence} sampleSize={day.sample_size} />
        </div>
      </div>

      <div className="forecastDayStats">
        <div><span>Expected units</span><b>{units(day.expected_units)}</b></div>
        <div>
          <span title="Stock to this level to serve 90% of days without running out">Stock to (P90)</span>
          <b>{day.p90}</b>
        </div>
        <div><span>Expected orders</span><b>{units(day.expected_orders)}</b></div>
        <div><span>Expected revenue</span><b>{money(day.expected_revenue)}</b></div>
      </div>

      <SimpleTable
        rows={day.products}
        columns={['name', 'expected_units', 'p90', 'mix_share', 'expected_revenue']}
        format={{
          expected_units: (v) => units(v),
          mix_share: (v) => `${(Number(v) * 100).toFixed(1)}%`,
          expected_revenue: (v) => money(v)
        }}
        emptyText="No product forecast for this day yet."
      />
    </div>
  );
}

function AccuracyPanel() {
  const { loading, error, data, reload } = useLoad(() => api('/api/forecast/accuracy'));
  if (loading || error) return <Loading error={error} onRetry={reload} />;

  const backtest = data.backtest || {};
  const beats = backtest.beats_seasonal_naive;

  return (
    <Section
      title="Model accuracy"
      action={<button type="button" className="ghost" onClick={reload}><RefreshCw size={14} /> Refresh</button>}
    >
      {/* MASE is reported against a seasonal-naive (same weekday last week)
          baseline. A value at or above 1 means the model is not beating that,
          which is stated plainly rather than hidden — a forecast nobody can
          check is worse than no forecast. */}
      {beats === false && (
        <div className="forecastWarning">
          <AlertTriangle size={16} />
          <span>
            The model is not yet beating a simple “same weekday last week” baseline
            (MASE {backtest.mase}). Treat these forecasts as planning aids, not
            commitments, until more trading history accumulates.
          </span>
        </div>
      )}

      <div className="kpis">
        <div className="kpi"><span>Days evaluated</span><b>{backtest.evaluated ?? 0}</b></div>
        <div className="kpi"><span title="Mean absolute error, in units">MAE</span><b>{backtest.mae ?? '—'}</b></div>
        <div className="kpi"><span title="Below 1 beats the seasonal-naive baseline">MASE</span><b>{backtest.mase ?? '—'}</b></div>
        <div className="kpi">
          <span title={`Share of days actual demand fell within P90. Target ${(backtest.p90_coverage_target || 0.9) * 100}%`}>P90 coverage</span>
          <b>{backtest.p90_coverage === null || backtest.p90_coverage === undefined ? '—' : `${(backtest.p90_coverage * 100).toFixed(0)}%`}</b>
        </div>
      </div>

      <SimpleTable
        rows={backtest.by_cart || []}
        columns={['location_name', 'evaluated', 'mae', 'mase', 'p90_coverage']}
        format={{ p90_coverage: (v) => (v === null ? '—' : `${(v * 100).toFixed(0)}%`) }}
        emptyText="Not enough history to evaluate yet."
      />
    </Section>
  );
}

function AssumptionsPanel({ carts }) {
  const { loading, error, data, reload } = useLoad(() => api('/api/forecast/assumptions'));
  const [locationId, setLocationId] = useState('');
  const [draft, setDraft] = useState(null);
  const [message, setMessage] = useState('');
  const [saving, setSaving] = useState(false);

  const activeLocation = locationId || carts[0]?.id || '';

  const rows = useMemo(() => {
    if (draft && draft.locationId === activeLocation) return draft.rows;
    const existing = new Map(
      (data?.assumptions || [])
        .filter((row) => row.location_id === activeLocation)
        .map((row) => [row.day_of_week, row])
    );
    return WEEKDAYS.map((_, dow) => ({
      day_of_week: dow,
      expected_units: existing.get(dow)?.expected_units ?? '',
      prior_strength_days: existing.get(dow)?.prior_strength_days ?? data?.default_prior_strength_days ?? 14
    }));
  }, [data, activeLocation, draft]);

  if (loading || error) return <Loading error={error} onRetry={reload} />;

  const update = (dow, field, value) => {
    setDraft({
      locationId: activeLocation,
      rows: rows.map((row) => (row.day_of_week === dow ? { ...row, [field]: value } : row))
    });
  };

  const save = async () => {
    setSaving(true);
    setMessage('');
    try {
      await api('/api/forecast/assumptions', {
        method: 'PUT',
        body: JSON.stringify({
          location_id: activeLocation,
          rows: rows.map((row) => ({
            day_of_week: row.day_of_week,
            expected_units: row.expected_units === '' ? null : Number(row.expected_units),
            prior_strength_days: Number(row.prior_strength_days) || 14
          }))
        })
      });
      setDraft(null);
      setMessage('Saved. The next nightly run will use these.');
      reload();
    } catch (e) {
      setMessage(e.message);
    } finally {
      setSaving(false);
    }
  };

  return (
    <Section title="Planning assumptions">
      {/* These are the model's prior. They dominate while there is little data
          and fade on their own as trading days accumulate — nobody has to come
          back and delete them. */}
      <p className="muted">
        What you expect a cart to sell on each weekday. The model starts from these
        and moves away from them as real sales arrive; “prior strength” is how many
        trading days it takes for the data to outweigh your number.
      </p>

      <div className="miniForm">
        <label>
          Cart
          <select value={activeLocation} onChange={(e) => { setLocationId(e.target.value); setDraft(null); }}>
            {carts.map((cart) => <option key={cart.id} value={cart.id}>{cart.name}</option>)}
          </select>
        </label>
      </div>

      <div className="tableWrap">
        <table>
          <thead><tr><th>Day</th><th>Expected units</th><th>Prior strength (days)</th></tr></thead>
          <tbody>
            {rows.map((row) => (
              <tr key={row.day_of_week}>
                <td>{WEEKDAYS[row.day_of_week]}</td>
                <td>
                  <input
                    type="number" min="0" step="1" placeholder="—"
                    value={row.expected_units}
                    onChange={(e) => update(row.day_of_week, 'expected_units', e.target.value)}
                  />
                </td>
                <td>
                  <input
                    type="number" min="1" max="365" step="1"
                    value={row.prior_strength_days}
                    onChange={(e) => update(row.day_of_week, 'prior_strength_days', e.target.value)}
                  />
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div className="miniForm">
        <button type="button" className="primary" onClick={save} disabled={saving}>
          {saving ? 'Saving…' : 'Save assumptions'}
        </button>
      </div>
      <Message text={message} type={message.startsWith('Saved') ? 'ok' : 'error'} />
    </Section>
  );
}

export default function Forecast() {
  const [locationId, setLocationId] = useState('');
  const [days, setDays] = useState(7);
  const [running, setRunning] = useState(false);
  const [runMessage, setRunMessage] = useState('');

  const { loading, error, data, reload } = useLoad(
    () => api(`/api/forecast?days=${days}${locationId ? `&location_id=${locationId}` : ''}`),
    [locationId, days]
  );

  if (loading || error) return <Loading error={error} onRetry={reload} />;

  const runNow = async () => {
    setRunning(true);
    setRunMessage('');
    try {
      const result = await api('/api/forecast/run', { method: 'POST', body: JSON.stringify({}) });
      setRunMessage(result.datesProcessed
        ? `Processed ${result.datesProcessed} day(s); wrote ${result.forecastsWritten} forecasts.`
        : `Already up to date${result.reason ? ` (${result.reason})` : ''}.`);
      reload();
    } catch (e) {
      setRunMessage(e.message);
    } finally {
      setRunning(false);
    }
  };

  const byCart = new Map();
  for (const day of data.forecasts) {
    if (!byCart.has(day.location_id)) byCart.set(day.location_id, { name: day.location_name, days: [] });
    byCart.get(day.location_id).days.push(day);
  }

  const lastRun = data.last_run;

  return (
    <>
      <Section
        title="Demand forecast"
        action={
          <button type="button" className="ghost" onClick={runNow} disabled={running}>
            <RefreshCw size={14} /> {running ? 'Running…' : 'Update now'}
          </button>
        }
      >
        <p className="muted">
          <Target size={13} /> Expected units per cart per day, with a P90 stocking
          level — load to P90 and you run out on about one day in ten. Updates
          automatically each night from the previous day's sales.
        </p>

        <div className="miniForm">
          <label>
            Cart
            <select value={locationId} onChange={(e) => setLocationId(e.target.value)}>
              <option value="">All carts</option>
              {data.carts.map((cart) => <option key={cart.id} value={cart.id}>{cart.name}</option>)}
            </select>
          </label>
          <label>
            Horizon
            <select value={days} onChange={(e) => setDays(Number(e.target.value))}>
              <option value={7}>Next 7 days</option>
              <option value={14}>Next 14 days</option>
            </select>
          </label>
        </div>

        <Message text={runMessage} type={runMessage.includes('Processed') || runMessage.includes('up to date') ? 'ok' : 'error'} />

        {lastRun && (
          <p className="muted">
            Last run {lastRun.finished_at ? new Date(lastRun.finished_at).toLocaleString() : 'in progress'}
            {lastRun.status === 'failed' ? ` — failed: ${lastRun.error}` : ''}
            {lastRun.through_date ? ` · through ${lastRun.through_date}` : ''}
            {' · model '}{data.model.version}
          </p>
        )}
      </Section>

      {[...byCart.entries()].map(([cartId, cart]) => (
        <Section key={cartId} title={cart.name}>
          <div className="forecastDays">
            {cart.days.map((day) => <DayCard key={day.business_date} day={day} />)}
          </div>
        </Section>
      ))}

      {!byCart.size && (
        <Section title="No forecast yet">
          <p className="muted">
            Nothing has been generated. Use “Update now” above to run the model
            against the sales history that exists.
          </p>
        </Section>
      )}

      <AssumptionsPanel carts={data.carts} />
      <AccuracyPanel />
    </>
  );
}
