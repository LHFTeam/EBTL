import { useCallback, useRef, useState } from 'react';
import { AlertTriangle, Camera, CameraOff, Check, Keyboard, PackageCheck, RefreshCw, X } from 'lucide-react';
import { api } from '../api/client.js';
import { hasString, resolveItemName, t } from '../i18n/kdsStrings.js';
import { useModalFocusTrap } from './modalFocus.js';
import { useQrScanner } from './qrScanner.js';

// The kitchen display's half of the pickup gate.
//
// A cart pickup leaves `ready` only when the customer proves they are the one
// collecting it, so the KDS cannot complete one with a button — it has to scan.
// This is the dashboard's PickupScanner said in the kitchen's own terms:
// bilingual and RTL-aware, sized for a tablet clamped to the cart rather than a
// phone held one-handed, and without the override branch, which prep accounts
// are not allowed to use (the server keeps that for supervisors and up).

function stripHash(value) {
  return String(value || '').replace(/^#/, '');
}

// Handoff failures answer with a `code` the sheet can say in Arabic. Anything
// unmapped — a Supabase error, a schema rejection — falls back to the server's
// own message, which is English but true, and never to a bare error code.
function problemFor(error, lang, fallbackKey) {
  if (error?.status === 429) return t('pickupError.rate_limited', lang);

  const code = error?.data?.code;
  if (code && hasString(`pickupError.${code}`)) return t(`pickupError.${code}`, lang);

  return error?.message || t(fallbackKey, lang);
}

export default function PrepPickupSheet({ order, lang, onClose, onHandedOver }) {
  const [mode, setMode] = useState('scan');
  const [problem, setProblem] = useState('');
  const [reviewing, setReviewing] = useState(null);
  const [busy, setBusy] = useState(false);
  const [manual, setManual] = useState({
    order_number: stripHash(order?.order_number),
    short_code: ''
  });

  const dialogRef = useRef(null);
  const videoRef = useRef(null);
  const canvasRef = useRef(null);

  const tt = (key, params) => t(key, lang, params);

  useModalFocusTrap(dialogRef, { active: true, onClose, focusKey: mode });

  // Answering `false` is what tells the frame loop to keep looking: the code
  // was read, the server refused it, and the customer is still standing there.
  const verify = useCallback(async (presented) => {
    setBusy(true);
    setProblem('');

    try {
      const result = await api('/api/cart-operations/pickups/verify', {
        method: 'POST',
        body: JSON.stringify(presented)
      });
      setReviewing({ presented, order: result.order, method: result.method });
      setMode('review');
      return true;
    } catch (error) {
      setProblem(problemFor(error, lang, 'pickupError.failed'));
      return false;
    } finally {
      setBusy(false);
    }
  }, [lang]);

  const { cameraError } = useQrScanner({
    active: mode === 'scan',
    videoRef,
    canvasRef,
    messages: {
      blocked: tt('pickup.cameraBlocked'),
      missing: tt('pickup.cameraMissing'),
      failed: tt('pickup.cameraFailed')
    },
    onToken: (token) => verify({ token })
  });

  async function confirmHandover() {
    if (!reviewing) return;
    setBusy(true);
    setProblem('');

    try {
      const result = await api('/api/cart-operations/pickups/confirm', {
        method: 'POST',
        body: JSON.stringify(reviewing.presented)
      });
      onHandedOver({
        order_id: reviewing.order.id,
        order_number: result.order.order_number,
        logged: result.logged
      });
    } catch (error) {
      setProblem(problemFor(error, lang, 'pickupError.confirmFailed'));
      setBusy(false);
    }
  }

  async function submitManual(event) {
    event.preventDefault();
    await verify({
      order_number: manual.order_number.trim(),
      short_code: manual.short_code.trim()
    });
  }

  function rescan() {
    setReviewing(null);
    setProblem('');
    setManual((current) => ({ ...current, short_code: '' }));
    setMode('scan');
  }

  // The handoff card carries English snapshots only. When the scan turns out to
  // be the ticket that is already open, its items are the same rows the wall is
  // showing, so the Arabic names it already has are reused rather than dropping
  // the operator into English halfway through a handover.
  function itemName(item) {
    const ticketItem = reviewing?.order.id === order?.id
      ? (order?.items || []).find((entry) => entry.id === item.id)
      : null;

    return resolveItemName(ticketItem?.products, item.product_name_snapshot, lang)
      || tt('common.item');
  }

  const reviewingOther = reviewing && reviewing.order.id !== order?.id;

  return (
    <div className="prepKdsOverlay">
      <button className="prepKdsOverlayScrim" type="button" aria-label={tt('pickup.closeAria')} onClick={onClose} />
      <section
        ref={dialogRef}
        className="prepKdsPickup"
        role="dialog"
        aria-modal="true"
        aria-labelledby="prep-pickup-title"
        tabIndex={-1}
      >
        <div className="prepKdsRecipeHead">
          <div>
            <span className="prepKdsRecipeEyebrow">{tt('pickup.eyebrow')}</span>
            <h2 id="prep-pickup-title">
              {mode === 'review' ? tt('pickup.reviewTitle') : tt('pickup.scanTitle')}
            </h2>
            <p>
              {mode === 'review'
                ? tt('pickup.reviewSubtitle')
                : tt('pickup.scanSubtitle', { order: stripHash(order?.order_number) })}
            </p>
          </div>
          <button className="prepKdsClose" type="button" onClick={onClose}>
            <X size={21} />
            {tt('button.close')}
          </button>
        </div>

        {problem && (
          <div className="prepKdsPickupProblem" role="alert">
            <AlertTriangle size={20} />
            <span>{problem}</span>
          </div>
        )}

        {mode === 'scan' && (
          <>
            <div className="prepKdsPickupCamera">
              {cameraError ? (
                <div className="prepKdsPickupCameraOff">
                  <CameraOff size={34} />
                  <strong>{tt('pickup.cameraUnavailable')}</strong>
                  <span>{cameraError}</span>
                </div>
              ) : (
                <>
                  <video ref={videoRef} playsInline muted />
                  <canvas ref={canvasRef} hidden />
                  <div className="prepKdsPickupReticle" aria-hidden="true" />
                </>
              )}
              {busy && (
                <div className="prepKdsPickupBusy">
                  <RefreshCw size={20} className="spinIcon" /> {tt('pickup.checking')}
                </div>
              )}
            </div>

            <button className="prepKdsPickupSwitch" type="button" onClick={() => setMode('manual')}>
              <Keyboard size={20} /> {tt('pickup.typeInstead')}
            </button>

            <p className="prepKdsPickupHint">{tt('pickup.noCode')}</p>
          </>
        )}

        {mode === 'manual' && (
          <form className="prepKdsPickupForm" onSubmit={submitManual}>
            <p className="prepKdsPickupHint">{tt('pickup.manualHint')}</p>

            <label>
              <span>{tt('pickup.orderNumberLabel')}</span>
              <input
                value={manual.order_number}
                onChange={(event) => setManual({ ...manual, order_number: event.target.value })}
                inputMode="numeric"
                autoComplete="off"
                dir="ltr"
                required
              />
            </label>

            <label>
              <span>{tt('pickup.shortCodeLabel')}</span>
              <input
                className="prepKdsPickupDigits"
                value={manual.short_code}
                onChange={(event) => setManual({
                  ...manual,
                  short_code: event.target.value.replace(/\D/g, '').slice(0, 6)
                })}
                inputMode="numeric"
                pattern="\d{6}"
                placeholder="000000"
                autoComplete="off"
                dir="ltr"
                required
              />
            </label>

            <div className="prepKdsPickupActions">
              <button type="button" onClick={rescan}>
                <Camera size={20} /> {tt('pickup.backToScanning')}
              </button>
              <button className="prepKdsPickupPrimary" type="submit" disabled={busy || manual.short_code.length !== 6}>
                {busy ? <RefreshCw size={20} className="spinIcon" /> : <Check size={20} />}
                {tt('pickup.checkCode')}
              </button>
            </div>
          </form>
        )}

        {mode === 'review' && reviewing && (
          <div className="prepKdsPickupReview">
            {reviewingOther && (
              <div className="prepKdsPickupProblem" role="alert">
                <AlertTriangle size={20} />
                <span>{tt('pickup.differentOrder')}</span>
              </div>
            )}

            <div className="prepKdsPickupReviewHead">
              <div>
                <strong>{stripHash(reviewing.order.order_number)}</strong>
                <span>{tt('pickup.itemCount', { count: reviewing.order.item_count })}</span>
              </div>
              <span className="prepKdsPickupMethod">
                {reviewing.method === 'qr' ? tt('pickup.methodScanned') : tt('pickup.methodTyped')}
              </span>
            </div>

            <div className="prepKdsPickupItems">
              {(reviewing.order.items || []).map((item) => (
                <div className="prepKdsTicketItem" key={item.id}>
                  <span className="prepKdsTicketQty">&times;{item.quantity}</span>
                  <span className="prepKdsTicketItemBody">
                    <span className="prepKdsTicketItemName">{itemName(item)}</span>
                    {item.customization_summary && (
                      <span className="prepKdsTicketMod">&#8627; {item.customization_summary}</span>
                    )}
                  </span>
                </div>
              ))}
            </div>

            {reviewing.order.customer_notes && (
              <div className="prepKdsTicketNote">
                <strong>{tt('ticket.note')}</strong>
                <span>{reviewing.order.customer_notes}</span>
              </div>
            )}

            <div className="prepKdsPickupActions">
              <button type="button" onClick={rescan}>
                <Camera size={20} /> {tt('pickup.scanAnother')}
              </button>
              <button className="prepKdsPickupPrimary" type="button" disabled={busy} onClick={confirmHandover}>
                {busy ? <RefreshCw size={20} className="spinIcon" /> : <PackageCheck size={20} />}
                {tt('pickup.confirm')}
              </button>
            </div>
          </div>
        )}
      </section>
    </div>
  );
}
