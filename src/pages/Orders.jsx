import { useMemo, useState } from 'react';
import { RefreshCw } from 'lucide-react';
import { api } from '../api/client.js';
import { Loading, Section } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { dt, money } from '../utils/format.js';

function customizationLines({ item, removedIngredients = [], additions = [] }) {
  const lines = [];
  if (item.customization_summary) lines.push(item.customization_summary);

  if (!item.customization_summary && removedIngredients.length) {
    lines.push(`No ${removedIngredients.map((entry) => entry.ingredient_name_snapshot).filter(Boolean).join(', ')}`);
  }

  if (!item.customization_summary && additions.length) {
    lines.push(`Add ${additions.map((entry) => {
      const qty = Number(entry.quantity_per_parent || 1);
      return qty > 1 ? `${entry.product_name_snapshot} x${qty}` : entry.product_name_snapshot;
    }).filter(Boolean).join(', ')}`);
  }

  return [...new Set(lines.filter(Boolean))];
}

export default function Orders() {
  const { data, loading, error, reload } = useLoad(() => api('/api/orders'));
  const [saving, setSaving] = useState('');

  async function update(id, status) {
    setSaving(id);
    await api(`/api/orders/${id}`, { method: 'PATCH', body: JSON.stringify({ status }) });
    setSaving('');
    reload();
  }

  const itemsByOrderId = useMemo(() => {
    const removedByItemId = new Map();
    for (const row of data?.removedIngredients || []) {
      const list = removedByItemId.get(row.order_item_id) || [];
      list.push(row);
      removedByItemId.set(row.order_item_id, list);
    }

    const additionsByItemId = new Map();
    for (const row of data?.additions || []) {
      const list = additionsByItemId.get(row.order_item_id) || [];
      list.push(row);
      additionsByItemId.set(row.order_item_id, list);
    }

    const grouped = new Map();
    for (const item of data?.items || []) {
      const list = grouped.get(item.order_id) || [];
      list.push({
        ...item,
        removedIngredients: removedByItemId.get(item.id) || [],
        additions: additionsByItemId.get(item.id) || []
      });
      grouped.set(item.order_id, list);
    }
    return grouped;
  }, [data]);

  if (loading || error) return <Loading error={error} />;

  return <Section title="Orders" action={<button onClick={reload}><RefreshCw size={16}/>Refresh</button>}>
    <div className="cardsList">
      {data.orders.map((order) => {
        const orderItems = itemsByOrderId.get(order.id) || [];
        return <div className="rowCard" key={order.id}>
          <div>
            <b>{order.order_number || 'Draft order'}</b>
            <span>{order.customers?.full_name || order.customers?.phone || 'No customer'} · {order.locations?.name}</span>
            <small>{dt(order.created_at)} · {money(order.total_amount)}</small>
            {orderItems.length > 0 && <div className="mutedStack">
              {orderItems.map((item) => <small key={item.id}>
                <b>{item.product_name_snapshot}</b> x{item.quantity}
                {customizationLines({ item, removedIngredients: item.removedIngredients, additions: item.additions }).map((line) => <span key={line}> · {line}</span>)}
              </small>)}
            </div>}
          </div>
          <select value={order.status} disabled={saving === order.id} onChange={e => update(order.id, e.target.value)}>
            {['draft','pending_payment','confirmed','preparing','ready','out_for_delivery','completed','cancelled','refunded'].map(s => <option key={s}>{s}</option>)}
          </select>
        </div>;
      })}
    </div>
  </Section>;
}
