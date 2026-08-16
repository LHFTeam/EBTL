import { useCallback, useRef, useState } from 'react';
import { AlertTriangle, Camera, CameraOff, Check, Keyboard, PackageCheck, RefreshCw, ShieldAlert, X } from 'lucide-react';
import { api } from '../api/client.js';
import { useQrScanner } from './qrScanner.js';

// The handoff sheet: scan the customer's code, check the bag against what comes
// back, release the order. The camera and the two decoders live in
// `qrScanner.js`, shared with the kitchen display's own handoff sheet.

const OVERRIDE_REASONS = [
  { value: 'dead_phone', label: 'Phone is dead or lost' },
  { value: 'no_app', label: 'App reinstalled — order is gone' },
  { value: 'app_error', label: 'App will not show the code' },
  { value: 'staff_error', label: 'Staff error at the cart' },
  { value: 'other', label: 'Something else' }
];

const CAMERA_MESSAGES = {
  blocked: 'Camera access was blocked. Allow it in the browser, or enter the code by hand.',
  missing: 'No camera on this device. Enter the code by hand.',
  failed: 'Could not start the camera. Enter the code by hand.'
};

export default function PickupScanner({ order, onClose, onHandedOver }) {
  const [mode, setMode] = useState('scan');
  const [problem, setProblem] = useState(null);
  const [reviewing, setReviewing] = useState(null);
  const [busy, setBusy] = useState(false);
  const [manual, setManual] = useState({ order_number: order?.order_number || '', short_code: '' });
  const [override, setOverride] = useState({ reason_code: '', phone_last4: '' });

  const videoRef = useRef(null);
  const canvasRef = useRef(null);

  // Answers `false` when the code did not stick, which is what tells the frame
  // loop to keep looking. Leaving `review` is what stops the camera: the sheet
  // is no longer scanning, so the preview has nothing to do but run hot.
  const verify = useCallback(async (presented) => {
    setBusy(true);
    setProblem(null);

    try {
      const result = await api('/api/cart-operations/pickups/verify', {
        method: 'POST',
        body: JSON.stringify(presented)
      });
      setReviewing({ presented, order: result.order, method: result.method });
      setMode('review');
      return true;
    } catch (error) {
      setProblem({
        code: error.data?.code || 'failed',
        message: error.message || 'Could not check that code.'
      });
      return false;
    } finally {
      setBusy(false);
    }
  }, []);

  const { cameraError } = useQrScanner({
    active: mode === 'scan',
    videoRef,
    canvasRef,
    messages: CAMERA_MESSAGES,
    onToken: (token) => verify({ token })
  });

  async function confirmHandover() {
    if (!reviewing) return;
    setBusy(true);
    setProblem(null);

    try {
      const result = await api('/api/cart-operations/pickups/confirm', {
        method: 'POST',
        body: JSON.stringify(reviewing.presented)
      });
      onHandedOver({
        order_number: result.order.order_number,
        method: result.method,
        logged: result.logged
      });
    } catch (error) {
      setProblem({
        code: error.data?.code || 'failed',
        message: error.message || 'Could not release that order.'
      });
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

  async function submitOverride(event) {
    event.preventDefault();
    setBusy(true);
    setProblem(null);

    try {
      const result = await api('/api/cart-operations/pickups/override', {
        method: 'POST',
        body: JSON.stringify({
          order_id: order.id,
          reason_code: override.reason_code,
          phone_last4: override.phone_last4.trim() || undefined
        })
      });
      onHandedOver({
        order_number: result.order.order_number,
        method: 'override',
        logged: result.logged
      });
    } catch (error) {
      setProblem({
        code: error.data?.code || 'failed',
        message: error.message || 'Could not override that handoff.'
      });
      setBusy(false);
    }
  }

  function rescan() {
    setReviewing(null);
    setProblem(null);
    setManual((current) => ({ ...current, short_code: '' }));
    setMode('scan');
  }

  return <div className="pickupOverlay" role="dialog" aria-modal="true" aria-label="Hand over order">
    <button className="pickupScrim" type="button" aria-label="Close" onClick={onClose} />

    <aside className="pickupSheet">
      <div className="pickupSheetHead">
        <div>
          <span className="eyebrow">Hand over</span>
          <h2>{mode === 'review' ? 'Check the bag' : 'Scan the customer’s code'}</h2>
          <p>{mode === 'review'
            ? 'Match these items to what you are about to give them.'
            : `Order #${String(order?.order_number || '').replace(/^#/, '')} is waiting. Any customer’s code can be scanned here.`}</p>
        </div>
        <button className="recipeClose" type="button" onClick={onClose}><X size={20} /> Close</button>
      </div>

      {problem && <div className={problem.code === 'expired' || problem.code === 'code_mismatch' ? 'pickupNotice warn' : 'pickupNotice stop'}>
        <AlertTriangle size={18} />
        <span>{problem.message}</span>
      </div>}

      {mode === 'scan' && <>
        <div className="pickupCamera">
          {cameraError
            ? <div className="pickupCameraOff"><CameraOff size={30} /><b>Camera unavailable</b><span>{cameraError}</span></div>
            : <>
              <video ref={videoRef} playsInline muted />
              <canvas ref={canvasRef} hidden />
              <div className="pickupReticle" aria-hidden="true" />
            </>}
          {busy && <div className="pickupCameraBusy"><RefreshCw size={18} className="spinIcon" /> Checking…</div>}
        </div>

        <div className="pickupSwitchRow">
          <button type="button" onClick={() => setMode('manual')}><Keyboard size={17} /> Can’t scan — type the code</button>
          <button type="button" className="pickupOverrideLink" onClick={() => setMode('override')}><ShieldAlert size={17} /> No code at all</button>
        </div>
      </>}

      {mode === 'manual' && <form className="pickupForm" onSubmit={submitManual}>
        <p className="pickupHint">The six digits under the QR on the customer’s screen. They expire with the code, so ask for a fresh one if it has been sitting a while.</p>

        <label>
          <span>Order number</span>
          <input
            value={manual.order_number}
            onChange={(event) => setManual({ ...manual, order_number: event.target.value })}
            inputMode="numeric"
            autoComplete="off"
            required
          />
        </label>

        <label>
          <span>Six-digit code</span>
          <input
            className="pickupDigits"
            value={manual.short_code}
            onChange={(event) => setManual({ ...manual, short_code: event.target.value.replace(/\D/g, '').slice(0, 6) })}
            inputMode="numeric"
            pattern="\d{6}"
            placeholder="000000"
            autoComplete="off"
            required
          />
        </label>

        <div className="pickupActions">
          <button type="button" onClick={rescan}><Camera size={17} /> Back to scanning</button>
          <button className="primary" type="submit" disabled={busy || manual.short_code.length !== 6}>
            {busy ? <RefreshCw size={18} className="spinIcon" /> : <Check size={18} />} Check code
          </button>
        </div>
      </form>}

      {mode === 'override' && <form className="pickupForm" onSubmit={submitOverride}>
        <div className="pickupNotice warn">
          <ShieldAlert size={18} />
          <span>Releasing order #{String(order?.order_number || '').replace(/^#/, '')} without a code. This is logged against your name.</span>
        </div>

        <label>
          <span>Why is there no code?</span>
          <select
            value={override.reason_code}
            onChange={(event) => setOverride({ ...override, reason_code: event.target.value })}
            required
          >
            <option value="" disabled>Choose a reason</option>
            {OVERRIDE_REASONS.map((reason) => <option key={reason.value} value={reason.value}>{reason.label}</option>)}
          </select>
        </label>

        <label>
          <span>Last 4 digits of their phone</span>
          <input
            className="pickupDigits"
            value={override.phone_last4}
            onChange={(event) => setOverride({ ...override, phone_last4: event.target.value.replace(/\D/g, '').slice(0, 4) })}
            inputMode="numeric"
            pattern="\d{4}"
            placeholder="0000"
            autoComplete="off"
          />
        </label>
        <p className="pickupHint">Ask the customer, then check it against the order. This is the only identity check an override gets.</p>

        <div className="pickupActions">
          <button type="button" onClick={rescan}><Camera size={17} /> Back to scanning</button>
          <button className="primary danger" type="submit" disabled={busy || !override.reason_code}>
            {busy ? <RefreshCw size={18} className="spinIcon" /> : <ShieldAlert size={18} />} Override and release
          </button>
        </div>
      </form>}

      {mode === 'review' && reviewing && <div className="pickupReview">
        {reviewing.order.id !== order?.id && <div className="pickupNotice warn">
          <AlertTriangle size={18} />
          <span>This is a different order from the one you had open. Hand over the one below.</span>
        </div>}

        <div className="pickupReviewHead">
          <div>
            <b>#{String(reviewing.order.order_number || '').replace(/^#/, '')}</b>
            <span>{reviewing.order.customer?.name || 'Walk-in Customer'} · {reviewing.order.item_count} items</span>
          </div>
          <span className="pickupMethodChip">{reviewing.method === 'qr' ? 'Scanned' : 'Typed code'}</span>
        </div>

        <div className="pickupReviewItems">
          {(reviewing.order.items || []).map((item) => <div className="pickupReviewItem" key={item.id}>
            <span className="pickupItemQty">{item.quantity}</span>
            <div>
              <b>{item.product_name_snapshot}</b>
              <span>{item.variant_name_snapshot || (item.serving_count > 1 ? `${item.serving_count} servings` : 'Standard')}</span>
              {item.customization_summary && <small>{item.customization_summary}</small>}
            </div>
          </div>)}
        </div>

        {reviewing.order.customer_notes && <div className="orderNoteCompact">Note: {reviewing.order.customer_notes}</div>}

        <div className="pickupActions">
          <button type="button" onClick={rescan}><Camera size={17} /> Scan another</button>
          <button className="primary" type="button" disabled={busy} onClick={confirmHandover}>
            {busy ? <RefreshCw size={18} className="spinIcon" /> : <PackageCheck size={18} />} Confirm handover
          </button>
        </div>
      </div>}
    </aside>
  </div>;
}
