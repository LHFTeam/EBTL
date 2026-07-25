import { useEffect, useState } from 'react';
import { api } from '../api/client.js';
import { Loading, Message, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { dt, money, toBool } from '../utils/format.js';

const REFEREE_DISCOUNT_TYPES = [
  { value: 'fixed_amount', label: 'Fixed amount off' },
  { value: 'percentage', label: 'Percentage off' }
];

const STATUS_LABELS = {
  pending: 'Pending',
  qualified: 'Qualified',
  rewarded: 'Rewarded',
  void: 'Void'
};

function settingsToForm(settings) {
  return {
    is_active: settings.is_active ?? true,
    referrer_reward_amount: settings.referrer_reward_amount ?? 0,
    referee_discount_type: settings.referee_discount_type || 'fixed_amount',
    referee_discount_value: settings.referee_discount_value ?? 0,
    referee_max_discount_amount: settings.referee_max_discount_amount ?? '',
    min_qualifying_order_value: settings.min_qualifying_order_value ?? 0,
    reward_cap_per_referrer: settings.reward_cap_per_referrer ?? '',
    terms: settings.terms || ''
  };
}

function formToPayload(form) {
  const isPercentage = form.referee_discount_type === 'percentage';
  return {
    is_active: toBool(form.is_active),
    referrer_reward_amount: form.referrer_reward_amount === '' ? 0 : form.referrer_reward_amount,
    referee_discount_type: form.referee_discount_type,
    referee_discount_value: form.referee_discount_value === '' ? 0 : form.referee_discount_value,
    referee_max_discount_amount: isPercentage ? form.referee_max_discount_amount : '',
    min_qualifying_order_value: form.min_qualifying_order_value === '' ? 0 : form.min_qualifying_order_value,
    reward_cap_per_referrer: form.reward_cap_per_referrer,
    terms: form.terms
  };
}

function refereeRewardSummary(settings) {
  const value = Number(settings.referee_discount_value || 0);
  if (settings.referee_discount_type === 'percentage') {
    const cap = settings.referee_max_discount_amount ? ` · max ${money(settings.referee_max_discount_amount)}` : '';
    return `${value}% off${cap}`;
  }
  return `${money(value)} off`;
}

function personLabel(person) {
  if (!person) return '—';
  return person.full_name || person.phone || String(person.id || '').slice(0, 8);
}

function SettingsForm({ value, onChange, onSubmit }) {
  const set = (patch) => onChange({ ...value, ...patch });
  const isPercentage = value.referee_discount_type === 'percentage';

  return <form className="miniForm formGrid" onSubmit={onSubmit}>
    <label className="fieldLabel">
      <span>Referrer reward (EGP store credit)</span>
      <input
        type="number"
        step="0.01"
        min="0"
        value={value.referrer_reward_amount}
        onChange={(e) => set({ referrer_reward_amount: e.target.value })}
      />
    </label>

    <label className="fieldLabel">
      <span>Referee discount type</span>
      <select value={value.referee_discount_type} onChange={(e) => set({ referee_discount_type: e.target.value })}>
        {REFEREE_DISCOUNT_TYPES.map((option) => <option key={option.value} value={option.value}>{option.label}</option>)}
      </select>
    </label>

    <label className="fieldLabel">
      <span>{isPercentage ? 'Referee percent off (%)' : 'Referee amount off (EGP)'}</span>
      <input
        type="number"
        step={isPercentage ? '1' : '0.01'}
        min="0"
        max={isPercentage ? '100' : undefined}
        value={value.referee_discount_value}
        onChange={(e) => set({ referee_discount_value: e.target.value })}
      />
    </label>

    {isPercentage && <label className="fieldLabel">
      <span>Max referee discount (EGP, optional)</span>
      <input
        type="number"
        step="0.01"
        min="0"
        placeholder="No cap"
        value={value.referee_max_discount_amount}
        onChange={(e) => set({ referee_max_discount_amount: e.target.value })}
      />
    </label>}

    <label className="fieldLabel">
      <span>Minimum qualifying order (EGP)</span>
      <input
        type="number"
        step="0.01"
        min="0"
        value={value.min_qualifying_order_value}
        onChange={(e) => set({ min_qualifying_order_value: e.target.value })}
      />
    </label>

    <label className="fieldLabel">
      <span>Reward cap per referrer (optional)</span>
      <input
        type="number"
        step="1"
        min="0"
        placeholder="Unlimited"
        value={value.reward_cap_per_referrer}
        onChange={(e) => set({ reward_cap_per_referrer: e.target.value })}
      />
    </label>

    <label className="fieldLabel full">
      <span>Terms (shown to customers)</span>
      <input
        placeholder="e.g. Reward is granted after your friend's first paid order."
        value={value.terms}
        onChange={(e) => set({ terms: e.target.value })}
      />
    </label>

    <label className="checkboxField">
      <input
        type="checkbox"
        checked={toBool(value.is_active)}
        onChange={(e) => set({ is_active: e.target.checked })}
      />
      <span>Program active</span>
    </label>

    <button className="primary">Save settings</button>
  </form>;
}

export default function Referrals() {
  const settingsLoad = useLoad(() => api('/api/referral-settings'));
  const referralsLoad = useLoad(() => api('/api/referrals'));

  const [form, setForm] = useState(null);
  const [msg, setMsg] = useState('');
  const [msgType, setMsgType] = useState('ok');

  const settings = settingsLoad.data?.settings || null;
  const referrals = referralsLoad.data?.referrals || [];
  const stats = referralsLoad.data?.stats || null;

  useEffect(() => {
    if (settings) setForm(settingsToForm(settings));
  }, [settings]);

  function showMessage(text, type = 'ok') {
    setMsg(text);
    setMsgType(type);
  }

  async function save(e) {
    e.preventDefault();
    setMsg('');
    try {
      await api('/api/referral-settings', {
        method: 'PATCH',
        body: JSON.stringify(formToPayload(form))
      });
      showMessage('Referral settings saved.');
      await settingsLoad.reload();
    } catch (err) {
      showMessage(err.message || 'Request failed', 'error');
    }
  }

  if (settingsLoad.loading || settingsLoad.error) return <Loading error={settingsLoad.error} />;

  return <div className="grid">
    <Section title="Referral Program Settings">
      {form && <SettingsForm value={form} onChange={setForm} onSubmit={save} />}
      {settings && (
        <p className="muted smallText">
          Referrer earns <b>{money(settings.referrer_reward_amount)}</b> store credit ·
          {' '}Referee gets <b>{refereeRewardSummary(settings)}</b> ·
          {' '}Min qualifying order <b>{money(settings.min_qualifying_order_value)}</b> ·
          {' '}{settings.is_active ? 'Active' : 'Paused'}
        </p>
      )}
    </Section>

    <Message text={msg} type={msgType} />

    {stats && (
      <Section title="Referral Performance">
        <div className="kpis">
          <div className="kpi"><span>Total referrals</span><b>{stats.total}</b></div>
          <div className="kpi"><span>Pending</span><b>{stats.pending}</b></div>
          <div className="kpi"><span>Rewarded</span><b>{stats.rewarded}</b></div>
          <div className="kpi"><span>Credit issued</span><b>{money(stats.credit_issued)}</b></div>
        </div>
      </Section>
    )}

    <Section title="Referrals">
      {referralsLoad.loading ? (
        <p className="muted smallText noPad">Loading referrals…</p>
      ) : referrals.length ? (
        <SimpleTable
          rows={referrals}
          columns={['referrer', 'referee', 'code', 'status', 'reward', 'created_at']}
          format={{
            referrer: (_value, row) => personLabel(row.referrer),
            referee: (_value, row) => personLabel(row.referee),
            code: (_value, row) => row.referral_code,
            status: (_value, row) => STATUS_LABELS[row.status] || row.status,
            reward: (_value, row) => (row.status === 'rewarded' ? money(row.referrer_reward_amount) : '—'),
            created_at: (value) => dt(value)
          }}
        />
      ) : (
        <div className="empty">No referrals yet.</div>
      )}
    </Section>
  </div>;
}
