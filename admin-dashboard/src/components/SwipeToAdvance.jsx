import { useRef, useState } from 'react';
import { RefreshCw } from 'lucide-react';

// Slide-to-confirm, the way a phone asks before powering off.
//
// The kitchen display used to advance an order when the ticket was tapped
// anywhere, which is exactly the gesture a wet sleeve or a passing tray makes
// against a wall-mounted tablet. A deliberate slide cannot happen by accident,
// and it puts the commitment where the operator is already looking.
//
// The slide runs toward the end of the reading direction — right in English,
// left in Arabic — so the gesture always means "forward" on a screen that
// flips. Which way that is comes from where the handle actually rests in its
// track, measured when the drag starts, rather than from a prop that could
// disagree with the direction the browser laid the track out in.
//
// Keyboard and screen-reader users get Enter/Space on the handle, which is the
// same commitment without the travel.

// How far along the track counts as a decision. Short of this the handle
// springs back, which is the gesture's own undo.
const CONFIRM_AT = 0.85;

export default function SwipeToAdvance({
  label,
  ariaLabel,
  icon: Icon,
  tone = 'advance',
  busy = false,
  onConfirm
}) {
  const trackRef = useRef(null);
  const knobRef = useRef(null);
  const dragRef = useRef(null);
  const progressRef = useRef(0);
  const [progress, setProgress] = useState(0);
  // Only so the spring-back transition can be switched off while a finger is
  // actually on the handle; the drag itself is tracked in refs.
  const [dragging, setDragging] = useState(false);

  function moveTo(value) {
    const clamped = Math.min(Math.max(value, 0), 1);
    progressRef.current = clamped;
    setProgress(clamped);
  }

  function startDrag(event) {
    if (busy) return;

    const track = trackRef.current;
    const knob = knobRef.current;
    if (!track || !knob) return;

    const trackRect = track.getBoundingClientRect();
    const knobRect = knob.getBoundingClientRect();
    // The handle rests against the start edge, so whichever side it is nearer
    // is the side it slides away from. That also gives the gutter, rather than
    // repeating the CSS padding here where the two could drift apart.
    const startGutter = knobRect.left - trackRect.left;
    const endGutter = trackRect.right - knobRect.right;
    const sign = startGutter <= endGutter ? 1 : -1;
    const gutter = Math.min(startGutter, endGutter);
    const distance = Math.max(trackRect.width - knobRect.width - gutter * 2, 1);

    dragRef.current = { startX: event.clientX, distance, sign };
    knob.setPointerCapture?.(event.pointerId);
    setDragging(true);
  }

  function continueDrag(event) {
    const drag = dragRef.current;
    if (!drag) return;
    moveTo(((event.clientX - drag.startX) * drag.sign) / drag.distance);
  }

  function endDrag(event) {
    if (!dragRef.current) return;
    dragRef.current = null;
    setDragging(false);
    knobRef.current?.releasePointerCapture?.(event.pointerId);

    const reached = progressRef.current >= CONFIRM_AT;
    moveTo(0);
    if (reached) onConfirm();
  }

  function onKeyDown(event) {
    if (busy || (event.key !== 'Enter' && event.key !== ' ')) return;
    event.preventDefault();
    onConfirm();
  }

  return (
    <div
      ref={trackRef}
      className={`prepKdsSwipe prepKdsSwipe-${tone} ${dragging ? 'prepKdsSwipe-dragging' : ''} ${busy ? 'prepKdsSwipe-locked' : ''}`}
      // The only dynamic value in the control: how far along the slide is.
      // Everything drawn from it (the fill, the label fade) lives in styles.css.
      style={{ '--prep-swipe-progress': progress }}
    >
      <span className="prepKdsSwipeFill" aria-hidden="true" />
      <span className="prepKdsSwipeLabel">{label}</span>
      <button
        ref={knobRef}
        className="prepKdsSwipeKnob"
        type="button"
        aria-label={ariaLabel}
        aria-disabled={busy}
        style={{ transform: `translateX(${progress * (dragRef.current?.sign || 0) * (dragRef.current?.distance || 0)}px)` }}
        onPointerDown={startDrag}
        onPointerMove={continueDrag}
        onPointerUp={endDrag}
        onPointerCancel={endDrag}
        onKeyDown={onKeyDown}
      >
        {busy ? <RefreshCw className="spinIcon" size={22} /> : <Icon size={22} />}
      </button>
    </div>
  );
}
