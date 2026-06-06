import { useState } from 'react';
import { api } from '../api/client.js';
import { Loading, Message, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { toBool } from '../utils/format.js';

const blank = {
  name: '',
  type: 'beach_cart',
  compound_name: '',
  beach_name: '',
  address: '',
  delivery_fee: '0',
  latitude: '',
  longitude: '',
  is_active: true
};

function hasText(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function emptyToNull(value) {
  return typeof value === 'string' && value.trim() === '' ? null : value;
}

function isProtectedCentralWarehouse(location) {
  return (
    location?.type === 'central_warehouse' &&
    String(location?.name || '').trim().toLowerCase() === 'central warehouse'
  );
}

function buildPayload(form, isEditing) {
  const payload = { ...form };

  if (!isEditing) return payload;

  for (const key of ['compound_name', 'beach_name', 'address', 'latitude', 'longitude']) {
    payload[key] = emptyToNull(payload[key]);
  }

  payload.delivery_fee = payload.delivery_fee === '' ? 0 : payload.delivery_fee;

  return payload;
}

export default function Locations() {
  const { data: loadedLocations, loading, error, reload } = useLoad(() => api('/api/locations'));
  const data = Array.isArray(loadedLocations) ? loadedLocations : [];

  const [form, setForm] = useState(blank);
  const [editing, setEditing] = useState(null);
  const [message, setMessage] = useState('');
  const [formError, setFormError] = useState('');

  const editingRow = data.find((location) => location.id === editing);
  const editingProtectedCentralWarehouse = isProtectedCentralWarehouse(editingRow);

  function resetForm() {
    setForm(blank);
    setEditing(null);
    setFormError('');
    setMessage('');
  }

  function validateForm() {
    if (form.type === 'beach_cart' && !hasText(form.compound_name)) {
      return 'Beach cart locations require a compound name.';
    }

    if (editingProtectedCentralWarehouse && form.type !== 'central_warehouse') {
      return 'Central Warehouse type is protected and cannot be changed.';
    }

    if (editingProtectedCentralWarehouse && !toBool(form.is_active)) {
      return 'Central Warehouse is protected and cannot be deactivated.';
    }

    return '';
  }

  async function save(e) {
    e.preventDefault();
    setFormError('');
    setMessage('');

    const validationError = validateForm();

    if (validationError) {
      setFormError(validationError);
      return;
    }

    try {
      const payload = buildPayload(form, Boolean(editing));

      if (editing) {
        await api(`/api/locations/${editing}`, {
          method: 'PATCH',
          body: JSON.stringify(payload)
        });

        setMessage('Location updated.');
      } else {
        await api('/api/locations', {
          method: 'POST',
          body: JSON.stringify(payload)
        });

        setMessage('Location added.');
      }

      setForm(blank);
      setEditing(null);
      await reload();
    } catch (err) {
      setFormError(err.message || 'Could not save location.');
    }
  }

  function edit(row) {
    setEditing(row.id);

    setForm({
      ...blank,
      ...row,
      compound_name: row.compound_name ?? '',
      beach_name: row.beach_name ?? '',
      address: row.address ?? '',
      delivery_fee: row.delivery_fee ?? '0',
      latitude: row.latitude ?? '',
      longitude: row.longitude ?? ''
    });

    setFormError('');
    setMessage('');

    window.scrollTo({ top: 0, behavior: 'smooth' });
  }

  async function deactivate(row) {
    setFormError('');
    setMessage('');

    if (isProtectedCentralWarehouse(row)) {
      setFormError('Central Warehouse is protected and cannot be deactivated.');
      return;
    }

    const confirmed = window.confirm(
      `Deactivate ${row.name}? This is a soft delete and the location can be reactivated later.`
    );

    if (!confirmed) return;

    try {
      await api(`/api/locations/${row.id}/deactivate`, {
        method: 'PATCH'
      });

      if (editing === row.id) resetForm();

      setMessage('Location deactivated.');
      await reload();
    } catch (err) {
      setFormError(err.message || 'Could not deactivate location.');
    }
  }

  async function activate(row) {
    setFormError('');
    setMessage('');

    try {
      await api(`/api/locations/${row.id}`, {
        method: 'PATCH',
        body: JSON.stringify({ is_active: true })
      });

      setMessage('Location activated.');
      await reload();
    } catch (err) {
      setFormError(err.message || 'Could not activate location.');
    }
  }

  if (loading || error) return <Loading error={error} />;

  return (
    <div className="grid">
      <Section
        title={editing ? 'Edit Location' : 'Add Location'}
        action={editing && <button onClick={resetForm}>Cancel edit</button>}
      >
        <Message text={message} />
        <Message text={formError} type="error" />

        {editingProtectedCentralWarehouse && (
          <div className="muted helperText">
            Central Warehouse is protected. You can edit address and coordinates, but you cannot change its name, type, or active status.
          </div>
        )}

        <form className="miniForm formGrid" onSubmit={save}>
          <input
            required
            placeholder="Name"
            value={form.name}
            disabled={editingProtectedCentralWarehouse}
            onChange={(e) => setForm({ ...form, name: e.target.value })}
          />

          <select
            value={form.type}
            disabled={editingProtectedCentralWarehouse}
            onChange={(e) => setForm({ ...form, type: e.target.value })}
          >
            <option value="central_warehouse">central_warehouse</option>
            <option value="beach_cart">beach_cart</option>
          </select>

          <label>
            Compound name{' '}
            {form.type === 'beach_cart' && (
              <span className="requiredHint">required for beach carts</span>
            )}

            <input
              placeholder="Compound name"
              value={form.compound_name ?? ''}
              aria-invalid={form.type === 'beach_cart' && !hasText(form.compound_name)}
              onChange={(e) => setForm({ ...form, compound_name: e.target.value })}
            />
          </label>

          <input
            placeholder="Beach name"
            value={form.beach_name ?? ''}
            onChange={(e) => setForm({ ...form, beach_name: e.target.value })}
          />

          <input
            placeholder="Address"
            value={form.address ?? ''}
            onChange={(e) => setForm({ ...form, address: e.target.value })}
          />

          <input
            type="number"
            step="0.01"
            min="0"
            placeholder="Delivery fee"
            value={form.delivery_fee ?? ''}
            onChange={(e) => setForm({ ...form, delivery_fee: e.target.value })}
          />

          <input
            type="number"
            step="0.0000001"
            placeholder="Latitude"
            value={form.latitude ?? ''}
            onChange={(e) => setForm({ ...form, latitude: e.target.value })}
          />

          <input
            type="number"
            step="0.0000001"
            placeholder="Longitude"
            value={form.longitude ?? ''}
            onChange={(e) => setForm({ ...form, longitude: e.target.value })}
          />

          <label>
            <input
              type="checkbox"
              checked={toBool(form.is_active)}
              disabled={editingProtectedCentralWarehouse}
              onChange={(e) => setForm({ ...form, is_active: e.target.checked })}
            />
            Active
          </label>

          <button className="primary">
            {editing ? 'Save Changes' : 'Add Location'}
          </button>
        </form>
      </Section>

      <Section title="Locations">
        <SimpleTable
          rows={data}
          columns={['name', 'type', 'compound_name', 'beach_name', 'address', 'delivery_fee', 'is_active']}
          actions={(row) => {
            const protectedCentralWarehouse = isProtectedCentralWarehouse(row);

            return (
              <div className="inlineActions">
                <button onClick={() => edit(row)}>Edit</button>

                {protectedCentralWarehouse ? (
                  <button disabled title="Central Warehouse cannot be deactivated.">
                    Protected
                  </button>
                ) : row.is_active ? (
                  <button onClick={() => deactivate(row)}>Deactivate</button>
                ) : (
                  <button onClick={() => activate(row)}>Activate</button>
                )}
              </div>
            );
          }}
        />
      </Section>
    </div>
  );
}
