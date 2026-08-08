import { useState } from 'react';
import { Megaphone, Trash2 } from 'lucide-react';
import { api } from '../api/client.js';
import { Loading, Message, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { humanize } from '../utils/format.js';

const EMPTY = {
  name: '',
  campaign_type: 'promo_code',
  scope: 'network',
  starts_on: '',
  ends_on: '',
  discount_pct: '',
  expected_uplift_pct: '30',
  notes: '',
  location_ids: [],
  product_ids: []
};

function upliftLabel(campaign) {
  const pct = Math.round((campaign.resolved_uplift - 1) * 100);
  const source = {
    planned: 'from your estimate',
    blended: 'estimate + early results',
    learned: 'measured'
  }[campaign.uplift_source] || 'from your estimate';
  return `${pct > 0 ? '+' : ''}${pct}% (${source})`;
}

export default function ForecastCampaigns() {
  const { loading, error, data, reload } = useLoad(() => api('/api/forecast/campaigns'));
  const [form, setForm] = useState(EMPTY);
  const [message, setMessage] = useState('');
  const [saving, setSaving] = useState(false);

  if (loading || error) return <Loading error={error} onRetry={reload} />;

  const set = (field, value) => setForm((current) => ({ ...current, [field]: value }));

  const multi = (event) => [...event.target.selectedOptions].map((option) => option.value);

  const create = async () => {
    setSaving(true);
    setMessage('');
    try {
      await api('/api/forecast/campaigns', {
        method: 'POST',
        body: JSON.stringify({
          name: form.name,
          campaign_type: form.campaign_type,
          scope: form.scope,
          starts_on: form.starts_on,
          ends_on: form.ends_on,
          discount_pct: form.discount_pct === '' ? null : Number(form.discount_pct),
          expected_uplift_pct: Number(form.expected_uplift_pct) || 0,
          notes: form.notes || null,
          location_ids: form.scope === 'cart' ? form.location_ids : [],
          product_ids: form.scope === 'product' ? form.product_ids : []
        })
      });
      setForm(EMPTY);
      setMessage('Campaign saved. Forecasts update on the next run.');
      reload();
    } catch (e) {
      setMessage(e.message);
    } finally {
      setSaving(false);
    }
  };

  const remove = async (id) => {
    try {
      await api(`/api/forecast/campaigns/${id}`, { method: 'DELETE' });
      reload();
    } catch (e) {
      setMessage(e.message);
    }
  };

  const toggle = async (campaign) => {
    try {
      await api(`/api/forecast/campaigns/${campaign.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ is_active: !campaign.is_active })
      });
      reload();
    } catch (e) {
      setMessage(e.message);
    }
  };

  return (
    <>
      <Section title="What campaigns do to the forecast">
        {/* This calendar is deliberately separate from Promo Codes. A campaign
            here changes forecasts and nothing else — it grants no discount — which
            is what lets it cover the things that actually move a beach cart and
            never involve a code. */}
        <p className="muted">
          Recording a campaign does two things: past campaign days are divided back
          out so a promotion never permanently inflates the baseline, and scheduled
          campaigns raise the forecast <em>before</em> they run, so carts are stocked
          for them.
        </p>
        <p className="muted">
          These entries affect forecasting only — they grant no discount. To give a
          real discount, create a promo code under Marketing → Promo Codes and link
          it here. A <b>cart</b> campaign lifts total volume; a <b>product</b>
          campaign shifts the mix toward the products you pick, taking share from the
          rest. If a product push should also grow total volume, add a second
          cart-scoped campaign for it.
        </p>
      </Section>

      <Section title="New campaign">
        <div className="miniForm">
          <label>
            Name
            <input value={form.name} onChange={(e) => set('name', e.target.value)} placeholder="Eid weekend push" />
          </label>
          <label>
            Type
            <select value={form.campaign_type} onChange={(e) => set('campaign_type', e.target.value)}>
              {data.campaign_types.map((type) => <option key={type} value={type}>{humanize(type)}</option>)}
            </select>
          </label>
          <label>
            Scope
            <select value={form.scope} onChange={(e) => set('scope', e.target.value)}>
              <option value="network">All carts (volume)</option>
              <option value="cart">Specific carts (volume)</option>
              <option value="product">Specific products (mix)</option>
            </select>
          </label>
          <label>
            Starts
            <input type="date" value={form.starts_on} onChange={(e) => set('starts_on', e.target.value)} />
          </label>
          <label>
            Ends
            <input type="date" value={form.ends_on} onChange={(e) => set('ends_on', e.target.value)} />
          </label>
          <label>
            Discount %
            <input type="number" min="0" max="100" value={form.discount_pct} onChange={(e) => set('discount_pct', e.target.value)} placeholder="optional" />
          </label>
          <label>
            Expected uplift %
            <input type="number" min="-99" max="400" value={form.expected_uplift_pct} onChange={(e) => set('expected_uplift_pct', e.target.value)} />
          </label>
        </div>

        {form.scope === 'cart' && (
          <div className="miniForm">
            <label>
              Carts
              <select multiple value={form.location_ids} onChange={(e) => set('location_ids', multi(e))}>
                {data.carts.map((cart) => <option key={cart.id} value={cart.id}>{cart.name}</option>)}
              </select>
            </label>
          </div>
        )}

        {form.scope === 'product' && (
          <div className="miniForm">
            <label>
              Products
              <select multiple size={8} value={form.product_ids} onChange={(e) => set('product_ids', multi(e))}>
                {data.products.map((product) => <option key={product.id} value={product.id}>{product.name}</option>)}
              </select>
            </label>
          </div>
        )}

        <div className="miniForm">
          <label>
            Notes
            <input value={form.notes} onChange={(e) => set('notes', e.target.value)} placeholder="optional" />
          </label>
          <button type="button" className="primary" onClick={create} disabled={saving || !form.name || !form.starts_on || !form.ends_on}>
            <Megaphone size={14} /> {saving ? 'Saving…' : 'Add campaign'}
          </button>
        </div>

        <Message text={message} type={message.startsWith('Campaign saved') ? 'ok' : 'error'} />
      </Section>

      <Section title="Campaigns">
        {/* Planned and measured lift are shown side by side: a number the model
            is still taking on trust must be distinguishable from one it has seen
            happen. */}
        <SimpleTable
          rows={data.campaigns}
          columns={['name', 'campaign_type', 'scope', 'starts_on', 'ends_on', 'expected_uplift_pct', 'applied_uplift', 'learned_observations', 'is_active']}
          format={{
            campaign_type: (v) => humanize(v),
            scope: (v) => humanize(v),
            expected_uplift_pct: (v) => `${Number(v) > 0 ? '+' : ''}${Number(v)}%`,
            applied_uplift: (_v, row) => upliftLabel(row),
            learned_observations: (v) => (v ? `${v} day${v === 1 ? '' : 's'} measured` : 'not yet run'),
            is_active: (v) => (v ? 'Active' : 'Paused')
          }}
          actions={(row) => (
            <>
              <button type="button" className="ghost" onClick={() => toggle(row)}>
                {row.is_active ? 'Pause' : 'Resume'}
              </button>
              <button type="button" className="ghost danger" onClick={() => remove(row.id)}>
                <Trash2 size={14} />
              </button>
            </>
          )}
          emptyText="No campaigns recorded yet."
        />
      </Section>
    </>
  );
}
