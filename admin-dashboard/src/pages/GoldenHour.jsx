import { useEffect, useRef, useState } from 'react';
import { api } from '../api/client.js';
import { Loading, Message, Section } from '../components/ui.jsx';
import { useLoad } from '../hooks/useLoad.js';
import { toBool } from '../utils/format.js';

const MAX_IMAGE_BYTES = 3 * 1024 * 1024;

const TITLE_MAX = 60;
const SUBTITLE_MAX = 160;
const CAPTION_MAX = 120;
const PILL_LABEL_MAX = 24;

// Mirrors the fallback in server/lib/goldenHour.js. Only used before the first
// payload lands, so the pill previews have something to draw.
const FALLBACK_SCHEME = { key: 'sand', label: 'Sand', background: '#F3E5D0', foreground: '#0E2238' };

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

function draftFromMode(mode) {
  return {
    is_active: !!mode.is_active,
    start_time: mode.start_time || '',
    end_time: mode.end_time || '',
    title: mode.title || '',
    subtitle: mode.subtitle || '',
    product_id: mode.product_id || '',
    image_caption: mode.image_caption || '',
    spirit_pill_scheme: mode.spirit_pill_scheme || FALLBACK_SCHEME.key,
    pills: (Array.isArray(mode.pills) ? mode.pills : []).map((pill) => ({
      label: pill?.label || '',
      scheme: pill?.scheme || FALLBACK_SCHEME.key
    }))
  };
}

// `09:00` → 540, matching timeToMinutes on the server. Used only to say which
// mode is live right now.
function timeToMinutes(value) {
  const match = /^(\d{1,2}):(\d{2})/.exec(String(value || '').trim());
  if (!match) return null;
  return Number(match[1]) * 60 + Number(match[2]);
}

function isWithinWindow(startTime, endTime, nowMinutes) {
  const start = timeToMinutes(startTime);
  const end = timeToMinutes(endTime);
  if (start == null || end == null || start === end || nowMinutes == null) return false;

  return start < end
    ? nowMinutes >= start && nowMinutes < end
    : nowMinutes >= start || nowMinutes < end;
}

// The pill exactly as the app draws it, so the colour choice is a look rather
// than a word.
function PillPreview({ scheme, children }) {
  const colors = scheme || FALLBACK_SCHEME;

  return <span
    className="goldenHourPill"
    style={{ background: colors.background, color: colors.foreground }}
  >{children}</span>;
}

function SchemeSelect({ value, schemes, onChange }) {
  return <select value={value} onChange={(e) => onChange(e.target.value)}>
    {schemes.map((scheme) => <option key={scheme.key} value={scheme.key}>{scheme.label}</option>)}
  </select>;
}

