import { useEffect, useRef, useState } from 'react';
import { api } from '../api/client.js';
import { Loading, Message, Section } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { slugify, toBool } from '../utils/format.js';

const blankCategory = {
  name: '',
  slug: '',
  sort_order: 0,
  is_active: true
};

const blankProductTag = {
  name: '',
  color_hex: '#1F6F68',
  display_order: 0,
  is_active: true
};

const MAX_IMAGE_BYTES = 3 * 1024 * 1024;

function nullableText(value) {
  const text = String(value ?? '').trim();
  return text ? text : null;
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

function ShopImagePreview({ src, label = 'No image' }) {
  return <div className="imagePreviewBox shopImagePreviewBox">
    {src ? <img className="cocktailImagePreview" src={src} alt="" /> : <span className="imagePlaceholder">{label}</span>}
  </div>;
}

export default function Shop() {
  const { data, loading, error, reload } = useLoad(() => api('/api/shop'));
  const messageRef = useRef(null);
  const [msg, setMsg] = useState('');
  const [msgType, setMsgType] = useState('ok');
  const [bannerFile, setBannerFile] = useState(null);
  const [newCategory, setNewCategory] = useState(blankCategory);
  const [categoryEdits, setCategoryEdits] = useState({});
  const [categoryImageFiles, setCategoryImageFiles] = useState({});
  const [newTag, setNewTag] = useState(blankProductTag);
  const [tagEdits, setTagEdits] = useState({});

  const settings = data?.settings || {};
  const categories = data?.categories || [];
  const productTags = data?.productTags || [];

  useEffect(() => {
    setCategoryEdits(Object.fromEntries(categories.map((category) => [category.id, {
      name: category.name || '',
      slug: category.slug || '',
      sort_order: category.sort_order ?? 0,
      is_active: !!category.is_active
    }])));
  }, [categories]);

  useEffect(() => {
    setTagEdits(Object.fromEntries(productTags.map((tag) => [tag.id, {
      name: tag.name || '',
      color_hex: tag.color_hex || '#1F6F68',
      display_order: tag.display_order ?? 0,
      is_active: !!tag.is_active
    }])));
  }, [productTags]);

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

  async function uploadBanner(e) {
    e.preventDefault();

    if (!bannerFile) {
      showMessage('Choose a .webp banner image first.', 'error');
      return;
    }

    await runAction(async () => {
      await api('/api/shop/banner-image', {
        method: 'POST',
        body: JSON.stringify(await imageUploadPayload(bannerFile))
      });
      setBannerFile(null);
    }, 'Shop banner image uploaded.');
  }

  async function clearBanner() {
    if (!window.confirm('Remove the shop banner image?')) return;

    await runAction(async () => {
      await api('/api/shop/banner-image', { method: 'DELETE' });
      setBannerFile(null);
    }, 'Shop banner image removed.');
  }

  async function addCategory(e) {
    e.preventDefault();

    await runAction(async () => {
      const created = await api('/api/shop/categories', {
        method: 'POST',
        body: JSON.stringify({
          name: newCategory.name,
          slug: nullableText(newCategory.slug),
          sort_order: newCategory.sort_order,
          is_active: toBool(newCategory.is_active)
        })
      });

      setNewCategory(blankCategory);

      return created;
    }, 'Category added.');
  }

  function patchCategoryEdit(categoryId, patch) {
    setCategoryEdits((current) => ({
      ...current,
      [categoryId]: {
        ...(current[categoryId] || {}),
        ...patch
      }
    }));
  }

  async function saveCategory(categoryId) {
    const draft = categoryEdits[categoryId] || {};

    await runAction(async () => {
      await api(`/api/shop/categories/${categoryId}`, {
        method: 'PATCH',
        body: JSON.stringify({
          name: draft.name,
          slug: nullableText(draft.slug),
          sort_order: draft.sort_order,
          is_active: toBool(draft.is_active)
        })
      });
    }, 'Category updated.');
  }

  async function setCategoryActive(categoryId, isActive) {
    const category = categories.find((row) => row.id === categoryId);

    if (!isActive && !window.confirm(`Deactivate ${category?.name || 'this category'}? It will be hidden from the shop category row.`)) return;

    await runAction(async () => {
      if (isActive) {
        await api(`/api/shop/categories/${categoryId}`, {
          method: 'PATCH',
          body: JSON.stringify({ is_active: true })
        });
      } else {
        await api(`/api/shop/categories/${categoryId}`, { method: 'DELETE' });
      }
    }, isActive ? 'Category activated.' : 'Category deactivated.');
  }

  async function uploadCategoryImage(categoryId) {
    const file = categoryImageFiles[categoryId];

    if (!file) {
      showMessage('Choose a .webp category image first.', 'error');
      return;
    }

    await runAction(async () => {
      await api(`/api/shop/categories/${categoryId}/image`, {
        method: 'POST',
        body: JSON.stringify(await imageUploadPayload(file))
      });
      setCategoryImageFiles((current) => ({ ...current, [categoryId]: null }));
    }, 'Category image uploaded.');
  }

  async function clearCategoryImage(categoryId) {
    const category = categories.find((row) => row.id === categoryId);
    if (!window.confirm(`Remove the image for ${category?.name || 'this category'}?`)) return;

    await runAction(async () => {
      await api(`/api/shop/categories/${categoryId}/image`, { method: 'DELETE' });
      setCategoryImageFiles((current) => ({ ...current, [categoryId]: null }));
    }, 'Category image removed.');
  }

  async function addProductTag(e) {
    e.preventDefault();

    await runAction(async () => {
      await api('/api/shop/product-tags', {
        method: 'POST',
        body: JSON.stringify({
          name: newTag.name,
          color_hex: newTag.color_hex,
          display_order: newTag.display_order,
          is_active: toBool(newTag.is_active)
        })
      });

      setNewTag(blankProductTag);
    }, 'Product tag added.');
  }

  function patchTagEdit(tagId, patch) {
    setTagEdits((current) => ({
      ...current,
      [tagId]: {
        ...(current[tagId] || {}),
        ...patch
      }
    }));
  }

  async function saveProductTag(tagId) {
    const draft = tagEdits[tagId] || {};

    await runAction(async () => {
      await api(`/api/shop/product-tags/${tagId}`, {
        method: 'PATCH',
        body: JSON.stringify({
          name: draft.name,
          color_hex: draft.color_hex,
          display_order: draft.display_order,
          is_active: toBool(draft.is_active)
        })
      });
    }, 'Product tag updated.');
  }

  async function setProductTagActive(tagId, isActive) {
    const tag = productTags.find((row) => row.id === tagId);

    if (!isActive && !window.confirm(`Deactivate tag "${tag?.name || 'this tag'}"? Existing products that use it will keep the text value, but it will not be selectable for new edits.`)) return;

    await runAction(async () => {
      if (isActive) {
        await api(`/api/shop/product-tags/${tagId}`, {
          method: 'PATCH',
          body: JSON.stringify({ is_active: true })
        });
      } else {
        await api(`/api/shop/product-tags/${tagId}`, { method: 'DELETE' });
      }
    }, isActive ? 'Product tag activated.' : 'Product tag deactivated.');
  }

  if (loading || error) return <Loading error={error} />;

  return <div className="grid">
    <div ref={messageRef} className="messageAnchor"><Message text={msg} type={msgType} /></div>

    <Section title="Shop Banner">
      <div className="subPanel noTopMargin">
        <div className="shopAssetRow">
          <ShopImagePreview src={settings.banner_image_url} label="No banner" />
          <div className="imageUploadControls">
            <b>Global shop banner image</b>
            <p className="muted smallText noPad">
              Upload a wide WebP image. The mobile app owns the static copy: “Beach day essentials?”, “We’ve got you.”, and “Shop Essentials”.
            </p>
            <form className="miniForm inlineShopUpload" onSubmit={uploadBanner}>
              <label className="fileButton">
                <input
                  type="file"
                  accept="image/webp,.webp"
                  onChange={(e) => chooseWebpImage(e.target.files?.[0], setBannerFile)}
                />
                <span>{bannerFile ? 'Change WebP banner' : 'Choose WebP banner'}</span>
              </label>
              <button className="primary" disabled={!bannerFile}>Upload banner</button>
              {settings.banner_image_url && <button type="button" onClick={clearBanner}>Remove</button>}
            </form>
            {bannerFile && <div className="selectedFile">Selected: {bannerFile.name} · {fileSizeLabel(bannerFile.size)}</div>}
          </div>
        </div>
      </div>
    </Section>

    <Section title="Categories">
      <form className="miniForm formGrid" onSubmit={addCategory}>
        <input
          required
          placeholder="Category name, eg Essentials"
          value={newCategory.name}
          onChange={(e) => setNewCategory({ ...newCategory, name: e.target.value, slug: newCategory.slug || slugify(e.target.value) })}
        />
        <input
          placeholder="slug"
          value={newCategory.slug}
          onChange={(e) => setNewCategory({ ...newCategory, slug: slugify(e.target.value) })}
        />
        <input
          type="number"
          step="1"
          placeholder="Sort order"
          value={newCategory.sort_order}
          onChange={(e) => setNewCategory({ ...newCategory, sort_order: e.target.value })}
        />
        <label className="checkboxField">
          <input
            type="checkbox"
            checked={toBool(newCategory.is_active)}
            onChange={(e) => setNewCategory({ ...newCategory, is_active: e.target.checked })}
          />
          <span>Active</span>
        </label>
        <button className="primary">Add category</button>
      </form>

      <div className="shopAdminList">
        {categories.length ? categories.map((category) => {
          const draft = categoryEdits[category.id] || {};
          const selectedFile = categoryImageFiles[category.id];

          return <div className="shopCategoryRow" key={category.id}>
            <ShopImagePreview src={category.image_url} label="No category image" />

            <div className="shopCategoryFields">
              <input
                value={draft.name || ''}
                placeholder="Category name"
                onChange={(e) => patchCategoryEdit(category.id, { name: e.target.value })}
              />
              <input
                value={draft.slug || ''}
                placeholder="slug"
                onChange={(e) => patchCategoryEdit(category.id, { slug: slugify(e.target.value) })}
              />
              <input
                type="number"
                value={draft.sort_order ?? 0}
                onChange={(e) => patchCategoryEdit(category.id, { sort_order: e.target.value })}
              />
              <label className="checkboxField">
                <input
                  type="checkbox"
                  checked={toBool(draft.is_active)}
                  onChange={(e) => patchCategoryEdit(category.id, { is_active: e.target.checked })}
                />
                <span>Active</span>
              </label>
              <span className="selectedFile">{category.active_product_count || 0} active products</span>
            </div>

            <div className="shopCategoryActions">
              <button className="primary" type="button" onClick={() => saveCategory(category.id)}>Save</button>
              <button type="button" onClick={() => setCategoryActive(category.id, !category.is_active)}>
                {category.is_active ? 'Deactivate' : 'Activate'}
              </button>

              <label className="fileButton">
                <input
                  type="file"
                  accept="image/webp,.webp"
                  onChange={(e) => chooseWebpImage(e.target.files?.[0], (file) => setCategoryImageFiles((current) => ({ ...current, [category.id]: file })))}
                />
                <span>{selectedFile ? 'Change image' : 'Choose image'}</span>
              </label>
              <button type="button" disabled={!selectedFile} onClick={() => uploadCategoryImage(category.id)}>Upload image</button>
              {category.image_url && <button type="button" onClick={() => clearCategoryImage(category.id)}>Remove image</button>}
              {selectedFile && <span className="selectedFile">{selectedFile.name} · {fileSizeLabel(selectedFile.size)}</span>}
            </div>
          </div>;
        }) : <div className="empty">No categories yet.</div>}
      </div>
    </Section>

    <Section title="Product Tags">
      <form className="miniForm tagAdminForm" onSubmit={addProductTag}>
        <input
          required
          maxLength="40"
          placeholder="Tag name, e.g. Best Seller"
          value={newTag.name}
          onChange={(e) => setNewTag({ ...newTag, name: e.target.value })}
        />
        <input
          required
          type="color"
          value={newTag.color_hex}
          onChange={(e) => setNewTag({ ...newTag, color_hex: e.target.value })}
        />
        <input
          type="number"
          placeholder="Display order"
          value={newTag.display_order}
          onChange={(e) => setNewTag({ ...newTag, display_order: e.target.value })}
        />
        <label className="checkboxField">
          <input
            type="checkbox"
            checked={toBool(newTag.is_active)}
            onChange={(e) => setNewTag({ ...newTag, is_active: e.target.checked })}
          />
          <span>Active</span>
        </label>
        <button className="primary">Add tag</button>
      </form>

      <div className="tagAdminList">
        {productTags.length ? productTags.map((tag) => {
          const draft = tagEdits[tag.id] || {};

          return <div className="tagAdminRow" key={tag.id}>
            <input
              value={draft.name || ''}
              maxLength="40"
              onChange={(e) => patchTagEdit(tag.id, { name: e.target.value })}
            />
            <input
              type="color"
              value={draft.color_hex || '#1F6F68'}
              onChange={(e) => patchTagEdit(tag.id, { color_hex: e.target.value })}
            />
            <input
              type="number"
              value={draft.display_order ?? 0}
              onChange={(e) => patchTagEdit(tag.id, { display_order: e.target.value })}
            />
            <label className="checkboxField">
              <input
                type="checkbox"
                checked={toBool(draft.is_active)}
                onChange={(e) => patchTagEdit(tag.id, { is_active: e.target.checked })}
              />
              <span>Active</span>
            </label>
            <span className="tagChip" style={{ '--tag-color': draft.color_hex || '#1F6F68' }}>{draft.name || 'Tag preview'}</span>
            <div className="inlineActions">
              <button type="button" className="primary" onClick={() => saveProductTag(tag.id)}>Save</button>
              <button type="button" onClick={() => setProductTagActive(tag.id, !tag.is_active)}>
                {tag.is_active ? 'Deactivate' : 'Activate'}
              </button>
            </div>
          </div>;
        }) : <div className="empty">No product tags yet.</div>}
      </div>
    </Section>
  </div>;
}
