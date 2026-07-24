import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertTriangle,
  Check,
  ChefHat,
  Clock3,
  LogOut,
  MapPin,
  Power,
  RefreshCw,
  Truck,
  Wifi,
  WifiOff,
  X
} from 'lucide-react';
import { api } from '../api/client.js';
import { connectPrepOrderSocket } from '../realtime/prepOrderSocket.js';

const ACTIVE_STATUS_GROUP = 'active';
const COMPLETED_STATUS_GROUP = 'picked_up';
const DEGRADED_POLL_MS = 15000;
const INVALIDATION_DEBOUNCE_MS = 250;
const BUSINESS_TIME_ZONE = 'Africa/Cairo';

// Urgency thresholds (from received time): green for the first 2 minutes,
// yellow for the next 8 minutes (up to 10), red after that.
const FRESH_MS = 2 * 60 * 1000;
const WARM_MS = 10 * 60 * 1000;

const ACTIVE_STATUSES = ['confirmed', 'preparing', 'ready'];

const STAGE_LABEL = {
  confirmed: 'NEW',
  preparing: 'PREPARING',
  ready: 'READY',
  completed: 'COMPLETED'
};

const cairoTimeFormatter = new Intl.DateTimeFormat('en-US', {
  timeZone: BUSINESS_TIME_ZONE,
  hour: '2-digit',
  minute: '2-digit',
  hour12: true
});

const cairoDayKeyFormatter = new Intl.DateTimeFormat('en-CA', {
  timeZone: BUSINESS_TIME_ZONE,
  year: 'numeric',
  month: '2-digit',
  day: '2-digit'
});

const cairoOrderTimeFormatter = new Intl.DateTimeFormat('en-GB', {
  timeZone: BUSINESS_TIME_ZONE,
  hour: '2-digit',
  minute: '2-digit',
  hour12: false
});

function orderStartedAt(order) {
  return order.confirmed_at || order.created_at || null;
}

function orderCompletedAt(order) {
  return order.completed_at || order.updated_at || null;
}

function orderNumber(order) {
  return order.order_number || 'Order';
}

function variantLabel(item) {
  return item.variant_name_snapshot
    || item.product_variants?.name
    || (Number(item.serving_count || 1) > 1 ? `${item.serving_count} servings` : 'Standard');
}

function formatQuantity(value) {
  const number = Number(value || 0);
  if (!Number.isFinite(number)) return '-';
  if (Math.abs(number - Math.round(number)) < 0.001) return String(Math.round(number));
  return number.toFixed(2).replace(/\.?0+$/, '');
}

