import { useEffect, useRef, useState } from 'react';
import { api } from '../api/client.js';
import { Loading, Message, Section } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { toBool } from '../utils/format.js';

const MAX_IMAGE_BYTES = 3 * 1024 * 1024;

const HEADLINE_MAX = 80;
const BODY_MAX = 200;

// Matches the check constraint on home_hero_settings and the app's own clamp.
const ROTATION_MIN_SECONDS = 2;
const ROTATION_MAX_SECONDS = 60;
const ROTATION_DEFAULT_SECONDS = 5;

// The destinations the customer app can resolve a banner tap to. `needsValue`
// destinations carry a second picker (which cocktail, which category); the
// stored deep link is `<kind>/<value>`. Keep in step with the validation in
// server/routes/bannerRoutes.js and with HomeHeroBanner.link in the app.
const deepLinkTargets = [
  { value: '', label: 'No link (not tappable)' },
  { value: 'finder', label: 'Cocktail Finder' },
  { value: 'explore', label: 'Explore tab' },
  { value: 'cart', label: 'Cart' },
  { value: 'orders', label: 'Order history' },
  { value: 'cocktail', label: 'A cocktail…', needsValue: 'cocktails' },
  { value: 'category', label: 'A shop category…', needsValue: 'categories' }
];

const blankBanner = {
  headline: '',
  body: '',
  deep_link_target: '',
  deep_link_value: '',
  display_order: 0,
  is_active: true
};

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

function targetFor(value) {
  return deepLinkTargets.find((target) => target.value === value) || deepLinkTargets[0];
}

// `cocktail/mojito` → { deep_link_target: 'cocktail', deep_link_value: 'mojito' }.
function splitDeepLink(deepLink) {
  const text = String(deepLink || '').trim();
  if (!text) return { deep_link_target: '', deep_link_value: '' };

  const separator = text.indexOf('/');
  if (separator === -1) return { deep_link_target: text, deep_link_value: '' };

  return {
    deep_link_target: text.slice(0, separator),
    deep_link_value: text.slice(separator + 1)
  };
}

function joinDeepLink(draft) {
  const target = targetFor(draft.deep_link_target);
  if (!target.value) return null;
  if (!target.needsValue) return target.value;

  const value = String(draft.deep_link_value || '').trim();
  return value ? `${target.value}/${value}` : null;
}

function BannerImagePreview({ src, label = 'No image' }) {
  return <div className="imagePreviewBox shopImagePreviewBox">
    {src ? <img className="cocktailImagePreview" src={src} alt="" /> : <span className="imagePlaceholder">{label}</span>}
  </div>;
}

// The destination select plus its dependent picker, shared by the add form and
// each banner row.
function DeepLinkFields({ draft, options, onPatch }) {
  const target = targetFor(draft.deep_link_target);
  const choices = target.needsValue ? (options[target.needsValue] || []) : [];

  return <>
    <select
      value={draft.deep_link_target || ''}
      onChange={(e) => onPatch({ deep_link_target: e.target.value, deep_link_value: '' })}
    >
      {deepLinkTargets.map((option) => <option key={option.value || 'none'} value={option.value}>{option.label}</option>)}
    </select>

    {target.needsValue && <select
      value={draft.deep_link_value || ''}
      onChange={(e) => onPatch({ deep_link_value: e.target.value })}
    >
      <option value="">{target.value === 'cocktail' ? 'Choose a cocktail' : 'Choose a category'}</option>
      {choices.map((choice) => {
        const value = target.value === 'cocktail' ? choice.slug : choice.id;
        return <option key={value} value={value}>{choice.name}</option>;
      })}
    </select>}
  </>;
}