export default function GoldenHour() {
  const { data, loading, error, reload } = useLoad(() => api('/api/golden-hour'));
  const messageRef = useRef(null);
  const [msg, setMsg] = useState('');
  const [msgType, setMsgType] = useState('ok');
  const [drafts, setDrafts] = useState({});
  const [imageFiles, setImageFiles] = useState({});

  const modes = data?.modes || [];
  const modeLabels = data?.modeLabels || {};
  const schemes = data?.pillSchemes || [FALLBACK_SCHEME];
  const cocktails = data?.cocktails || [];
  const maxPills = data?.maxPills ?? 4;
  const coverage = data?.coverage || { overlaps: [], gaps: [] };
  const nowMinutes = data?.now_minutes ?? null;

  const schemeFor = (key) => schemes.find((scheme) => scheme.key === key) || schemes[0] || FALLBACK_SCHEME;

  // Keyed off the payload rather than the derived array: `data?.modes || []` is
  // a fresh array on every render while the load is in flight.
  useEffect(() => {
    setDrafts(Object.fromEntries((data?.modes || []).map((mode) => [mode.mode, draftFromMode(mode)])));
  }, [data]);

  function showMessage(text, type = 'ok') {
    setMsg(text);
    setMsgType(type);
    window.requestAnimationFrame(() => {
      messageRef.current?.scrollIntoView({ behavior: 'smooth', block: 'start' });
    });
  }

  function patchDraft(mode, patch) {
    setDrafts((current) => ({ ...current, [mode]: { ...(current[mode] || {}), ...patch } }));
  }

  function patchPill(mode, index, patch) {
    setDrafts((current) => {
      const draft = current[mode] || {};
      const pills = [...(draft.pills || [])];
      pills[index] = { ...pills[index], ...patch };
      return { ...current, [mode]: { ...draft, pills } };
    });
  }

  function addPill(mode) {
    setDrafts((current) => {
      const draft = current[mode] || {};
      const pills = [...(draft.pills || [])];
      if (pills.length >= maxPills) return current;
      pills.push({ label: '', scheme: FALLBACK_SCHEME.key });
      return { ...current, [mode]: { ...draft, pills } };
    });
  }

  function removePill(mode, index) {
    setDrafts((current) => {
      const draft = current[mode] || {};
      const pills = (draft.pills || []).filter((_, position) => position !== index);
      return { ...current, [mode]: { ...draft, pills } };
    });
  }

  function chooseWebpImage(mode, file) {
    if (!file) {
      setImageFiles((current) => ({ ...current, [mode]: null }));
      return;
    }

    if (!isWebpFile(file)) {
      setImageFiles((current) => ({ ...current, [mode]: null }));
      showMessage('Please choose a .webp image file.', 'error');
      return;
    }

    if (file.size > MAX_IMAGE_BYTES) {
      setImageFiles((current) => ({ ...current, [mode]: null }));
      showMessage('Image is too large. Maximum size is 3 MB.', 'error');
      return;
    }

    setImageFiles((current) => ({ ...current, [mode]: file }));
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

  // The whole draft goes up on every save, `pills` included: the array is the
  // list, so dropping a pill is sending a shorter one.
  function patchBody(draft) {
    return {
      is_active: toBool(draft.is_active),
      start_time: draft.start_time,
      end_time: draft.end_time,
      title: draft.title ?? '',
      subtitle: draft.subtitle ?? '',
      product_id: draft.product_id ? draft.product_id : null,
      image_caption: draft.image_caption ?? '',
      spirit_pill_scheme: draft.spirit_pill_scheme,
      pills: (draft.pills || [])
        .map((pill) => ({ label: String(pill.label || '').trim(), scheme: pill.scheme }))
        .filter((pill) => pill.label)
    };
  }

  async function saveMode(mode) {
    const draft = drafts[mode] || {};

    await runAction(async () => {
      await api(`/api/golden-hour/${mode}`, {
        method: 'PATCH',
        body: JSON.stringify(patchBody(draft))
      });
    }, `${modeLabels[mode] || mode} saved.`);
  }

  // The toggle saves on its own rather than waiting for the Save button, so
  // pulling a live mode is one click. It still carries the rest of the draft:
  // switching a mode on is refused without a title and a cocktail, and those
  // may only exist in the form so far.
  async function setModeActive(mode, isActive) {
    const draft = drafts[mode] || {};

    await runAction(async () => {
      await api(`/api/golden-hour/${mode}`, {
        method: 'PATCH',
        body: JSON.stringify({ ...patchBody(draft), is_active: isActive })
      });
    }, isActive ? `${modeLabels[mode] || mode} is live.` : `${modeLabels[mode] || mode} switched off.`);
  }

  async function uploadImage(mode) {
    const file = imageFiles[mode];

    if (!file) {
      showMessage('Choose a .webp image first.', 'error');
      return;
    }

    await runAction(async () => {
      await api(`/api/golden-hour/${mode}/image`, {
        method: 'POST',
        body: JSON.stringify(await imageUploadPayload(file))
      });
      setImageFiles((current) => ({ ...current, [mode]: null }));
    }, 'Image uploaded.');
  }

  async function removeImage(mode) {
    if (!window.confirm('Remove this image? It is deleted from storage and this cannot be undone.')) return;

    await runAction(async () => {
      await api(`/api/golden-hour/${mode}/image`, { method: 'DELETE' });
      setImageFiles((current) => ({ ...current, [mode]: null }));
    }, 'Image removed.');
  }

  if (loading || error) return <Loading error={error} onRetry={reload} />;

  const liveMode = modes.find((mode) => mode.is_active && isWithinWindow(mode.start_time, mode.end_time, nowMinutes));

  return <div className="grid">
    <div ref={messageRef} className="messageAnchor"><Message text={msg} type={msgType} /></div>

    <Section title="Golden Hour">
      <p className="muted smallText noPad">
        The card the app opens with when a customer already has a beach cart chosen. Which of the four
        versions they get depends on the hour it is in Cairo. A mode has to have a title and a cocktail
        before it can be switched on, and one that is off is simply skipped — if no mode covers the current
        hour, the app opens with no card at all.
      </p>

      <div className="subPanel noTopMargin">
        <b>Showing now</b>
        <p className="muted smallText noPad">
          {liveMode
            ? `${modeLabels[liveMode.mode] || liveMode.mode} — ${liveMode.start_time} to ${liveMode.end_time} Cairo time.`
            : 'Nothing. No live mode covers this hour, so the app opens straight onto Home.'}
        </p>

        {!!coverage.gaps.length && <p className="muted smallText noPad">
          Uncovered hours: {coverage.gaps.map((gap) => `${gap.start}–${gap.end}`).join(', ')}. Customers
          opening the app then see no card.
        </p>}

        {!!coverage.overlaps.length && <p className="muted smallText noPad">
          Overlapping windows: {coverage.overlaps.map(([left, right]) => `${modeLabels[left] || left} & ${modeLabels[right] || right}`).join(', ')}.
          Where two overlap, the earlier one in this page's order wins.
        </p>}
      </div>
    </Section>

    {modes.map((mode) => {
      const draft = drafts[mode.mode] || draftFromMode(mode);
      const selectedFile = imageFiles[mode.mode];
      const pills = draft.pills || [];
      const isLive = mode.mode === liveMode?.mode;

      return <Section
        key={mode.mode}
        title={`${modeLabels[mode.mode] || mode.mode}${isLive ? ' · showing now' : ''}`}
        action={<label className="checkboxField">
          <input
            type="checkbox"
            checked={!!mode.is_active}
            onChange={(e) => setModeActive(mode.mode, e.target.checked)}
          />
          <span>{mode.is_active ? 'Active' : 'Off'}</span>
        </label>}
      >
        <div className="goldenHourGrid">
          <div className="goldenHourFields">
            <label>
              <span>Window (Cairo)</span>
              <div className="goldenHourWindow">
                <input
                  type="time"
                  value={draft.start_time}
                  onChange={(e) => patchDraft(mode.mode, { start_time: e.target.value })}
                />
                <span className="muted smallText noPad">to</span>
                <input
                  type="time"
                  value={draft.end_time}
                  onChange={(e) => patchDraft(mode.mode, { end_time: e.target.value })}
                />
              </div>
              <span className="muted smallText noPad">
                The start is included and the end is not. An end earlier than the start runs past midnight —
                19:00 to 02:00 is the evening and the small hours.
              </span>
            </label>

            <label>
              <span>Title</span>
              <input
                maxLength={TITLE_MAX}
                value={draft.title}
                placeholder="Golden hour is calling"
                onChange={(e) => patchDraft(mode.mode, { title: e.target.value })}
              />
              <span className="muted smallText noPad">
                Use / to split the app title onto two lines, for example: Fire&apos;s lit./One more round.
              </span>
            </label>

            <label>
              <span>Text beneath the title</span>
              <textarea
                maxLength={SUBTITLE_MAX}
                rows={2}
                value={draft.subtitle}
                placeholder="The sun is doing its thing. Here is what to pour."
                onChange={(e) => patchDraft(mode.mode, { subtitle: e.target.value })}
              />
            </label>

            <label>
              <span>Cocktail</span>
              <select
                value={draft.product_id}
                onChange={(e) => patchDraft(mode.mode, { product_id: e.target.value })}
              >
                <option value="">Choose a cocktail</option>
                {cocktails.map((cocktail) => <option key={cocktail.id} value={cocktail.id}>{cocktail.name}</option>)}
              </select>
              <span className="muted smallText noPad">
                What the card's Add to Cart adds, and the spirit the first pill names.
              </span>
            </label>

            <label>
              <span>Text under the image</span>
              <input
                maxLength={CAPTION_MAX}
                value={draft.image_caption}
                placeholder="Served long, over ice"
                onChange={(e) => patchDraft(mode.mode, { image_caption: e.target.value })}
              />
            </label>
          </div>

          <div className="goldenHourImage">
            <div className="imagePreviewBox shopImagePreviewBox">
              {mode.image_url
                ? <img className="cocktailImagePreview" src={mode.image_url} alt="" />
                : <span className="imagePlaceholder">No image</span>}
            </div>

            <label className="fileButton">
              <input
                type="file"
                accept="image/webp,.webp"
                onChange={(e) => chooseWebpImage(mode.mode, e.target.files?.[0])}
              />
              <span>{selectedFile ? 'Change WebP image' : mode.image_url ? 'Replace image' : 'Choose WebP image'}</span>
            </label>

            <div className="goldenHourImageActions">
              <button type="button" disabled={!selectedFile} onClick={() => uploadImage(mode.mode)}>Upload</button>
              {mode.image_url && <button type="button" className="danger" onClick={() => removeImage(mode.mode)}>Remove</button>}
            </div>

            {selectedFile && <div className="selectedFile">{selectedFile.name} · {fileSizeLabel(selectedFile.size)}</div>}
          </div>
        </div>

        <div className="subPanel">
          <b>Pills</b>
          <p className="muted smallText noPad">
            The first pill is always the cocktail's spirit and its text is written for you — pick its colour
            only. Add up to {maxPills} more after it.
          </p>

          <div className="goldenHourPillRow">
            <PillPreview scheme={schemeFor(draft.spirit_pill_scheme)}>
              Your {'{spirit}'}
            </PillPreview>
            {pills.filter((pill) => pill.label.trim()).map((pill, index) => (
              <PillPreview key={index} scheme={schemeFor(pill.scheme)}>{pill.label}</PillPreview>
            ))}
          </div>

          <div className="goldenHourPillEditor">
            <div className="editLine goldenHourPillLine">
              <span className="muted smallText noPad">Spirit pill (text is automatic)</span>
              <SchemeSelect
                value={draft.spirit_pill_scheme}
                schemes={schemes}
                onChange={(value) => patchDraft(mode.mode, { spirit_pill_scheme: value })}
              />
              <span />
            </div>

            {pills.map((pill, index) => <div className="editLine goldenHourPillLine" key={index}>
              <input
                maxLength={PILL_LABEL_MAX}
                value={pill.label}
                placeholder="Pill text"
                onChange={(e) => patchPill(mode.mode, index, { label: e.target.value })}
              />
              <SchemeSelect
                value={pill.scheme}
                schemes={schemes}
                onChange={(value) => patchPill(mode.mode, index, { scheme: value })}
              />
              <button type="button" className="danger" onClick={() => removePill(mode.mode, index)}>Remove</button>
            </div>)}

            <button
              type="button"
              className="compactButton"
              disabled={pills.length >= maxPills}
              onClick={() => addPill(mode.mode)}
            >Add pill</button>
          </div>
        </div>

        <div className="goldenHourActions">
          <button type="button" className="primary" onClick={() => saveMode(mode.mode)}>Save {modeLabels[mode.mode] || mode.mode}</button>
        </div>
      </Section>;
    })}
  </div>;
}
