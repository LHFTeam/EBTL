import { useState } from 'react';
import { api } from '../api/client.js';
import { Loading, Message, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { humanize, toBool } from '../utils/format.js';

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

const MAX_LOCATION_BANNER_BYTES = 3 * 1024 * 1024;

const DAYS = [
  { day_of_week: 0, label: 'Sunday' },
  { day_of_week: 1, label: 'Monday' },
  { day_of_week: 2, label: 'Tuesday' },
  { day_of_week: 3, label: 'Wednesday' },
  { day_of_week: 4, label: 'Thursday' },
  { day_of_week: 5, label: 'Friday' },
  { day_of_week: 6, label: 'Saturday' }
];

function hasText(value) {
  return typeof value === 'string' && value.trim().length > 0;
}

function emptyToNull(value) {
  return typeof value === 'string' && value.trim() === '' ? null : value;
}

function timeForInput(value) {
  if (!value) return '';
  return String(value).slice(0, 5);
}

function defaultOpeningHours() {
  return DAYS.map((day) => ({
    day_of_week: day.day_of_week,
    is_closed: true,
    opens_at: '10:00',
    closes_at: '19:00'
  }));
}

function buildOpeningHoursForm(rows = []) {
  const byDay = new Map((rows || []).map((row) => [Number(row.day_of_week), row]));

  return DAYS.map((day) => {
    const row = byDay.get(day.day_of_week);

    if (!row) {
      return {
        day_of_week: day.day_of_week,
        is_closed: true,
        opens_at: '10:00',
        closes_at: '19:00'
      };
    }

    return {
      day_of_week: day.day_of_week,
      is_closed: Boolean(row.is_closed),
      opens_at: timeForInput(row.opens_at) || '10:00',
      closes_at: timeForInput(row.closes_at) || '19:00'
    };
  });
}

function openingHoursPayload(hours) {
  return {
    hours: hours.map((row) => ({
      day_of_week: row.day_of_week,
      is_closed: Boolean(row.is_closed),
      opens_at: row.is_closed ? null : row.opens_at,
      closes_at: row.is_closed ? null : row.closes_at
    }))
  };
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

function fileSizeLabel(bytes) {
  if (!bytes) return '0 KB';
  if (bytes < 1024 * 1024) return `${Math.ceil(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(2)} MB`;
}

function isWebpFile(file) {
  return file && (file.type === 'image/webp' || file.name.toLowerCase().endsWith('.webp'));
}

function arrayBufferToBase64(buffer) {
  const bytes = new Uint8Array(buffer);
  let binary = '';
  const chunkSize = 0x8000;

  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }

  return btoa(binary);
}

async function imageUploadPayload(file) {
  return {
    file_name: file.name,
    content_type: file.type || 'image/webp',
    data_base64: arrayBufferToBase64(await file.arrayBuffer())
  };
}

function LocationBannerPreview({ src, label = 'No banner' }) {
  return (
    <div className="locationBannerPreviewBox">
      {src ? <img className="locationBannerPreview" src={src} alt="Location banner" /> : <span className="imagePlaceholder">{label}</span>}
    </div>
  );
}

export default function Locations() {
  const { data: loadedLocations, loading, error, reload } = useLoad(() => api('/api/locations'));
  const data = Array.isArray(loadedLocations) ? loadedLocations : [];

  const [form, setForm] = useState(blank);
  const [editing, setEditing] = useState(null);
  const [message, setMessage] = useState('');
  const [formError, setFormError] = useState('');
  const [bannerFile, setBannerFile] = useState(null);
  const [openingHours, setOpeningHours] = useState(defaultOpeningHours());
  const [hoursLoading, setHoursLoading] = useState(false);

  const editingRow = data.find((location) => location.id === editing);
  const editingProtectedCentralWarehouse = isProtectedCentralWarehouse(editingRow);

  function resetForm() {
    setForm(blank);
    setEditing(null);
    setBannerFile(null);
    setOpeningHours(defaultOpeningHours());
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

  function validateOpeningHours() {
    for (const row of openingHours) {
      const dayLabel = DAYS.find((day) => day.day_of_week === row.day_of_week)?.label || 'Day';

      if (row.is_closed) continue;

      if (!row.opens_at || !row.closes_at) {
        return `${dayLabel}: open and close times are required unless the day is closed.`;
      }

      if (row.opens_at === row.closes_at) {
        return `${dayLabel}: open and close times cannot be the same.`;
      }
    }

    return '';
  }

  function chooseBannerFile(file) {
    setFormError('');
    setMessage('');

    if (!file) {
      setBannerFile(null);
      return;
    }

    if (!isWebpFile(file)) {
      setBannerFile(null);
      setFormError('Please choose a .webp image file.');
      return;
    }

    if (file.size > MAX_LOCATION_BANNER_BYTES) {
      setBannerFile(null);
      setFormError('Image is too large. Maximum size is 3 MB.');
      return;
    }

    setBannerFile(file);
  }

  function patchOpeningHour(dayOfWeek, patch) {
    setOpeningHours((current) => current.map((row) => (
      row.day_of_week === dayOfWeek ? { ...row, ...patch } : row
    )));
  }

  async function loadOpeningHours(locationId) {
    setHoursLoading(true);

    try {
      const response = await api(`/api/locations/${locationId}/opening-hours`);
      setOpeningHours(buildOpeningHoursForm(response.hours || []));
    } catch (err) {
      setOpeningHours(defaultOpeningHours());
      setFormError(err.message || 'Could not load opening hours.');
    } finally {
      setHoursLoading(false);
    }
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

        setMessage('Location added. Edit the new location to upload a banner and set opening hours.');
      }

      setForm(blank);
      setEditing(null);
      setBannerFile(null);
      setOpeningHours(defaultOpeningHours());
      await reload();
    } catch (err) {
      setFormError(err.message || 'Could not save location.');
    }
  }

  async function edit(row) {
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

    setBannerFile(null);
    setOpeningHours(defaultOpeningHours());
    setFormError('');
    setMessage('');

    window.scrollTo({ top: 0, behavior: 'smooth' });
    await loadOpeningHours(row.id);
  }

  async function uploadBanner(e) {
    e.preventDefault();
    setFormError('');
    setMessage('');

    if (!editing) {
      setFormError('Save the location first, then upload a banner.');
      return;
    }

    if (!bannerFile) {
      setFormError('Choose a .webp banner image first.');
      return;
    }

    try {
      await api(`/api/locations/${editing}/banner`, {
        method: 'POST',
        body: JSON.stringify(await imageUploadPayload(bannerFile))
      });

      setBannerFile(null);
      setMessage('Location banner uploaded.');
      await reload();
    } catch (err) {
      setFormError(err.message || 'Could not upload location banner.');
    }
  }

  async function removeBanner() {
    setFormError('');
    setMessage('');

    if (!editing) return;
    if (!window.confirm('Remove this location banner image?')) return;

    try {
      await api(`/api/locations/${editing}/banner`, { method: 'DELETE' });
      setBannerFile(null);
      setMessage('Location banner removed.');
      await reload();
    } catch (err) {
      setFormError(err.message || 'Could not remove location banner.');
    }
  }

  async function saveOpeningHours(e) {
    e.preventDefault();
    setFormError('');
    setMessage('');

    if (!editing) {
      setFormError('Save the location first, then set opening hours.');
      return;
    }

    const validationError = validateOpeningHours();

    if (validationError) {
      setFormError(validationError);
      return;
    }

    try {
      await api(`/api/locations/${editing}/opening-hours`, {
        method: 'PUT',
        body: JSON.stringify(openingHoursPayload(openingHours))
      });

      setMessage('Opening hours saved.');
      await loadOpeningHours(editing);
    } catch (err) {
      setFormError(err.message || 'Could not save opening hours.');
    }
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

  if (loading || error) return <Loading error={error} onRetry={reload} />;

  return (
    <div className="grid">
      <Section
        title={editing ? 'Edit Location' : 'Add Location'}
        action={editing && <button type="button" onClick={resetForm}>Cancel edit</button>}
      >
        <Message text={message} />
        <Message text={formError} type="error" />

        {editingProtectedCentralWarehouse && (
          <div className="muted helperText">
            Central Warehouse is protected. You can edit address, coordinates, delivery fee, banner image, and opening hours, but you cannot change its name, type, or active status.
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
            <option value="central_warehouse">Central Warehouse</option>
            <option value="beach_cart">Beach Cart</option>
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

          <label className="checkboxField">
            <input
              type="checkbox"
              checked={toBool(form.is_active)}
              disabled={editingProtectedCentralWarehouse}
              onChange={(e) => setForm({ ...form, is_active: e.target.checked })}
            />
            <span>Active</span>
          </label>

          <button className="primary">
            {editing ? 'Save Changes' : 'Add Location'}
          </button>
        </form>

        {editing && (
          <div className="locationAssetGrid">
            <div className="subPanel noTopMargin">
              <h3>Location banner image</h3>
              <div className="shopAssetRow">
                <LocationBannerPreview src={editingRow?.banner_image_url} />

                <div className="imageUploadControls">
                  <b>Customer app location banner</b>
                  <p className="muted smallText noPad">
                    Upload a public WebP banner for this beach cart/location. Maximum file size is 3 MB.
                  </p>

                  <form className="miniForm inlineShopUpload" onSubmit={uploadBanner}>
                    <label className="fileButton">
                      <input
                        type="file"
                        accept="image/webp,.webp"
                        onChange={(e) => chooseBannerFile(e.target.files?.[0])}
                      />
                      <span>{bannerFile ? 'Change WebP banner' : 'Choose WebP banner'}</span>
                    </label>

                    <button className="primary" disabled={!bannerFile}>Upload banner</button>

                    {editingRow?.banner_image_url && (
                      <button type="button" onClick={removeBanner}>Remove</button>
                    )}
                  </form>

                  {bannerFile && (
                    <div className="selectedFile">
                      Selected: {bannerFile.name} · {fileSizeLabel(bannerFile.size)}
                    </div>
                  )}
                </div>
              </div>
            </div>

            <div className="subPanel noTopMargin">
              <h3>Opening hours</h3>
              <p className="muted smallText noPad">
                Days use Cairo business time. Closed days are still saved so the app can show accurate availability.
              </p>

              {hoursLoading ? (
                <div className="muted">Loading opening hours…</div>
              ) : (
                <form className="openingHoursForm" onSubmit={saveOpeningHours}>
                  {openingHours.map((row) => {
                    const day = DAYS.find((item) => item.day_of_week === row.day_of_week);

                    return (
                      <div className="openingHourLine" key={row.day_of_week}>
                        <b>{day?.label}</b>

                        <label className="checkboxField">
                          <input
                            type="checkbox"
                            checked={Boolean(row.is_closed)}
                            onChange={(e) => patchOpeningHour(row.day_of_week, { is_closed: e.target.checked })}
                          />
                          <span>Closed</span>
                        </label>

                        <label>
                          Opens
                          <input
                            type="time"
                            value={row.opens_at}
                            disabled={row.is_closed}
                            onChange={(e) => patchOpeningHour(row.day_of_week, { opens_at: e.target.value })}
                          />
                        </label>

                        <label>
                          Closes
                          <input
                            type="time"
                            value={row.closes_at}
                            disabled={row.is_closed}
                            onChange={(e) => patchOpeningHour(row.day_of_week, { closes_at: e.target.value })}
                          />
                        </label>
                      </div>
                    );
                  })}

                  <button className="primary">Save opening hours</button>
                </form>
              )}
            </div>
          </div>
        )}
      </Section>

      <Section title="Locations">
        <SimpleTable
          rows={data}
          columns={['banner_image_url', 'name', 'type', 'compound_name', 'delivery_fee', 'is_active']}
          format={{
            banner_image_url: (value, row) => value ? <img className="tableImageThumb locationTableBannerThumb" src={value} alt={row.name} /> : '-',
            type: (value) => humanize(value),
            is_active: (value) => value ? 'Active' : 'Inactive'
          }}
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
