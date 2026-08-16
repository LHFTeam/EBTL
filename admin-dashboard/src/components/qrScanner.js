import { useCallback, useEffect, useRef, useState } from 'react';
import jsQR from 'jsqr';

// The camera half of a pickup handoff, with no opinion about what a scanned
// token means or how the sheet around it looks. Two screens use it: the
// dashboard's PickupScanner (English, cart operator on a phone) and the
// kitchen display's PrepPickupSheet (bilingual, tablet at the cart).
//
// Two decoders, because the carts run a mixed fleet. Chrome on Android has
// BarcodeDetector built in and does the work off the main thread; Safari has
// no such thing, so jsQR reads frames off a canvas instead. Everything after
// the decode is identical, and both fall through to typing the code by hand
// when the camera is refused, missing, or simply beaten by the sun.

const FRAME_INTERVAL_MS = 200;

async function createDetector() {
  if (typeof window === 'undefined' || !('BarcodeDetector' in window)) return null;

  try {
    const formats = await window.BarcodeDetector.getSupportedFormats();
    if (!formats.includes('qr_code')) return null;
    return new window.BarcodeDetector({ formats: ['qr_code'] });
  } catch {
    return null;
  }
}

function cameraProblem(error, messages) {
  if (error?.name === 'NotAllowedError') return messages.blocked;
  if (error?.name === 'NotFoundError') return messages.missing;
  return messages.failed;
}

/**
 * Runs the preview and the decode loop while `active`, and hands each decoded
 * token to `onToken`. The caller owns the video and canvas elements so it can
 * place and style them; this owns the stream, the interval, and the claim.
 *
 * The claim is what stops the loop reading the same code forty more times
 * while the first read is still in flight: it is taken the moment a token is
 * decoded and held until `onToken` settles. Resolving `false` releases it —
 * the caller saying "that one did not stick, keep looking" — while anything
 * else keeps the loop quiet, because a code that worked ends the scan.
 */
export function useQrScanner({ active, videoRef, canvasRef, onToken, messages }) {
  const [cameraError, setCameraError] = useState('');
  const streamRef = useRef(null);
  const claimedRef = useRef(false);
  const onTokenRef = useRef(onToken);
  const messagesRef = useRef(messages);

  // Kept in refs so a re-render with a fresh callback or a language switch
  // mid-scan does not tear down the camera and start it again.
  useEffect(() => {
    onTokenRef.current = onToken;
    messagesRef.current = messages;
  });

  const stopCamera = useCallback(() => {
    for (const track of streamRef.current?.getTracks() || []) track.stop();
    streamRef.current = null;
  }, []);

  useEffect(() => {
    if (!active) return undefined;

    let cancelled = false;
    let timer = null;
    claimedRef.current = false;

    (async () => {
      let stream;
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: { ideal: 'environment' } },
          audio: false
        });
      } catch (error) {
        if (!cancelled) setCameraError(cameraProblem(error, messagesRef.current));
        return;
      }

      if (cancelled) {
        for (const track of stream.getTracks()) track.stop();
        return;
      }

      streamRef.current = stream;
      setCameraError('');

      const video = videoRef.current;
      if (!video) return;
      video.srcObject = stream;
      try {
        await video.play();
      } catch {
        // Autoplay refusal leaves a paused preview; the manual path still works.
      }

      const detector = await createDetector();

      const read = async () => {
        if (cancelled || claimedRef.current) return;
        if (!video.videoWidth) return;

        let token = null;

        if (detector) {
          try {
            const [found] = await detector.detect(video);
            token = found?.rawValue || null;
          } catch {
            token = null;
          }
        } else {
          const canvas = canvasRef.current;
          if (!canvas) return;
          canvas.width = video.videoWidth;
          canvas.height = video.videoHeight;
          const context = canvas.getContext('2d', { willReadFrequently: true });
          context.drawImage(video, 0, 0, canvas.width, canvas.height);
          const frame = context.getImageData(0, 0, canvas.width, canvas.height);
          token = jsQR(frame.data, frame.width, frame.height, { inversionAttempts: 'dontInvert' })?.data || null;
        }

        if (token && !claimedRef.current) {
          claimedRef.current = true;
          if (await onTokenRef.current(token) === false) claimedRef.current = false;
        }
      };

      timer = window.setInterval(read, FRAME_INTERVAL_MS);
    })();

    return () => {
      cancelled = true;
      if (timer) window.clearInterval(timer);
      stopCamera();
    };
  }, [active, stopCamera, videoRef, canvasRef]);

  useEffect(() => stopCamera, [stopCamera]);

  return { cameraError };
}
