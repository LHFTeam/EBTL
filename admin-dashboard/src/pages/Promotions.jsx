import { useEffect, useMemo, useState } from 'react';
import { api } from '../api/client.js';
import { Loading, Message, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { dt, money, toBool } from '../utils/format.js';

const DISCOUNT_TYPES = [
  { value: 'percentage', label: 'Percentage off' },
  { value: 'fixed_amount', label: 'Fixed amount off' },
  { value: 'free_delivery', label: 'Free delivery' }
];

const FULFILLMENT_OPTIONS = [
  { value: '', label: 'Any (pickup or delivery)' },
  { value: 'pickup_at_cart', label: 'Pickup only' },
  { value: 'delivery_to_unit', label: 'Delivery only' }
];

const blankPromotion = {
  code: '',
  name: '',
  description: '',
  discount_type: 'percentage',
  discount_value: 10,
  max_discount_amount: '',
  min_order_value: 0,
  usage_limit: '',
  per_customer_limit: '',
  first_order_only: false,
  allowed_fulfillment_type: '',
  starts_at: '',
  ends_at: '',
  is_active: true
};

function toDatetimeLocalValue(iso) {
  if (!iso) return '';
  const value = new Date(iso);
  if (Number.isNaN(value.getTime())) return '';
  const pad = (n) => String(n).padStart(2, '0');
  return `${value.getFullYear()}-${pad(value.getMonth() + 1)}-${pad(value.getDate())}T${pad(value.getHours())}:${pad(value.getMinutes())}`;
}

function promotionToForm(promotion) {
  return {
    code: promotion.code || '',
    name: promotion.name || '',
    description: promotion.description || '',
    discount_type: promotion.discount_type || 'percentage',
    discount_value: promotion.discount_value ?? 0,
    max_discount_amount: promotion.max_discount_amount ?? '',
    min_order_value: promotion.min_order_value ?? 0,
    usage_limit: promotion.usage_limit ?? '',
    per_customer_limit: promotion.per_customer_limit ?? '',
    first_order_only: !!promotion.first_order_only,
    allowed_fulfillment_type: promotion.allowed_fulfillment_type || '',
    starts_at: toDatetimeLocalValue(promotion.starts_at),
    ends_at: toDatetimeLocalValue(promotion.ends_at),
    is_active: !!promotion.is_active
  };
}

function formToPayload(form) {
  const isFreeDelivery = form.discount_type === 'free_delivery';
  return {
    code: String(form.code || '').trim().toUpperCase(),
    name: form.name,
    description: form.description,
    discount_type: form.discount_type,
    discount_value: isFreeDelivery ? 0 : form.discount_value,
    max_discount_amount: isFreeDelivery ? '' : form.max_discount_amount,
    min_order_value: form.min_order_value === '' ? 0 : form.min_order_value,
    usage_limit: form.usage_limit,
    per_customer_limit: form.per_customer_limit,
    first_order_only: toBool(form.first_order_only),
    allowed_fulfillment_type: form.allowed_fulfillment_type,
    starts_at: form.starts_at ? new Date(form.starts_at).toISOString() : '',
    ends_at: form.ends_at ? new Date(form.ends_at).toISOString() : '',
    is_active: toBool(form.is_active)
  };
}

function discountSummary(promotion) {
  if (promotion.discount_type === 'percentage') {
    const cap = promotion.max_discount_amount ? ` · max ${money(promotion.max_discount_amount)}` : '';
    return `${Number(promotion.discount_value || 0)}% off${cap}`;
  }
  if (promotion.discount_type === 'fixed_amount') {
    return `${money(promotion.discount_value)} off`;
  }
  if (promotion.discount_type === 'free_delivery') {
    return 'Free delivery';
  }
  return promotion.discount_type;
}

function windowSummary(promotion) {
  const start = promotion.starts_at ? dt(promotion.starts_at) : '—';
  const end = promotion.ends_at ? dt(promotion.ends_at) : '—';
  if (!promotion.starts_at && !promotion.ends_at) return 'Always';
  return `${start} → ${end}`;
}

function limitsSummary(promotion) {
  const parts = [];
  parts.push(promotion.usage_limit ? `${promotion.redemption_count || 0}/${promotion.usage_limit} used` : `${promotion.redemption_count || 0} used`);
  if (promotion.per_customer_limit) parts.push(`${promotion.per_customer_limit}/customer`);
  if (promotion.first_order_only) parts.push('first order');
  if (promotion.allowed_fulfillment_type === 'pickup_at_cart') parts.push('pickup only');
  if (promotion.allowed_fulfillment_type === 'delivery_to_unit') parts.push('delivery only');
  return parts.join(' · ');
}

function PromotionForm({ value, onChange, onSubmit, submitLabel }) {
  const set = (patch) => onChange({ ...value, ...patch });
  const isFreeDelivery = value.discount_type === 'free_delivery';

  return <form className="miniForm formGrid" onSubmit={onSubmit}>
    <label className="fieldLabel">
      <span>Code</span>
      <input
        required
        placeholder="SUMMER20"
        value={value.code}
        onChange={(e) => set({ code: e.target.value.toUpperCase() })}
      />
    </label>

    <label className="fieldLabel">
      <span>Internal name</span>
      <input
        required
        placeholder="Summer 20% launch"
        value={value.name}
        onChange={(e) => set({ name: e.target.value })}
      />
    </label>

    <label className="fieldLabel full">
      <span>Description (internal only)</span>
      <input
        placeholder="Notes for staff — never shown to customers"
        value={value.description}
        onChange={(e) => set({ description: e.target.value })}
      />
    </label>

    <label className="fieldLabel">
      <span>Discount type</span>
      <select value={value.discount_type} onChange={(e) => set({ discount_type: e.target.value })}>
        {DISCOUNT_TYPES.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
      </select>
    </label>

    {!isFreeDelivery && <label className="fieldLabel">
      <span>{value.discount_type === 'percentage' ? 'Percent off (%)' : 'Amount off (EGP)'}</span>
      <input
        type="number"
        step={value.discount_type === 'percentage' ? '1' : '0.01'}
        min="0"
        max={value.discount_type === 'percentage' ? '100' : undefined}
        value={value.discount_value}
        onChange={(e) => set({ discount_value: e.target.value })}
      />
    </label>}

    {value.discount_type === 'percentage' && <label className="fieldLabel">
      <span>Max discount (EGP, optional)</span>
      <input
        type="number"
        step="0.01"
        min="0"
        placeholder="No cap"
        value={value.max_discount_amount}
        onChange={(e) => set({ max_discount_amount: e.target.value })}
      />
    </label>}

    <label className="fieldLabel">
      <span>Minimum order (EGP)</span>
      <input
        type="number"
        step="0.01"
        min="0"
        value={value.min_order_value}
        onChange={(e) => set({ min_order_value: e.target.value })}
      />
    </label>

    <label className="fieldLabel">
      <span>Total usage limit (optional)</span>
      <input
        type="number"
        step="1"
        min="0"
        placeholder="Unlimited"
        value={value.usage_limit}
        onChange={(e) => set({ usage_limit: e.target.value })}
      />
    </label>

    <label className="fieldLabel">
      <span>Per-customer limit (optional)</span>
      <input
        type="number"
        step="1"
        min="0"
        placeholder="Unlimited"
        value={value.per_customer_limit}
        onChange={(e) => set({ per_customer_limit: e.target.value })}
      />
    </label>

    <label className="fieldLabel">
      <span>Valid for</span>
      <select value={value.allowed_fulfillment_type} onChange={(e) => set({ allowed_fulfillment_type: e.target.value })}>
        {FULFILLMENT_OPTIONS.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
      </select>
    </label>

    <label className="fieldLabel">
      <span>Starts (optional)</span>
      <input
        type="datetime-local"
        value={value.starts_at}
        onChange={(e) => set({ starts_at: e.target.value })}
      />
    </label>

    <label className="fieldLabel">
      <span>Ends (optional)</span>
      <input
        type="datetime-local"
        value={value.ends_at}
        onChange={(e) => set({ ends_at: e.target.value })}
      />
    </label>

    <label className="checkboxField">
      <input
        type="checkbox"
        checked={toBool(value.first_order_only)}
        onChange={(e) => set({ first_order_only: e.target.checked })}
      />
      <span>First order only</span>
    </label>

    <label className="checkboxField">
      <input
        type="checkbox"
        checked={toBool(value.is_active)}
        onChange={(e) => set({ is_active: e.target.checked })}
      />
      <span>Active</span>
    </label>

    <button className="primary">{submitLabel}</button>
  </form>;
}

export default function Promotions() {
  const { data, loading, error, reload } = useLoad(() => api('/api/promotions'));
  const promotions = data?.promotions || [];

  const [form, setForm] = useState(blankPromotion);
  const [editing, setEditing] = useState(null);
  const [editForm, setEditForm] = useState(blankPromotion);
  const [detail, setDetail] = useState(null);
  const [detailLoading, setDetailLoading] = useState(false);
  const [msg, setMsg] = useState('');
  const [msgType, setMsgType] = useState('ok');

  const selectedPromotion = useMemo(
    () => promotions.find((promotion) => promotion.id === editing) || null,
    [promotions, editing]
  );

  useEffect(() => {
    if (!selectedPromotion) {
      setDetail(null);
      return;
    }

    setEditForm(promotionToForm(selectedPromotion));

    let cancelled = false;
    setDetailLoading(true);
    api(`/api/promotions/${selectedPromotion.id}`)
      .then((payload) => {
        if (!cancelled) setDetail(payload);
      })
      .catch(() => {
        if (!cancelled) setDetail(null);
      })
      .finally(() => {
        if (!cancelled) setDetailLoading(false);
      });

    return () => {
      cancelled = true;
    };
  }, [selectedPromotion]);

  function showMessage(text, type = 'ok') {
    setMsg(text);
    setMsgType(type);
  }

  async function runAction(action, successText) {
    setMsg('');
    try {
      await action();
      showMessage(successText);
      await reload();
    } catch (err) {
      showMessage(err.message || 'Request failed', 'error');
    }
  }

  async function add(e) {
    e.preventDefault();
    await runAction(async () => {
      await api('/api/promotions', {
        method: 'POST',
        body: JSON.stringify(formToPayload(form))
      });
      setForm(blankPromotion);
    }, 'Promo code created.');
  }

  async function save(e) {
    e.preventDefault();
    await runAction(async () => {
      await api(`/api/promotions/${editing}`, {
        method: 'PATCH',
        body: JSON.stringify(formToPayload(editForm))
      });
    }, 'Promo code updated.');
  }

  async function setPromotionActive(promotion, isActive) {
    if (!isActive && !window.confirm(`Deactivate ${promotion.code}? Customers will no longer be able to redeem it.`)) return;

    await runAction(async () => {
      if (isActive) {
        await api(`/api/promotions/${promotion.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ is_active: true })
        });
      } else {
        await api(`/api/promotions/${promotion.id}`, { method: 'DELETE' });
      }
    }, isActive ? 'Promo code activated.' : 'Promo code deactivated.');
  }

  if (loading || error) return <Loading error={error} />;

  return <div className="grid">
    <Section title="Create Promo Code">
      <PromotionForm value={form} onChange={setForm} onSubmit={add} submitLabel="Create promo code" />
    </Section>

    <Message text={msg} type={msgType} />

    {selectedPromotion && (
      <Section
        title={`Edit Promo Code: ${selectedPromotion.code}`}
        action={<button onClick={() => setEditing(null)}>Close editor</button>}
      >
        <PromotionForm value={editForm} onChange={setEditForm} onSubmit={save} submitLabel="Save changes" />

        <div className="promoStats">
          {detailLoading && <p className="muted smallText noPad">Loading redemptions…</p>}
          {detail && (
            <>
              <div className="promoStatsHead">
                <b>Redemptions</b>
                <span className="muted smallText">
                  {detail.stats.redemption_count} used · {money(detail.stats.total_discount)} discounted
                </span>
              </div>
              {detail.redemptions.length ? (
                <SimpleTable
                  rows={detail.redemptions}
                  columns={['created_at', 'order_id', 'customer_id', 'discount_amount']}
                  format={{
                    created_at: (value) => dt(value),
                    discount_amount: (value) => money(value)
                  }}
                />
              ) : (
                <div className="empty">No redemptions yet.</div>
              )}
            </>
          )}
        </div>
      </Section>
    )}

    <Section title="Promo Codes">
      <SimpleTable
        rows={promotions}
        columns={['code', 'discount', 'window', 'limits', 'is_active']}
        format={{
          code: (_value, row) => <div>
            <b>{row.code}</b>
            <div className="muted smallText">{row.name}</div>
          </div>,
          discount: (_value, row) => discountSummary(row),
          window: (_value, row) => windowSummary(row),
          limits: (_value, row) => limitsSummary(row),
          is_active: (value) => value ? 'Active' : 'Inactive'
        }}
        actions={(row) => (
          <div className="inlineActions">
            <button type="button" onClick={() => setEditing(row.id)}>Edit</button>
            <button
              type="button"
              className={row.is_active ? 'danger' : ''}
              onClick={() => setPromotionActive(row, !row.is_active)}
            >
              {row.is_active ? 'Deactivate' : 'Activate'}
            </button>
          </div>
        )}
      />
    </Section>
  </div>;
}
