import { useEffect } from 'react';

// Keyboard containment for the kitchen display's two overlays (the recipe
// drawer and the handoff sheet). The KDS is a touch screen first, but it is
// also the one dashboard route staff run full-screen with a keyboard attached,
// so Tab must not wander onto the ticket wall behind an open dialog.

const FOCUSABLE_SELECTOR = [
  'button:not([disabled])',
  '[href]',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])'
].join(',');

/**
 * Marks everything outside the dialog inert while it is open, cycles Tab
 * inside it, closes on Escape, and hands focus back where it came from.
 *
 * `focusKey` re-runs the trap when the dialog's content is swapped underneath
 * it (a different recipe, a different scan step) so focus lands on the new
 * first control rather than a button that no longer exists.
 */
export function useModalFocusTrap(dialogRef, { active, onClose, focusKey }) {
  useEffect(() => {
    if (!active) return undefined;

    const previouslyFocused = document.activeElement;
    const dialog = dialogRef.current;
    const overlay = dialog?.parentElement;
    const root = overlay?.parentElement;
    const backgroundElements = root
      ? [...root.children].filter((element) => element !== overlay)
      : [];

    for (const element of backgroundElements) {
      element.inert = true;
    }

    dialog?.querySelector(FOCUSABLE_SELECTOR)?.focus();

    function onKeyDown(event) {
      if (event.key === 'Escape') {
        event.preventDefault();
        onClose();
        return;
      }

      if (event.key !== 'Tab' || !dialog) return;

      const focusable = [...dialog.querySelectorAll(FOCUSABLE_SELECTOR)]
        .filter((element) => !element.disabled && element.getAttribute('aria-hidden') !== 'true');
      if (!focusable.length) {
        event.preventDefault();
        dialog.focus();
        return;
      }

      const first = focusable[0];
      const last = focusable[focusable.length - 1];
      if (event.shiftKey && document.activeElement === first) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && document.activeElement === last) {
        event.preventDefault();
        first.focus();
      }
    }

    window.addEventListener('keydown', onKeyDown);
    return () => {
      window.removeEventListener('keydown', onKeyDown);
      for (const element of backgroundElements) {
        element.inert = false;
      }
      if (previouslyFocused instanceof HTMLElement && previouslyFocused.isConnected) {
        previouslyFocused.focus();
      }
    };
  }, [active, focusKey, onClose, dialogRef]);
}