export default function Banners() {
  const { data, loading, error, reload } = useLoad(() => api('/api/banners'));
  const messageRef = useRef(null);
  const [msg, setMsg] = useState('');
  const [msgType, setMsgType] = useState('ok');
  const [shopBannerFile, setShopBannerFile] = useState(null);
  const [newBanner, setNewBanner] = useState(blankBanner);
  const [newBannerFile, setNewBannerFile] = useState(null);
  const [bannerEdits, setBannerEdits] = useState({});
  const [bannerImageFiles, setBannerImageFiles] = useState({});
  const [rotationSeconds, setRotationSeconds] = useState(ROTATION_DEFAULT_SECONDS);

  const heroBanners = data?.heroBanners || [];
  const shopSettings = data?.shopSettings || {};
  const deepLinkOptions = data?.deepLinkOptions || { cocktails: [], categories: [] };

  // Keyed off the payload rather than the derived array: `data?.heroBanners ||
  // []` is a fresh array on every render while the load is in flight.
  useEffect(() => {
    setBannerEdits(Object.fromEntries((data?.heroBanners || []).map((banner) => [banner.id, {
      headline: banner.headline || '',
      body: banner.body || '',
      display_order: banner.display_order ?? 0,
      is_active: !!banner.is_active,
      ...splitDeepLink(banner.deep_link)
    }])));
  }, [data]);

  useEffect(() => {
    setRotationSeconds(data?.heroSettings?.rotation_seconds ?? ROTATION_DEFAULT_SECONDS);
  }, [data]);

  function showMessage(text, type = 'ok') {
    setMsg(text);
    setMsgType(type);
    window.requestAnimationFrame(() => {
      messageRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  }

  function chooseWebpImage(file, setter) {
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

  async function saveRotation(e) {
    e.preventDefault();

    await runAction(async () => {
      await api('/api/banners/hero-settings', {
        method: 'PATCH',
        body: JSON.stringify({ rotation_seconds: rotationSeconds })
      });
    }, 'Rotation speed saved.');
  }

  async function addHeroBanner(e) {
    e.preventDefault();

    if (!newBannerFile) {
      showMessage('Choose a .webp banner image first.', 'error');
      return;
    }

    await runAction(async () => {
      await api('/api/banners/hero', {
        method: 'POST',
        body: JSON.stringify({
          image: await imageUploadPayload(newBannerFile),
          headline: newBanner.headline,
          body: newBanner.body,
          deep_link: joinDeepLink(newBanner),
          display_order: newBanner.display_order,
          is_active: toBool(newBanner.is_active)
        })
      });

      setNewBanner(blankBanner);
      setNewBannerFile(null);
    }, 'Hero banner added.');
  }

  function patchBannerEdit(bannerId, patch) {
    setBannerEdits((current) => ({
      ...current,
      [bannerId]: {
        ...(current[bannerId] || {}),
        ...patch
      }
    }));
  }

  async function saveHeroBanner(bannerId) {
    const draft = bannerEdits[bannerId] || {};

    await runAction(async () => {
      await api(`/api/banners/hero/${bannerId}`, {
        method: 'PATCH',
        body: JSON.stringify({
          headline: draft.headline ?? '',
          body: draft.body ?? '',
          deep_link: joinDeepLink(draft),
          // A cleared number input must leave the stored order alone rather
          // than coercing to 0 — JSON.stringify drops the undefined key.
          display_order: draft.display_order === '' ? undefined : draft.display_order,
          is_active: toBool(draft.is_active)
        })
      });
    }, 'Hero banner updated.');
  }

  async function setHeroBannerActive(bannerId, isActive) {
    await runAction(async () => {
      await api(`/api/banners/hero/${bannerId}`, {
        method: 'PATCH',
        body: JSON.stringify({ is_active: isActive })
      });
    }, isActive ? 'Hero banner shown.' : 'Hero banner hidden.');
  }

  async function uploadHeroBannerImage(bannerId) {
    const file = bannerImageFiles[bannerId];

    if (!file) {
      showMessage('Choose a .webp banner image first.', 'error');
      return;
    }

    await runAction(async () => {
      await api(`/api/banners/hero/${bannerId}/image`, {
        method: 'POST',
        body: JSON.stringify(await imageUploadPayload(file))
      });
      setBannerImageFiles((current) => ({ ...current, [bannerId]: null }));
    }, 'Hero banner image replaced.');
  }

  async function deleteHeroBanner(bannerId) {
    if (!window.confirm('Delete this hero banner? Its image is removed too and this cannot be undone.')) return;

    await runAction(async () => {
      await api(`/api/banners/hero/${bannerId}`, { method: 'DELETE' });
      setBannerImageFiles((current) => ({ ...current, [bannerId]: null }));
    }, 'Hero banner deleted.');
  }

  async function uploadShopBanner(e) {
    e.preventDefault();

    if (!shopBannerFile) {
      showMessage('Choose a .webp banner image first.', 'error');
      return;
    }

    await runAction(async () => {
      await api('/api/banners/shop-image', {
        method: 'POST',
        body: JSON.stringify(await imageUploadPayload(shopBannerFile))
      });
      setShopBannerFile(null);
    }, 'Shop banner image uploaded.');
  }

  async function clearShopBanner() {
    if (!window.confirm('Remove the shop banner image?')) return;

    await runAction(async () => {
      await api('/api/banners/shop-image', { method: 'DELETE' });
      setShopBannerFile(null);
    }, 'Shop banner image removed.');
  }

  if (loading || error) return <Loading error={error} onRetry={reload} />;

  return <div className="grid">
    <div ref={messageRef} className="messageAnchor"><Message text={msg} type={msgType} /></div>

    <Section title="Home Hero Banner">
      <p className="muted smallText noPad">
        The carousel at the top of the app's Home tab. Slides show in ascending order. Only the image and the
        order are required — a slide with no headline or body is just the image, and one with no link is not
        tappable. With no active slides the app falls back to its three built-in ones.
      </p>

      <div className="subPanel noTopMargin">
        <form className="miniForm inlineShopUpload" onSubmit={saveRotation}>
          <b>Rotation speed</b>
          <input
            required
            type="number"
            step="1"
            min={ROTATION_MIN_SECONDS}
            max={ROTATION_MAX_SECONDS}
            className="rotationInput"
            value={rotationSeconds}
            onChange={(e) => setRotationSeconds(e.target.value)}
          />
          <span className="muted smallText noPad">
            seconds each slide is shown before the carousel moves on ({ROTATION_MIN_SECONDS}–{ROTATION_MAX_SECONDS}, default {ROTATION_DEFAULT_SECONDS}).
            Swiping pauses it; it resumes a slide-length after the customer lets go.
          </span>
          <button className="primary">Save speed</button>
        </form>
      </div>

      <form className="miniForm bannerAddForm" onSubmit={addHeroBanner}>
        <label className="fileButton">
          <input
            type="file"
            accept="image/webp,.webp"
            onChange={(e) => chooseWebpImage(e.target.files?.[0], setNewBannerFile)}
          />
          <span>{newBannerFile ? 'Change WebP image' : 'Choose WebP image *'}</span>
        </label>
        <input
          maxLength={HEADLINE_MAX}
          placeholder="Headline (optional)"
          value={newBanner.headline}
          onChange={(e) => setNewBanner({ ...newBanner, headline: e.target.value })}
        />
        <input
          maxLength={BODY_MAX}
          placeholder="Body (optional)"
          value={newBanner.body}
          onChange={(e) => setNewBanner({ ...newBanner, body: e.target.value })}
        />
        <DeepLinkFields
          draft={newBanner}
          options={deepLinkOptions}
          onPatch={(patch) => setNewBanner({ ...newBanner, ...patch })}
        />
        <input
          required
          type="number"
          step="1"
          min="0"
          placeholder="Order *"
          value={newBanner.display_order}
          onChange={(e) => setNewBanner({ ...newBanner, display_order: e.target.value })}
        />
        <label className="checkboxField">
          <input
            type="checkbox"
            checked={toBool(newBanner.is_active)}
            onChange={(e) => setNewBanner({ ...newBanner, is_active: e.target.checked })}
          />
          <span>Active</span>
        </label>
        <button className="primary" disabled={!newBannerFile}>Add banner</button>
      </form>
      {newBannerFile && <div className="selectedFile">Selected: {newBannerFile.name} · {fileSizeLabel(newBannerFile.size)}</div>}

      <div className="shopAdminList">
        {heroBanners.length ? heroBanners.map((banner) => {
          const draft = bannerEdits[banner.id] || {};
          const selectedFile = bannerImageFiles[banner.id];

          return <div className="shopCategoryRow" key={banner.id}>
            <BannerImagePreview src={banner.image_url} label="No banner image" />

            <div className="bannerFields">
              <input
                maxLength={HEADLINE_MAX}
                value={draft.headline || ''}
                placeholder="Headline (optional)"
                onChange={(e) => patchBannerEdit(banner.id, { headline: e.target.value })}
              />
              <input
                maxLength={BODY_MAX}
                value={draft.body || ''}
                placeholder="Body (optional)"
                onChange={(e) => patchBannerEdit(banner.id, { body: e.target.value })}
              />
              <DeepLinkFields
                draft={draft}
                options={deepLinkOptions}
                onPatch={(patch) => patchBannerEdit(banner.id, patch)}
              />
              <input
                type="number"
                min="0"
                value={draft.display_order ?? 0}
                onChange={(e) => patchBannerEdit(banner.id, { display_order: e.target.value })}
              />
              <label className="checkboxField">
                <input
                  type="checkbox"
                  checked={toBool(draft.is_active)}
                  onChange={(e) => patchBannerEdit(banner.id, { is_active: e.target.checked })}
                />
                <span>Active</span>
              </label>
            </div>

            <div className="shopCategoryActions">
              <button className="primary" type="button" onClick={() => saveHeroBanner(banner.id)}>Save</button>
              <button type="button" onClick={() => setHeroBannerActive(banner.id, !banner.is_active)}>
                {banner.is_active ? 'Hide' : 'Show'}
              </button>

              <label className="fileButton">
                <input
                  type="file"
                  accept="image/webp,.webp"
                  onChange={(e) => chooseWebpImage(e.target.files?.[0], (file) => setBannerImageFiles((current) => ({ ...current, [banner.id]: file })))}
                />
                <span>{selectedFile ? 'Change image' : 'Replace image'}</span>
              </label>
              <button type="button" disabled={!selectedFile} onClick={() => uploadHeroBannerImage(banner.id)}>Upload image</button>
              <button type="button" className="danger" onClick={() => deleteHeroBanner(banner.id)}>Delete</button>
              {selectedFile && <span className="selectedFile">{selectedFile.name} · {fileSizeLabel(selectedFile.size)}</span>}
            </div>
          </div>;
        }) : <div className="empty">No hero banners yet — the app is showing its three built-in slides.</div>}
      </div>
    </Section>

    <Section title="Shop Banner">
      <div className="subPanel noTopMargin">
        <div className="shopAssetRow">
          <BannerImagePreview src={shopSettings.banner_image_url} label="No banner" />
          <div className="imageUploadControls">
            <b>Global shop banner image</b>
            <p className="muted smallText noPad">
              Upload a wide WebP image. The mobile app owns the static copy: “Beach day essentials?”, “We’ve got you.”, and “Shop Essentials”.
            </p>
            <form className="miniForm inlineShopUpload" onSubmit={uploadShopBanner}>
              <label className="fileButton">
                <input
                  type="file"
                  accept="image/webp,.webp"
                  onChange={(e) => chooseWebpImage(e.target.files?.[0], setShopBannerFile)}
                />
                <span>{shopBannerFile ? 'Change WebP banner' : 'Choose WebP banner'}</span>
              </label>
              <button className="primary" disabled={!shopBannerFile}>Upload banner</button>
              {shopSettings.banner_image_url && <button type="button" onClick={clearShopBanner}>Remove</button>}
            </form>
            {shopBannerFile && <div className="selectedFile">Selected: {shopBannerFile.name} · {fileSizeLabel(shopBannerFile.size)}</div>}
          </div>
        </div>
      </div>
    </Section>
  </div>;
}
