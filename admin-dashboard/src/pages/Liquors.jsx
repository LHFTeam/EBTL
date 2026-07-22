import { useEffect, useMemo, useState } from 'react';
import { api } from '../api/client.js';
import { Loading, Message, Section, SimpleTable } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { toBool } from '../utils/format.js';

const blankLiquor = {
  name: '',
  display_order: 0,
  is_active: true
};

const MAX_IMAGE_BYTES = 3 * 1024 * 1024;

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

export default function Liquors() {
  const { data, loading, error, reload } = useLoad(() => api('/api/liquors'));
  const liquors = data?.liquors || [];

  const [form, setForm] = useState(blankLiquor);
  const [createImageFile, setCreateImageFile] = useState(null);
  const [editing, setEditing] = useState(null);
  const [editForm, setEditForm] = useState(blankLiquor);
  const [editImageFile, setEditImageFile] = useState(null);
  const [msg, setMsg] = useState('');
  const [msgType, setMsgType] = useState('ok');

  const selectedLiquor = useMemo(
    () => liquors.find((liquor) => liquor.id === editing) || null,
    [liquors, editing]
  );

  useEffect(() => {
    if (!selectedLiquor) return;

    setEditForm({
      name: selectedLiquor.name || '',
      display_order: selectedLiquor.display_order ?? 0,
      is_active: !!selectedLiquor.is_active
    });
    setEditImageFile(null);
  }, [selectedLiquor]);

  function showMessage(text, type = 'ok') {
    setMsg(text);
    setMsgType(type);
  }

  function chooseLiquorImage(file, setter) {
    if (!file) {
      setter(null);
      return;
    }

    if (!isWebpFile(file)) {
      setter(null);
      showMessage('Please choose a .webp image file.', 'error');
      return;
    }

    if (file.size > MAX_IMAGE_BYTES) {
      setter(null);
      showMessage('Image is too large. Maximum size is 3 MB.', 'error');
      return;
    }

    setter(file);
  }

  async function uploadLiquorImage(liquorId, file) {
    await api(`/api/liquors/${liquorId}/image`, {
      method: 'POST',
      body: JSON.stringify(await imageUploadPayload(file))
    });
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
    setMsg('');

    try {
      const created = await api('/api/liquors', {
        method: 'POST',
        body: JSON.stringify({
          name: form.name,
          display_order: form.display_order,
          is_active: toBool(form.is_active)
        })
      });

      if (createImageFile && created?.id) {
        try {
          await uploadLiquorImage(created.id, createImageFile);
        } catch (imageErr) {
          setForm(blankLiquor);
          setCreateImageFile(null);
          showMessage(`Liquor saved, but image upload failed: ${imageErr.message || 'Upload failed'}`, 'error');
          await reload();
          return;
        }
      }

      setForm(blankLiquor);
      setCreateImageFile(null);
      showMessage(createImageFile ? 'Liquor and image saved.' : 'Liquor saved.');
      await reload();
    } catch (err) {
      showMessage(err.message || 'Request failed', 'error');
    }
  }

  async function save(e) {
    e.preventDefault();

    await runAction(async () => {
      await api(`/api/liquors/${editing}`, {
        method: 'PATCH',
        body: JSON.stringify({
          name: editForm.name,
          display_order: editForm.display_order,
          is_active: toBool(editForm.is_active)
        })
      });
    }, 'Liquor updated.');
  }

  async function saveEditedImage(e) {
    e.preventDefault();

    if (!editImageFile) {
      showMessage('Choose a .webp image first.', 'error');
      return;
    }

    await runAction(async () => {
      await uploadLiquorImage(editing, editImageFile);
      setEditImageFile(null);
    }, 'Liquor image uploaded.');
  }

  async function clearEditedImage() {
    const name = selectedLiquor?.name || 'this liquor';
    if (!window.confirm(`Remove the image for ${name}?`)) return;

    await runAction(async () => {
      await api(`/api/liquors/${editing}/image`, { method: 'DELETE' });
      setEditImageFile(null);
    }, 'Liquor image removed.');
  }

  async function setLiquorActive(liquor, isActive) {
    if (!isActive && !window.confirm(`Deactivate ${liquor.name}? It will be hidden from the customer app.`)) return;

    await runAction(async () => {
      if (isActive) {
        await api(`/api/liquors/${liquor.id}`, {
          method: 'PATCH',
          body: JSON.stringify({ is_active: true })
        });
      } else {
        await api(`/api/liquors/${liquor.id}`, { method: 'DELETE' });
      }
    }, isActive ? 'Liquor activated.' : 'Liquor deactivated.');
  }

  if (loading || error) return <Loading error={error} />;

  return <div className="grid">
    <Section title="Add Liquor Type">
      <form className="miniForm formGrid" onSubmit={add}>
        <input
          required
          placeholder="Liquor name, eg Gin"
          value={form.name}
          onChange={(e) => setForm({ ...form, name: e.target.value })}
        />

        <input
          type="number"
          step="1"
          placeholder="Display order"
          value={form.display_order}
          onChange={(e) => setForm({ ...form, display_order: e.target.value })}
        />

        <label className="checkboxField">
          <input
            type="checkbox"
            checked={toBool(form.is_active)}
            onChange={(e) => setForm({ ...form, is_active: e.target.checked })}
          />
          <span>Active in app</span>
        </label>

        <div className="full imageUploadPanel">
          <div>
            <b>Liquor image</b>
            <p className="muted smallText noPad">
              Upload a square WebP image. It will be stored in the Supabase <code>liquors</code> bucket after the liquor type is created.
            </p>
          </div>

          <label className="fileButton">
            <input
              type="file"
              accept="image/webp,.webp"
              onChange={(e) => chooseLiquorImage(e.target.files?.[0], setCreateImageFile)}
            />
            <span>{createImageFile ? 'Change WebP image' : 'Choose WebP image'}</span>
          </label>

          {createImageFile && (
            <div className="selectedFile">
              Selected: {createImageFile.name} · {fileSizeLabel(createImageFile.size)}
            </div>
          )}
        </div>

        <button className="primary">Save liquor</button>
      </form>
    </Section>

    <Message text={msg} type={msgType} />

    {selectedLiquor && (
      <Section
        title={`Edit Liquor: ${selectedLiquor.name}`}
        action={<button onClick={() => setEditing(null)}>Close editor</button>}
      >
        <div className="imageUploadPanel editorImagePanel">
          <div className="imagePreviewBox">
            {selectedLiquor.image_url ? (
              <img className="cocktailImagePreview" src={selectedLiquor.image_url} alt={selectedLiquor.name} />
            ) : (
              <div className="imagePlaceholder">No image</div>
            )}
          </div>

          <form className="imageUploadControls" onSubmit={saveEditedImage}>
            <b>Liquor image</b>
            <p className="muted smallText noPad">
              Upload a replacement square WebP image. It will be saved to Supabase Storage and linked to this liquor.
            </p>

            <label className="fileButton">
              <input
                type="file"
                accept="image/webp,.webp"
                onChange={(e) => chooseLiquorImage(e.target.files?.[0], setEditImageFile)}
              />
              <span>{editImageFile ? 'Change WebP image' : 'Choose WebP image'}</span>
            </label>

            {editImageFile && (
              <div className="selectedFile">
                Selected: {editImageFile.name} · {fileSizeLabel(editImageFile.size)}
              </div>
            )}

            <div className="inlineActions">
              <button className="primary" disabled={!editImageFile}>Upload image</button>
              {selectedLiquor.image_url && (
                <button type="button" className="danger" onClick={clearEditedImage}>
                  Remove image
                </button>
              )}
            </div>
          </form>
        </div>

        <form className="miniForm formGrid" onSubmit={save}>
          <input
            required
            value={editForm.name || ''}
            onChange={(e) => setEditForm({ ...editForm, name: e.target.value })}
          />

          <input
            type="number"
            step="1"
            value={editForm.display_order ?? 0}
            onChange={(e) => setEditForm({ ...editForm, display_order: e.target.value })}
          />

          <label className="checkboxField">
            <input
              type="checkbox"
              checked={toBool(editForm.is_active)}
              onChange={(e) => setEditForm({ ...editForm, is_active: e.target.checked })}
            />
            <span>Active in app</span>
          </label>

          <button className="primary">Save liquor details</button>
        </form>
      </Section>
    )}

    <Section title="Liquor Types">
      <SimpleTable
        rows={liquors}
        columns={['image_url', 'name', 'display_order', 'is_active']}
        format={{
          image_url: (value, row) => value ? <img className="tableImageThumb" src={value} alt={row.name} /> : '-',
          is_active: (value) => value ? 'Active' : 'Inactive'
        }}
        actions={(row) => (
          <div className="inlineActions">
            <button type="button" onClick={() => setEditing(row.id)}>Edit</button>
            <button
              type="button"
              className={row.is_active ? 'danger' : ''}
              onClick={() => setLiquorActive(row, !row.is_active)}
            >
              {row.is_active ? 'Deactivate' : 'Activate'}
            </button>
          </div>
        )}
      />
    </Section>
  </div>;
}