function formatTimer(milliseconds) {
  const totalSeconds = Math.max(0, Math.floor(milliseconds / 1000));
  const hours = Math.floor(totalSeconds / 3600);
  const minutes = Math.floor((totalSeconds % 3600) / 60);
  const seconds = totalSeconds % 60;

  if (hours > 0) {
    return `${hours}:${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
  }

  return `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`;
}

function formatOrderTime(value) {
  if (!value) return '--:--';
  const date = new Date(value);
  return Number.isNaN(date.getTime()) ? '--:--' : cairoOrderTimeFormatter.format(date);
}

function cairoDayKey(value) {
  const date = new Date(value || '');
  return Number.isNaN(date.getTime()) ? '' : cairoDayKeyFormatter.format(date);
}

function initialsFor(name) {
  return String(name || '')
    .split(/\s+/)
    .map((word) => word[0])
    .filter(Boolean)
    .join('')
    .slice(0, 2)
    .toUpperCase() || 'EM';
}

function asStringList(value) {
  if (Array.isArray(value)) return value.map(String).map((entry) => entry.trim()).filter(Boolean);
  if (!value) return [];

  if (typeof value === 'string' && value.trim().startsWith('[')) {
    try {
      const parsed = JSON.parse(value);
      if (Array.isArray(parsed)) {
        return parsed.map(String).map((entry) => entry.trim()).filter(Boolean);
      }
    } catch {
      // Fall through to the comma-separated representation.
    }
  }

  return String(value).split(',').map((entry) => entry.trim()).filter(Boolean);
}

function itemAllergens(item) {
  const allergens = [];

  for (const recipeItem of item.recipe_items || []) {
    allergens.push(...asStringList(recipeItem.ingredients?.allergen_flags));
  }

  for (const addition of item.additions || []) {
    for (const recipeItem of addition.recipe_items || []) {
      allergens.push(...asStringList(recipeItem.ingredients?.allergen_flags));
    }
  }

  return [...new Set(allergens)];
}

function orderAllergens(order) {
  return [...new Set((order.items || []).flatMap(itemAllergens))];
}

function modificationLines(item) {
  const lines = [];

  for (const removed of item.removed_ingredients || []) {
    const name = removed.ingredient_name_snapshot || removed.ingredients?.name;
    if (name) lines.push(`NO ${name}`);
  }

  for (const addition of item.additions || []) {
    const name = addition.product_name_snapshot || addition.products?.name;
    const quantity = totalAdditionQuantity(item, addition);
    if (name) lines.push(`ADD ${name}${quantity > 1 ? ` x${quantity}` : ''}`);
  }

  if (!lines.length && item.customization_summary) {
    lines.push(item.customization_summary);
  }

  return [...new Set(lines)];
}

function totalAdditionQuantity(item, addition) {
  const parentQuantity = Math.max(Number(item.quantity || 1), 1);
  const quantityPerParent = Math.max(Number(addition.quantity_per_parent || 1), 1);
  return parentQuantity * quantityPerParent;
}

function elapsedMsFor(order, now) {
  const start = new Date(orderStartedAt(order) || 0).getTime();
  return Number.isFinite(start) && start > 0 ? Math.max(0, now - start) : 0;
}

function urgencyFor(order, now) {
  const elapsed = elapsedMsFor(order, now);
  if (elapsed < FRESH_MS) return 'fresh';
  if (elapsed < WARM_MS) return 'warm';
  return 'urgent';
}

function nextStatusFor(status) {
  if (status === 'confirmed') return 'preparing';
  if (status === 'preparing') return 'ready';
  if (status === 'ready') return 'completed';
  return null;
}

function fulfillmentLabel(order) {
  if (order.fulfillment_type === 'delivery_to_unit') {
    return order.customer_address_snapshot
      ? `Deliver to ${order.customer_address_snapshot}`
      : 'Delivery to unit';
  }

  return 'Pickup at cart';
}

function isRecipeItemRemoved(item, recipeItem) {
  return (item.removed_ingredients || []).some((removed) => (
    removed.recipe_item_id === recipeItem.id
    || (removed.ingredient_id && removed.ingredient_id === recipeItem.ingredient_id)
  ));
}

function scaledIngredientQuantity(item, recipeItem) {
  const recipeYield = Math.max(Number(item.recipe?.yield_servings || 1), 1);
  const servingCount = Math.max(Number(item.serving_count || 1), 1);
  const orderedQuantity = Math.max(Number(item.quantity || 1), 1);
  return (Number(recipeItem.quantity || 0) / recipeYield) * servingCount * orderedQuantity;
}

function connectionCopy(state) {
  if (state === 'live') return 'Live';
  if (state === 'offline') return 'Offline';
  return 'Reconnecting';
}

function TicketItem({ order, item, onOpenRecipe }) {
  const modifications = modificationLines(item);

  return (
    <div className="prepKdsTicketItem">
      <span className="prepKdsTicketQty">&times;{formatQuantity(item.quantity)}</span>
      <span className="prepKdsTicketItemBody">
        <span className="prepKdsTicketItemName">{item.product_name_snapshot || item.products?.name || 'Item'}</span>
        {modifications.map((line) => (
          <span className="prepKdsTicketMod" key={line}>&#8627; {line}</span>
        ))}
      </span>
      <button
        className="prepKdsTicketRecipe"
        type="button"
        onClick={(event) => {
          event.stopPropagation();
          onOpenRecipe(order, item);
        }}
      >
        Recipe
      </button>
    </div>
  );
}

function PrepTicket({ order, now, saving, highlighted, onAdvance, onOpenRecipe }) {
  const urgency = urgencyFor(order, now);
  const allergens = orderAllergens(order);
  const nextStatus = nextStatusFor(order.status);
  const FulfillmentIcon = order.fulfillment_type === 'delivery_to_unit' ? Truck : MapPin;

  return (
    <article
      className={`prepKdsTicket prepKdsTicket-${urgency} prepKdsTicket-${order.status} ${highlighted ? 'prepKdsTicket-new' : ''} ${saving ? 'prepKdsTicket-saving' : ''}`}
      role="button"
      tabIndex={0}
      aria-label={`${orderNumber(order)} - ${STAGE_LABEL[order.status]}. Press to advance.`}
      aria-busy={saving}
      onClick={() => nextStatus && onAdvance(order, nextStatus)}
      onKeyDown={(event) => {
        if ((event.key === 'Enter' || event.key === ' ') && nextStatus) {
          event.preventDefault();
          onAdvance(order, nextStatus);
        }
      }}
    >
      <div className={`prepKdsTicketHead prepKdsTicketHead-${urgency}`}>
        <span className="prepKdsTicketCode">{orderNumber(order)}</span>
        <span className="prepKdsTicketTimer">
          {saving ? <RefreshCw className="spinIcon" size={18} /> : <Clock3 size={17} />}
          {formatTimer(elapsedMsFor(order, now))}
        </span>
      </div>

      <div className="prepKdsTicketBody">
        <div className="prepKdsTicketFulfillment">
          <FulfillmentIcon size={15} />
          <span>{fulfillmentLabel(order)}</span>
          <span className="prepKdsTicketReceived">{formatOrderTime(orderStartedAt(order))}</span>
        </div>

        {allergens.length > 0 && (
          <div className="prepKdsTicketAllergens" role="alert">
            <AlertTriangle size={15} />
            <span><strong>ALLERGEN</strong> {allergens.join(', ')}</span>
          </div>
        )}

        <div className="prepKdsTicketItems">
          {(order.items || []).map((item) => (
            <TicketItem key={item.id} order={order} item={item} onOpenRecipe={onOpenRecipe} />
          ))}
        </div>

        {order.customer_notes && (
          <div className="prepKdsTicketNote">
            <strong>NOTE</strong>
            <span>{order.customer_notes}</span>
          </div>
        )}
      </div>

      <div className={`prepKdsTicketStage prepKdsTicketStage-${order.status}`}>
        {STAGE_LABEL[order.status]}
      </div>
    </article>
  );
}

function CompletedTicket({ order }) {
  return (
    <article className="prepKdsTicket prepKdsTicket-done">
      <div className="prepKdsTicketHead prepKdsTicketHead-done">
        <span className="prepKdsTicketCode">{orderNumber(order)}</span>
        <span className="prepKdsDoneBadge"><Check size={14} /> Done</span>
      </div>

      <div className="prepKdsTicketBody">
        <div className="prepKdsTicketItems">
          {(order.items || []).map((item) => (
            <div className="prepKdsTicketItem prepKdsTicketItem-done" key={item.id}>
              <span className="prepKdsTicketQty">&times;{formatQuantity(item.quantity)}</span>
              <span className="prepKdsTicketItemBody">
                <span className="prepKdsTicketItemName">{item.product_name_snapshot || item.products?.name || 'Item'}</span>
              </span>
            </div>
          ))}
        </div>
        <span className="prepKdsCompletedAt">Completed {formatOrderTime(orderCompletedAt(order))} Cairo</span>
      </div>

      <div className="prepKdsTicketStage prepKdsTicketStage-completed">COMPLETED</div>
    </article>
  );
}

function PrepRecipeOverlay({ payload, now, onClose }) {
  const dialogRef = useRef(null);

  useEffect(() => {
    if (!payload) return undefined;

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

    const focusableSelector = [
      'button:not([disabled])',
      '[href]',
      'input:not([disabled])',
      'select:not([disabled])',
      'textarea:not([disabled])',
      '[tabindex]:not([tabindex="-1"])'
    ].join(',');

    dialog?.querySelector(focusableSelector)?.focus();

    function onKeyDown(event) {
      if (event.key === 'Escape') {
        event.preventDefault();
        onClose();
        return;
      }

      if (event.key !== 'Tab' || !dialog) return;

      const focusable = [...dialog.querySelectorAll(focusableSelector)]
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
  }, [payload?.order?.id, payload?.item?.id, onClose]);

  if (!payload) return null;

  const { order, item } = payload;
  const recipeItems = item.recipe_items || [];
  const modifications = modificationLines(item);
  const allergens = itemAllergens(item);

  return (
    <div className="prepKdsOverlay">
      <button className="prepKdsOverlayScrim" type="button" aria-label="Close recipe details" onClick={onClose} />
      <section
        ref={dialogRef}
        className="prepKdsRecipe"
        role="dialog"
        aria-modal="true"
        aria-labelledby="prep-recipe-title"
        tabIndex={-1}
      >
        <div className="prepKdsRecipeHead">
          <div>
            <span className="prepKdsRecipeEyebrow">{orderNumber(order)} / Recipe</span>
            <h2 id="prep-recipe-title">{item.product_name_snapshot || item.products?.name || 'Item'}</h2>
            <p>{formatQuantity(item.quantity)} x {variantLabel(item)}</p>
          </div>
          <button className="prepKdsClose" type="button" onClick={onClose}>
            <X size={21} />
            Close
          </button>
        </div>

        <div className="prepKdsRecipeContext">
          <span><Clock3 size={18} /> {formatTimer(elapsedMsFor(order, now))} elapsed</span>
          <span><MapPin size={18} /> {fulfillmentLabel(order)}</span>
        </div>

        {allergens.length > 0 && (
          <div className="prepKdsRecipeAlert" role="alert">
            <AlertTriangle size={24} />
            <span>
              <strong>ALLERGY WARNING</strong>
              {allergens.join(', ')}
            </span>
          </div>
        )}

        {modifications.length > 0 && (
          <section className="prepKdsRecipePanel prepKdsRecipeMods">
            <h3>Customer modifications</h3>
            <div>
              {modifications.map((line) => <strong key={line}>{line}</strong>)}
            </div>
          </section>
        )}

        <section className="prepKdsRecipePanel">
          <h3>Ingredients for this order</h3>
          {recipeItems.length > 0 ? (
            <div className="prepKdsIngredients">
              {recipeItems.map((recipeItem) => {
                const removed = isRecipeItemRemoved(item, recipeItem);
                const ingredientName = recipeItem.ingredients?.name
                  || recipeItem.ingredient_name_snapshot
                  || 'Ingredient';
                const ingredientAllergens = asStringList(recipeItem.ingredients?.allergen_flags);

                return (
                  <div className={`prepKdsIngredient ${removed ? 'prepKdsIngredient-removed' : ''}`} key={recipeItem.id}>
                    <span>
                      <strong>{ingredientName}</strong>
                      <small>
                        {removed
                          ? 'Removed from this order'
                          : [
                              recipeItem.is_optional ? 'Optional' : '',
                              recipeItem.is_customer_supplied || recipeItem.ingredients?.is_customer_supplied
                                ? 'Customer supplied'
                                : ''
                            ].filter(Boolean).join(' / ') || 'Base recipe'}
                      </small>
                      {ingredientAllergens.length > 0 && <em>Allergen: {ingredientAllergens.join(', ')}</em>}
                    </span>
                    <b>
                      {formatQuantity(scaledIngredientQuantity(item, recipeItem))}
                      {' '}
                      {recipeItem.unit || recipeItem.ingredients?.base_unit || ''}
                    </b>
                  </div>
                );
              })}
            </div>
          ) : (
            <div className="prepKdsRecipeEmpty">No recipe ingredients are recorded for this item.</div>
          )}
        </section>

        {item.recipe?.notes && (
          <section className="prepKdsRecipePanel">
            <h3>Preparation notes</h3>
            <p className="prepKdsPreparationNotes">{item.recipe.notes}</p>
          </section>
        )}

        {(item.additions || []).length > 0 && (
          <section className="prepKdsRecipePanel">
            <h3>Added extras</h3>
            <div className="prepKdsExtras">
              {item.additions.map((addition) => (
                <div key={addition.id}>
                  <strong>{addition.product_name_snapshot || addition.products?.name || 'Extra'}</strong>
                  <span>
                    {addition.variant_name_snapshot || 'Standard'}
                    {' / '}
                    x{formatQuantity(totalAdditionQuantity(item, addition))}
                  </span>
                </div>
              ))}
            </div>
          </section>
        )}

        {order.customer_notes && (
          <section className="prepKdsRecipePanel prepKdsRecipeOrderNote">
            <h3>Order note</h3>
            <p>{order.customer_notes}</p>
          </section>
        )}
      </section>
    </div>
  );
}

export default function PrepOrders({ user, onLogout }) {
  const [orders, setOrders] = useState([]);
  const [completedOrders, setCompletedOrders] = useState([]);
  const [filter, setFilter] = useState('active');
  const [location, setLocation] = useState(null);
  const [loading, setLoading] = useState(true);
  const [loadError, setLoadError] = useState('');
  const [connectionState, setConnectionState] = useState(
    typeof navigator !== 'undefined' && navigator.onLine === false ? 'offline' : 'reconnecting'
  );
  const [now, setNow] = useState(Date.now());
  const [savingOrderIds, setSavingOrderIds] = useState(new Set());
  const [highlightedOrderIds, setHighlightedOrderIds] = useState(new Set());
  const [recipePayload, setRecipePayload] = useState(null);
  const [toast, setToast] = useState(null);
  const [loggingOut, setLoggingOut] = useState(false);

  const mountedRef = useRef(true);
  const clockOffsetRef = useRef(0);
  const loadPromiseRef = useRef(null);
  const queuedRefreshRef = useRef(false);
  const knownOrderIdsRef = useRef(new Set());
  const hasLoadedOrdersRef = useRef(false);
  const refreshTimerRef = useRef(null);
  const queuedRefreshTimerRef = useRef(null);
  const highlightTimerRef = useRef(null);
  const filterRef = useRef(filter);

  useEffect(() => {
    filterRef.current = filter;
  }, [filter]);

  useEffect(() => {
    mountedRef.current = true;
    return () => {
      mountedRef.current = false;
    };
  }, []);

  const applyServerTime = useCallback((serverTime) => {
    const parsed = new Date(serverTime || '').getTime();
    if (!Number.isNaN(parsed)) {
      clockOffsetRef.current = parsed - Date.now();
      setNow(Date.now() + clockOffsetRef.current);
    }
  }, []);

  const loadLocation = useCallback(async () => {
    const payload = await api('/api/cart-operations/locations');
    if (!mountedRef.current) return null;

    applyServerTime(payload.server_time);
    const locations = payload.locations || [];
    const selectedLocation = locations.find((entry) => entry.id === payload.selected_location_id)
      || null;
    setLocation(selectedLocation);
    return selectedLocation;
  }, [applyServerTime]);

  const loadCompleted = useCallback(async () => {
    try {
      const payload = await api(`/api/cart-operations/orders?status_group=${COMPLETED_STATUS_GROUP}`);
      if (!mountedRef.current) return;

      applyServerTime(payload.server_time);
      const todayKey = cairoDayKey(Date.now() + clockOffsetRef.current);
      const rows = (payload.orders || [])
        .filter((order) => order.status === 'completed')
        .filter((order) => cairoDayKey(orderCompletedAt(order)) === todayKey)
        .sort((a, b) => (
          new Date(orderCompletedAt(b) || 0).getTime() - new Date(orderCompletedAt(a) || 0).getTime()
        ));
      setCompletedOrders(rows);
    } catch (error) {
      if (error.status === 401 || error.status === 403) return;
      // The completed list is secondary; keep the last known list on failure.
    }
  }, [applyServerTime]);

  const loadOrders = useCallback(async ({ initial = false } = {}) => {
    if (loadPromiseRef.current) {
      queuedRefreshRef.current = true;
      return loadPromiseRef.current;
    }

    if (initial) setLoading(true);

    const loadPromise = (async () => {
      try {
        const payload = await api(`/api/cart-operations/orders?status_group=${ACTIVE_STATUS_GROUP}`);
        if (!mountedRef.current) return;

        applyServerTime(payload.server_time);
        if (payload.location) setLocation(payload.location);

        const nextOrders = (payload.orders || [])
          .filter((order) => (
            ACTIVE_STATUSES.includes(order.status)
            && (!order.payment_status || order.payment_status === 'paid')
          ))
          .sort((a, b) => (
            new Date(orderStartedAt(a) || 0).getTime() - new Date(orderStartedAt(b) || 0).getTime()
          ));

        if (hasLoadedOrdersRef.current) {
          const newlyArrivedIds = nextOrders
            .filter((order) => order.status === 'confirmed' && !knownOrderIdsRef.current.has(order.id))
            .map((order) => order.id);

          if (newlyArrivedIds.length > 0) {
            setHighlightedOrderIds(new Set(newlyArrivedIds));
            window.clearTimeout(highlightTimerRef.current);
            highlightTimerRef.current = window.setTimeout(() => {
              if (mountedRef.current) setHighlightedOrderIds(new Set());
            }, 8000);
          }
        }

        knownOrderIdsRef.current = new Set(nextOrders.map((order) => order.id));
        hasLoadedOrdersRef.current = true;
        setOrders(nextOrders);
        setLoadError('');
      } catch (error) {
        if (mountedRef.current) {
          if (error.status === 401 || error.status === 403) {
            setOrders([]);
            setLocation(null);
            window.location.assign('/login');
            return;
          }
          setLoadError(error.message || 'Could not load the kitchen queue.');
        }
      } finally {
        if (mountedRef.current) setLoading(false);
      }
    })();

    loadPromiseRef.current = loadPromise;

    try {
      await loadPromise;
    } finally {
      loadPromiseRef.current = null;
      if (queuedRefreshRef.current && mountedRef.current) {
        queuedRefreshRef.current = false;
        window.clearTimeout(queuedRefreshTimerRef.current);
        queuedRefreshTimerRef.current = window.setTimeout(() => {
          queuedRefreshTimerRef.current = null;
          loadOrders();
        }, 0);
      }
    }

    return undefined;
  }, [applyServerTime]);

  const scheduleCanonicalRefresh = useCallback((delay = INVALIDATION_DEBOUNCE_MS) => {
    if (refreshTimerRef.current && delay > 0) return;
    window.clearTimeout(refreshTimerRef.current);
    refreshTimerRef.current = window.setTimeout(() => {
      refreshTimerRef.current = null;
      loadOrders();
      if (filterRef.current === 'completed') loadCompleted();
    }, delay);
  }, [loadOrders, loadCompleted]);

  const loadKitchen = useCallback(async () => {
    setLoading(true);
    setLoadError('');

    const results = await Promise.allSettled([
      loadLocation(),
      loadOrders({ initial: true }),
      loadCompleted()
    ]);

    if (!mountedRef.current) return;

    const locationResult = results[0];
    if (locationResult.status === 'rejected') {
      setLoadError(locationResult.reason?.message || 'Could not load the assigned prep location.');
    }
    setLoading(false);
  }, [loadLocation, loadOrders, loadCompleted]);

  useEffect(() => {
    loadKitchen();
  }, [loadKitchen]);

  useEffect(() => {
    const timer = window.setInterval(() => {
      setNow(Date.now() + clockOffsetRef.current);
    }, 1000);

    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    let active = true;
    let subscription;

    function handleSocketStatus(status) {
      if (!active) return;
      if (navigator.onLine === false || status?.feed === 'stopped') {
        setConnectionState('offline');
        return;
      }
      if (status?.connection === 'connected' && status?.feed === 'live') {
        setConnectionState('live');
        scheduleCanonicalRefresh(0);
        return;
      }
      setConnectionState('reconnecting');
    }

    try {
      subscription = connectPrepOrderSocket({
        onStatus: handleSocketStatus,
        onInvalidate: () => {
          if (active) scheduleCanonicalRefresh();
        }
      });
    } catch {
      handleSocketStatus({ connection: 'disconnected', feed: 'degraded' });
    }

    function onOffline() {
      if (active) setConnectionState('offline');
    }

    function onOnline() {
      if (!active) return;
      setConnectionState('reconnecting');
      scheduleCanonicalRefresh(0);
    }

    window.addEventListener('offline', onOffline);
    window.addEventListener('online', onOnline);

    return () => {
      active = false;
      window.removeEventListener('offline', onOffline);
      window.removeEventListener('online', onOnline);
      if (typeof subscription === 'function') subscription();
      else subscription?.disconnect?.();
    };
  }, [scheduleCanonicalRefresh]);

  useEffect(() => {
    if (connectionState === 'live' || navigator.onLine === false) return undefined;

    const timer = window.setInterval(() => {
      loadOrders();
      if (filterRef.current === 'completed') loadCompleted();
    }, DEGRADED_POLL_MS);
    return () => window.clearInterval(timer);
  }, [connectionState, loadOrders, loadCompleted]);

  useEffect(() => {
    if (!toast) return undefined;
    const timer = window.setTimeout(() => setToast(null), 4500);
    return () => window.clearTimeout(timer);
  }, [toast]);

  useEffect(() => {
    setRecipePayload((current) => {
      if (!current) return current;
      const latestOrder = orders.find((order) => order.id === current.order.id);
      const latestItem = latestOrder?.items?.find((item) => item.id === current.item.id);
      if (!latestOrder || !latestItem) return null;
      if (latestOrder === current.order && latestItem === current.item) return current;
      return { order: latestOrder, item: latestItem };
    });
  }, [orders]);

  useEffect(() => () => {
    window.clearTimeout(refreshTimerRef.current);
    window.clearTimeout(queuedRefreshTimerRef.current);
    window.clearTimeout(highlightTimerRef.current);
  }, []);

  const closeRecipe = useCallback(() => setRecipePayload(null), []);

  const openRecipe = useCallback((order, item) => setRecipePayload({ order, item }), []);

  const showCompleted = useCallback(() => {
    setFilter('completed');
    loadCompleted();
  }, [loadCompleted]);

  const stageCounts = useMemo(() => {
    const counts = { confirmed: 0, preparing: 0, ready: 0 };
    for (const order of orders) {
      if (counts[order.status] !== undefined) counts[order.status] += 1;
    }
    return counts;
  }, [orders]);

  async function advanceOrder(order, status) {
    if (savingOrderIds.has(order.id)) return;

    setSavingOrderIds((current) => new Set(current).add(order.id));
    setToast(null);

    try {
      await api(`/api/cart-operations/orders/${order.id}/status`, {
        method: 'PATCH',
        body: JSON.stringify({ status })
      });

      if (!mountedRef.current) return;

      if (status === 'completed') {
        setOrders((current) => current.filter((entry) => entry.id !== order.id));
        knownOrderIdsRef.current.delete(order.id);
        loadCompleted();
        setToast({ type: 'success', message: `${orderNumber(order)} completed.` });
      } else {
        setOrders((current) => current.map((entry) => (
          entry.id === order.id ? { ...entry, status } : entry
        )));
        setToast({
          type: 'success',
          message: status === 'ready'
            ? `${orderNumber(order)} is ready for handoff.`
            : `${orderNumber(order)} moved to Preparing.`
        });
      }

      setLoadError('');
    } catch (error) {
      if (!mountedRef.current) return;

      const conflict = /already|cannot move|conflict/i.test(error.message || '');
      setToast({
        type: 'error',
        message: conflict
          ? `${orderNumber(order)} was already updated on another screen.`
          : (error.message || 'Could not update this order.')
      });
    } finally {
      if (mountedRef.current) {
        setSavingOrderIds((current) => {
          const next = new Set(current);
          next.delete(order.id);
          return next;
        });
        scheduleCanonicalRefresh(0);
      }
    }
  }

  async function handleLogout() {
    if (loggingOut) return;
    setLoggingOut(true);

    try {
      await onLogout();
    } catch (error) {
      if (!mountedRef.current) return;
      setLoggingOut(false);
      setToast({ type: 'error', message: error.message || 'Could not log out.' });
    }
  }

  const connectionLabel = connectionCopy(connectionState);
  const ConnectionIcon = connectionState === 'live' ? Wifi : WifiOff;
  const messageIsError = toast ? toast.type === 'error' : Boolean(loadError);

  if (loading && !orders.length && !location) {
    return (
      <div className="prepKdsRoot prepKdsBoot">
        <div className="prepKdsBootCard">
          <ChefHat size={42} />
          <strong>Opening order display</strong>
          <span>Loading the assigned location and live queue...</span>
        </div>
      </div>
    );
  }

  if (!location) {
    return (
      <div className="prepKdsRoot prepKdsBoot">
        <div className="prepKdsBootCard prepKdsBootError">
          <MapPin size={42} />
          <strong>Prep location unavailable</strong>
          <span>{toast?.message || loadError || 'This prep employee does not have an active assigned cart location.'}</span>
          <div>
            <button type="button" onClick={loadKitchen}><RefreshCw size={18} /> Try again</button>
            <button type="button" onClick={handleLogout} disabled={loggingOut}><LogOut size={18} /> Logout</button>
          </div>
        </div>
      </div>
    );
  }

  const isCompleted = filter === 'completed';

  return (
    <div className="prepKdsRoot">
      <header className="prepKdsHeader">
        <div className="prepKdsHeaderLead">
          <div className="prepKdsHeaderLeadTop">
            <span className="prepKdsHeaderEyebrow">Fulfillment</span>
            <span className={`prepKdsConnection prepKdsConnection-${connectionState}`}>
              <ConnectionIcon size={13} />
              {connectionLabel}
            </span>
          </div>
          <h1 className="prepKdsLocationName">{location.name}</h1>
        </div>

        <div className="prepKdsFilter" role="tablist" aria-label="Order filter">
          <button
            type="button"
            role="tab"
            aria-selected={!isCompleted}
            className={!isCompleted ? 'prepKdsFilterActive' : ''}
            onClick={() => setFilter('active')}
          >
            Active &middot; {orders.length}
          </button>
          <button
            type="button"
            role="tab"
            aria-selected={isCompleted}
            className={isCompleted ? 'prepKdsFilterActive' : ''}
            onClick={showCompleted}
          >
            Completed &middot; {completedOrders.length}
          </button>
        </div>

        <div className="prepKdsStageCounts">
          <div className="prepKdsStageCount prepKdsStageCount-new">
            <strong>{stageCounts.confirmed}</strong>
            <small>New</small>
          </div>
          <div className="prepKdsStageCount prepKdsStageCount-preparing">
            <strong>{stageCounts.preparing}</strong>
            <small>Preparing</small>
          </div>
          <div className="prepKdsStageCount prepKdsStageCount-ready">
            <strong>{stageCounts.ready}</strong>
            <small>Ready</small>
          </div>
        </div>
      </header>

      {(toast || loadError) && (
        <div className={`prepKdsToast ${messageIsError ? 'prepKdsToast-error' : 'prepKdsToast-success'}`} role="status">
          <span>{toast?.message || loadError}</span>
          {loadError && <button type="button" onClick={() => loadOrders({ initial: true })}>Retry</button>}
          <button type="button" aria-label="Dismiss message" onClick={() => {
            setToast(null);
            setLoadError('');
          }}><X size={18} /></button>
        </div>
      )}

      <main className="prepKdsBoard">
        {!isCompleted && (
          orders.length === 0 ? (
            <div className="prepKdsEmpty">
              <ChefHat size={38} />
              <strong>No active orders</strong>
              <span>New orders will appear here automatically, in the order they arrive.</span>
            </div>
          ) : (
            <div className="prepKdsWall">
              {orders.map((order) => (
                <PrepTicket
                  key={order.id}
                  order={order}
                  now={now}
                  saving={savingOrderIds.has(order.id)}
                  highlighted={highlightedOrderIds.has(order.id)}
                  onAdvance={advanceOrder}
                  onOpenRecipe={openRecipe}
                />
              ))}
            </div>
          )
        )}

        {isCompleted && (
          completedOrders.length === 0 ? (
            <div className="prepKdsEmpty">
              <Check size={38} />
              <strong>No completed orders yet</strong>
              <span>Orders you finish will appear here for the rest of your shift.</span>
            </div>
          ) : (
            <div className="prepKdsWall">
              {completedOrders.map((order) => (
                <CompletedTicket key={order.id} order={order} />
              ))}
            </div>
          )
        )}
      </main>

      <nav className="prepKdsNav">
        <div className="prepKdsNavUser">
          <span className="prepKdsAvatar">{initialsFor(user?.name || user?.username)}</span>
          <span className="prepKdsNavUserCopy">
            <strong>{user?.name || user?.username || 'Employee'}</strong>
            <small>Station operator &middot; {location.name}</small>
          </span>
        </div>

        <div className="prepKdsNavClock">{cairoTimeFormatter.format(new Date(now))}</div>

        <button className="prepKdsLogout" type="button" onClick={handleLogout} disabled={loggingOut}>
          {loggingOut ? <RefreshCw size={17} className="spinIcon" /> : <Power size={17} />}
          Log Out
        </button>
      </nav>

      <PrepRecipeOverlay payload={recipePayload} now={now} onClose={closeRecipe} />
    </div>
  );
}
