import { useCallback, useEffect, useMemo, useRef, useState } from 'react';
import {
  AlertTriangle,
  Check,
  ChevronRight,
  ChefHat,
  Clock,
  Filter,
  MapPin,
  PackageCheck,
  Phone,
  Play,
  RefreshCw,
  ScanLine,
  Search,
  User,
  X
} from 'lucide-react';
import { api } from '../api/client.js';
import PickupScanner from '../components/PickupScanner.jsx';
import { money } from '../utils/format.js';

const AUTO_REFRESH_MS = 12000;
const ACTIVE_GROUP = 'active';

const FILTERS = [
  { key: 'active', label: 'Active', helper: 'Confirmed + Preparing + Ready' },
  { key: 'confirmed', label: 'Confirmed', helper: 'Waiting to start' },
  { key: 'preparing', label: 'Preparing', helper: 'Being made' },
  { key: 'ready', label: 'Ready', helper: 'Ready for pickup' },
  { key: 'picked_up', label: 'Picked Up', helper: 'Completed orders' }
];

const STATUS_LABELS = {
  confirmed: 'Confirmed',
  preparing: 'Preparing',
  ready: 'Ready',
  completed: 'Picked Up'
};

const PAYMENT_LABELS = {
  unpaid: 'Unpaid',
  pending: 'Pending',
  paid: 'Paid',
  failed: 'Failed',
  refunded: 'Refunded',
  partially_refunded: 'Partially Refunded'
};

function formatTime(value) {
  if (!value) return '-';
  return new Date(value).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
}

function formatDate(value) {
  if (!value) return '-';
  return new Date(value).toLocaleDateString([], { month: 'short', day: 'numeric', year: 'numeric' });
}

function formatFulfillment(order) {
  if (order.fulfillment_type === 'delivery_to_unit') return order.customer_address_snapshot || 'Delivery to unit';
  return 'Pickup at Cart';
}

function formatElapsed(value, now = Date.now()) {
  if (!value) return '-';
  const elapsedMs = Math.max(0, now - new Date(value).getTime());
  const minutes = Math.floor(elapsedMs / 60000);
  if (minutes < 1) return 'Just now';
  if (minutes < 60) return `${minutes} min ago`;
  const hours = Math.floor(minutes / 60);
  const remainingMinutes = minutes % 60;
  return remainingMinutes ? `${hours}h ${remainingMinutes}m ago` : `${hours}h ago`;
}

function formatQuantity(value) {
  const number = Number(value || 0);
  if (!Number.isFinite(number)) return '-';
  if (Math.abs(number - Math.round(number)) < 0.001) return String(Math.round(number));
  return number.toFixed(2).replace(/\.00$/, '').replace(/0$/, '');
}

function normalizeStatusClass(value) {
  return String(value || '').replaceAll('_', '-');
}

function orderNumberLabel(order) {
  return order.order_number || 'Draft order';
}

function itemSearchText(item) {
  return [
    item.product_name_snapshot,
    item.variant_name_snapshot,
    item.customization_summary,
    ...(item.removed_ingredients || []).map((row) => row.ingredient_name_snapshot),
    ...(item.additions || []).map((row) => row.product_name_snapshot)
  ].filter(Boolean).join(' ');
}

function orderMatchesSearch(order, search) {
  const term = search.trim().toLowerCase();
  if (!term) return true;
  const haystack = [
    order.order_number,
    order.customer?.name,
    order.customer?.phone,
    order.customer_phone_snapshot,
    order.customer_notes,
    formatFulfillment(order),
    ...(order.items || []).map(itemSearchText)
  ].filter(Boolean).join(' ').toLowerCase();

  return haystack.includes(term);
}

function modificationLines(item) {
  const lines = [];

  for (const removed of item.removed_ingredients || []) {
    if (removed.ingredient_name_snapshot) lines.push(`Remove ${removed.ingredient_name_snapshot}`);
  }

  for (const addition of item.additions || []) {
    const quantity = Number(addition.quantity_per_parent || 1);
    const suffix = quantity > 1 ? ` x${quantity}` : '';
    if (addition.product_name_snapshot) lines.push(`Add ${addition.product_name_snapshot}${suffix}`);
  }

  if (!lines.length && item.customization_summary) lines.push(item.customization_summary);

  return [...new Set(lines.filter(Boolean))];
}

function itemHasAllergyIndicator(item) {
  return (item.recipe_items || []).some((row) => row.ingredients?.allergen_flags?.length);
}

function statusAction(order) {
  if (order.status === 'confirmed') return { status: 'preparing', label: 'Start Preparing', icon: Play };
  if (order.status === 'preparing') return { status: 'ready', label: 'Ready for Pickup', icon: Check };

  if (order.status === 'ready') {
    // A cart pickup is released by scanning the customer's code — the backend
    // refuses `completed` for one of these, so there is no button that could
    // do it. A delivery still leaves on the runner's word.
    return order.fulfillment_type === 'pickup_at_cart'
      ? { scan: true, status: 'completed', label: 'Scan to Hand Over', icon: ScanLine }
      : { status: 'completed', label: 'Mark Handed Over', icon: PackageCheck };
  }

  return null;
}

function variantLabel(item) {
  return item.variant_name_snapshot || (item.serving_count > 1 ? `${item.serving_count} servings` : 'Standard');
}

function selectedFilterLabel(filterKey) {
  return FILTERS.find((filter) => filter.key === filterKey)?.label || 'Active';
}

function updateSelectedOrder(currentOrderId, orders) {
  if (!orders.length) return null;
  return orders.find((order) => order.id === currentOrderId) || orders[0];
}

function toastClass(type) {
  return type === 'error' ? 'cartOpsToast error' : 'cartOpsToast success';
}

function prepStatusLabel(status) {
  return String(status || 'queued').replaceAll('_', ' ');
}

function isItemRemoved(item, recipeItem) {
  return (item.removed_ingredients || []).some((removed) => {
    return removed.recipe_item_id === recipeItem.id || removed.ingredient_id === recipeItem.ingredient_id;
  });
}

function multipliedIngredientQuantity({ recipeItem, item }) {
  const recipeYield = Math.max(Number(item.recipe?.yield_servings || 1), 1);
  const servingCount = Math.max(Number(item.serving_count || 1), 1);
  const itemQuantity = Math.max(Number(item.quantity || 1), 1);
  return (Number(recipeItem.quantity || 0) / recipeYield) * servingCount * itemQuantity;
}

function componentTotal(component, item) {
  return Number(component.quantity_per_order_item_unit || 0) * Number(item.quantity || 1);
}

function OrderItemRow({ item, onOpenRecipe }) {
  const mods = modificationLines(item);

  return <button className="orderItemRow" type="button" onClick={onOpenRecipe}>
    <div className="itemQty">{item.quantity}</div>
    <div className="itemThumb">
      {item.product_image_url ? <img src={item.product_image_url} alt="" /> : <ChefHat size={20} />}
    </div>
    <div className="itemCopy">
      <div className="itemTitleLine">
        <b>{item.product_name_snapshot}</b>
        {itemHasAllergyIndicator(item) && <span className="allergyFlag"><AlertTriangle size={12} /> Allergy</span>}
      </div>
      <span>{variantLabel(item)}</span>
      {mods.length > 0 && <div className="modLines">
        {mods.map((line) => <small key={line}>• {line}</small>)}
      </div>}
    </div>
    <span className={`prepBadge prep-${normalizeStatusClass(item.prep_status)}`}>{prepStatusLabel(item.prep_status)}</span>
    <ChevronRight size={18} />
  </button>;
}

function OrderCard({ order, selected, highlighted, now, saving, onSelect, onStatus, onScan, onOpenRecipe }) {
  const action = statusAction(order);
  const ActionIcon = action?.icon;

  return <article className={`opsOrderCard statusLeft-${normalizeStatusClass(order.status)} ${selected ? 'selected' : ''} ${highlighted ? 'highlighted' : ''}`} onClick={onSelect}>
    <div className="opsOrderCardTop">
      <div>
        <b>{orderNumberLabel(order)}</b>
        <span>{formatTime(order.confirmed_at || order.created_at)} · {formatElapsed(order.confirmed_at || order.created_at, now)}</span>
      </div>
      <div className="orderCardBadges">
        <span className={`statusPill status-${normalizeStatusClass(order.status)}`}>{STATUS_LABELS[order.status] || order.status}</span>
        <span className={`statusPill status-${normalizeStatusClass(order.payment_status)}`}>{PAYMENT_LABELS[order.payment_status] || order.payment_status}</span>
      </div>
    </div>

    <div className="orderCardMeta">
      <span><User size={14} /> {order.customer?.name || 'Walk-in Customer'}</span>
      <span><MapPin size={14} /> {formatFulfillment(order)}</span>
      <span>{order.item_count} items</span>
      <b>{money(order.total_amount)}</b>
    </div>

    <div className="orderCardItems">
      {(order.items || []).map((item) => <OrderItemRow
        key={item.id}
        item={item}
        onOpenRecipe={(event) => {
          event.stopPropagation();
          onOpenRecipe(order, item);
        }}
      />)}
    </div>

    {order.customer_notes && <div className="orderNoteCompact">Note: {order.customer_notes}</div>}

    {action && <div className="orderCardAction">
      <button
        className={`primary orderActionButton action-${action.status}`}
        type="button"
        disabled={saving === order.id}
        onClick={(event) => {
          event.stopPropagation();
          if (action.scan) onScan(order);
          else onStatus(order, action.status);
        }}
      >
        {saving === order.id ? <RefreshCw size={18} className="spinIcon" /> : <ActionIcon size={18} />}
        {action.label}
      </button>
    </div>}
  </article>;
}

function OrderDetail({ order, now, saving, onStatus, onScan, onOpenRecipe }) {
  if (!order) {
    return <aside className="orderDetailPane emptyState">
      <ChefHat size={38} />
      <b>Select an order</b>
      <span>Order details, items, notes, and the next action will appear here.</span>
    </aside>;
  }

  const action = statusAction(order);
  const ActionIcon = action?.icon;

  return <aside className="orderDetailPane">
    <div className="detailHeader">
      <div>
        <h2>{orderNumberLabel(order)}</h2>
        <span>{STATUS_LABELS[order.status] || order.status} · {formatElapsed(order.confirmed_at || order.created_at, now)}</span>
      </div>
      <span className={`statusPill status-${normalizeStatusClass(order.status)}`}>{STATUS_LABELS[order.status] || order.status}</span>
    </div>

    <div className="detailCustomerGrid">
      <div>
        <span className="detailLabel"><User size={15} /> Customer</span>
        <b>{order.customer?.name || 'Walk-in Customer'}</b>
        {order.customer?.phone && <small><Phone size={13} /> {order.customer.phone}</small>}
      </div>
      <div>
        <span className="detailLabel"><Clock size={15} /> Fulfillment</span>
        <b>{formatFulfillment(order)}</b>
        <small>{order.requested_fulfillment_at ? `${formatDate(order.requested_fulfillment_at)}, ${formatTime(order.requested_fulfillment_at)}` : 'ASAP'}</small>
      </div>
    </div>

    <div className="detailTotals">
      <span><small>Items</small><b>{order.item_count}</b></span>
      <span><small>Subtotal</small><b>{money(order.subtotal_ex_vat)}</b></span>
      <span><small>VAT</small><b>{money(order.vat_amount)}</b></span>
      <span><small>Total</small><b>{money(order.total_amount)}</b></span>
    </div>

    <div className="detailItemsBlock">
      <div className="detailBlockTitle">Items</div>
      {(order.items || []).map((item) => <OrderItemRow
        key={item.id}
        item={item}
        onOpenRecipe={() => onOpenRecipe(order, item)}
      />)}
    </div>

    {order.customer_notes && <div className="orderNoteFull">
      <b>Customer note</b>
      <p>{order.customer_notes}</p>
    </div>}

    {action && <div className="detailStickyAction">
      <button
        className={`primary detailActionButton action-${action.status}`}
        type="button"
        disabled={saving === order.id}
        onClick={() => (action.scan ? onScan(order) : onStatus(order, action.status))}
      >
        {saving === order.id ? <RefreshCw size={20} className="spinIcon" /> : <ActionIcon size={20} />}
        {action.label}
      </button>
    </div>}
  </aside>;
}

function RecipeSheet({ payload, onClose }) {
  if (!payload) return null;

  const { order, item } = payload;
  const removedNames = new Set((item.removed_ingredients || []).map((row) => row.ingredient_name_snapshot).filter(Boolean));
  const mods = modificationLines(item);
  const recipeItems = item.recipe_items || [];
  const components = item.inventory_components || [];

  return <div className="recipeOverlay" role="dialog" aria-modal="true">
    <button className="recipeScrim" type="button" aria-label="Close recipe" onClick={onClose} />
    <aside className="recipeSheet">
      <div className="recipeSheetHead">
        <div>
          <span className="eyebrow">Recipe</span>
          <h2>{item.product_name_snapshot}</h2>
          <p>{orderNumberLabel(order)} · Quantity {item.quantity} · {variantLabel(item)}</p>
        </div>
        <button className="recipeClose" type="button" onClick={onClose}><X size={20} /> Close</button>
      </div>

      <div className="recipeHero">
        <div className="recipeImageBox">
          {item.product_image_url ? <img src={item.product_image_url} alt="" /> : <ChefHat size={28} />}
        </div>
        <div>
          <b>Version {item.recipe?.version || '-'}</b>
          <span>Yield: {item.recipe?.yield_servings || 1} serving{Number(item.recipe?.yield_servings || 1) === 1 ? '' : 's'}</span>
          {item.recipe?.notes && <p>{item.recipe.notes}</p>}
        </div>
      </div>

      {mods.length > 0 && <section className="recipePanel modsPanel">
        <h3>Customer modifications</h3>
        {mods.map((line) => <span key={line}>• {line}</span>)}
      </section>}

      <section className="recipePanel">
        <h3>Ingredient list</h3>
        {recipeItems.length ? <div className="recipeRows">
          {recipeItems.map((recipeItem) => {
            const removed = isItemRemoved(item, recipeItem);
            const ingredientName = recipeItem.ingredients?.name || recipeItem.ingredient_name_snapshot || removedNames.has(recipeItem.ingredient_name_snapshot) || 'Ingredient';
            return <div className={`recipeIngredientRow ${removed ? 'removed' : ''}`} key={recipeItem.id}>
              <div>
                <b>{ingredientName}</b>
                <span>
                  {recipeItem.is_optional && 'Optional'}
                  {recipeItem.is_optional && (recipeItem.is_customer_supplied || recipeItem.ingredients?.is_customer_supplied) && ' · '}
                  {(recipeItem.is_customer_supplied || recipeItem.ingredients?.is_customer_supplied) && 'Customer supplied'}
                  {!recipeItem.is_optional && !(recipeItem.is_customer_supplied || recipeItem.ingredients?.is_customer_supplied) && 'Base recipe'}
                </span>
              </div>
              <strong>{formatQuantity(multipliedIngredientQuantity({ recipeItem, item }))} {recipeItem.unit}</strong>
            </div>;
          })}
        </div> : <div className="empty">No recipe items found.</div>}
      </section>

      {components.length > 0 && <section className="recipePanel">
        <h3>Prepared quantity after modifications</h3>
        <div className="recipeRows compact">
          {components.map((component) => <div className="recipeIngredientRow" key={component.id}>
            <div>
              <b>{component.ingredient_name_snapshot}</b>
              <span>{component.source_type === 'addon_recipe' ? 'Added extra' : 'Base recipe'}</span>
            </div>
            <strong>{formatQuantity(componentTotal(component, item))} {component.unit_snapshot || ''}</strong>
          </div>)}
        </div>
      </section>}

      {item.additions?.length > 0 && <section className="recipePanel">
        <h3>Added extras</h3>
        {item.additions.map((addition) => <div className="addonRecipeLine" key={addition.id}>
          <b>{addition.product_name_snapshot}</b>
          <span>{addition.variant_name_snapshot || 'Standard'} · x{addition.quantity_per_parent || 1}</span>
        </div>)}
      </section>}
    </aside>
  </div>;
}

export default function Orders({ selectedLocationId, selectedLocation, locationLoading, locationError }) {
  const [orders, setOrders] = useState([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');
  const [statusFilter, setStatusFilter] = useState(ACTIVE_GROUP);
  const [search, setSearch] = useState('');
  const [autoRefresh, setAutoRefresh] = useState(true);
  const [now, setNow] = useState(Date.now());
  const [selectedOrderId, setSelectedOrderId] = useState('');
  const [savingOrderId, setSavingOrderId] = useState('');
  const [toast, setToast] = useState(null);
  const [recipePayload, setRecipePayload] = useState(null);
  const [scanningOrder, setScanningOrder] = useState(null);
  const [highlightedOrderIds, setHighlightedOrderIds] = useState(new Set());
  const [newOrdersNotice, setNewOrdersNotice] = useState(false);
  const knownOrderIdsRef = useRef(new Set());
  const hasLoadedRef = useRef(false);
  const queueRef = useRef(null);
  const savingRef = useRef(false);

  const loadOrders = useCallback(async ({ silent = false } = {}) => {
    if (!selectedLocationId) return;
    if (savingRef.current && silent) return;

    if (!silent) setLoading(true);
    setError('');

    try {
      const payload = await api(`/api/cart-operations/orders?location_id=${encodeURIComponent(selectedLocationId)}&status_group=${encodeURIComponent(statusFilter)}`);
      const nextOrders = payload.orders || [];
      const nextIds = new Set(nextOrders.map((order) => order.id));
      const oldIds = knownOrderIdsRef.current;

      if (hasLoadedRef.current) {
        const newConfirmedIds = nextOrders
          .filter((order) => order.status === 'confirmed' && !oldIds.has(order.id))
          .map((order) => order.id);

        if (newConfirmedIds.length) {
          setHighlightedOrderIds(new Set(newConfirmedIds));
          window.setTimeout(() => setHighlightedOrderIds(new Set()), 4200);

          if ((queueRef.current?.scrollTop || 0) > 140) {
            setNewOrdersNotice(true);
          }
        }
      }

      knownOrderIdsRef.current = nextIds;
      hasLoadedRef.current = true;
      setOrders(nextOrders);
      setSelectedOrderId((current) => updateSelectedOrder(current, nextOrders)?.id || '');
    } catch (err) {
      setError(err.message || 'Could not load orders.');
    } finally {
      if (!silent) setLoading(false);
    }
  }, [selectedLocationId, statusFilter]);

  useEffect(() => {
    setOrders([]);
    setSelectedOrderId('');
    setError('');
    knownOrderIdsRef.current = new Set();
    hasLoadedRef.current = false;
    if (selectedLocationId) loadOrders();
  }, [selectedLocationId, statusFilter, loadOrders]);

  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 30000);
    return () => window.clearInterval(timer);
  }, []);

  useEffect(() => {
    if (!autoRefresh || !selectedLocationId) return undefined;
    const timer = window.setInterval(() => loadOrders({ silent: true }), AUTO_REFRESH_MS);
    return () => window.clearInterval(timer);
  }, [autoRefresh, selectedLocationId, loadOrders]);

  async function updateOrderStatus(order, status) {
    savingRef.current = true;
    setSavingOrderId(order.id);
    setToast(null);

    try {
      await api(`/api/cart-operations/orders/${order.id}/status`, {
        method: 'PATCH',
        body: JSON.stringify({ status })
      });
      setToast({ type: 'success', message: `Order ${order.order_number || ''} updated.` });
      await loadOrders({ silent: true });
    } catch (err) {
      setToast({ type: 'error', message: 'Couldn’t update order. Try again.' });
    } finally {
      setSavingOrderId('');
      savingRef.current = false;
    }
  }

  async function handleHandedOver({ order_number, method, logged }) {
    setScanningOrder(null);
    setToast({
      type: 'success',
      message: logged
        ? `Order ${order_number} handed over${method === 'override' ? ' by override' : ''}.`
        : `Order ${order_number} handed over, but the handoff log did not save. Tell a supervisor.`
    });
    await loadOrders({ silent: true });
  }

  const filteredOrders = useMemo(() => {
    return orders.filter((order) => orderMatchesSearch(order, search));
  }, [orders, search]);

  const counts = useMemo(() => {
    return orders.reduce((acc, order) => {
      acc.active += ['confirmed', 'preparing', 'ready'].includes(order.status) ? 1 : 0;
      if (order.status === 'completed') acc.picked_up += 1;
      if (acc[order.status] !== undefined) acc[order.status] += 1;
      return acc;
    }, { active: 0, confirmed: 0, preparing: 0, ready: 0, picked_up: 0 });
  }, [orders]);

  const selectedOrder = useMemo(() => {
    return filteredOrders.find((order) => order.id === selectedOrderId) || filteredOrders[0] || null;
  }, [filteredOrders, selectedOrderId]);

  function openRecipe(order, item) {
    setRecipePayload({ order, item });
  }

  if (locationLoading) {
    return <div className="cartOpsPage"><div className="cartOpsLoading">Loading cart operations…</div></div>;
  }

  if (locationError) {
    return <div className="cartOpsPage"><div className="error">{locationError}</div></div>;
  }

  if (!selectedLocationId) {
    return <div className="cartOpsPage"><div className="emptyState fullPage"><MapPin size={38} /><b>No cart location selected</b><span>Select an active cart location to view orders.</span></div></div>;
  }

  return <div className="cartOpsPage">
    <header className="cartOpsHeader">
      <div className="cartIdentity">
        <div className="cartIcon"><MapPin size={22} /></div>
        <div>
          <b>{selectedLocation?.name || 'Cart Operations'}</b>
          <span className={selectedLocation?.is_active === false ? 'offlineDot' : 'onlineDot'}>{selectedLocation?.is_active === false ? 'Offline' : 'Online'}</span>
        </div>
      </div>

      <div className="headerClock">
        <b>{new Date(now).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })}</b>
        <span>{formatDate(now)}</span>
      </div>

      <div className="cartOpsSearch">
        <Search size={18} />
        <input value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Search order #, customer, or item…" />
      </div>

      <button className="filterButton" type="button" aria-label="Selected filter"><Filter size={18} /> {selectedFilterLabel(statusFilter)}</button>
      <button className="refreshButton" type="button" disabled={loading} onClick={() => loadOrders()}><RefreshCw size={18} className={loading ? 'spinIcon' : ''} /> Refresh</button>
    </header>

    <div className="cartOpsControls">
      <div className="statusSegments">
        {FILTERS.map((filter) => <button
          key={filter.key}
          className={statusFilter === filter.key ? 'active' : ''}
          type="button"
          onClick={() => setStatusFilter(filter.key)}
        >
          <b>{filter.label}</b>
          <span>{counts[filter.key] ?? 0}</span>
        </button>)}
      </div>
      <label className="autoRefreshToggle">
        <span>Auto refresh</span>
        <input type="checkbox" checked={autoRefresh} onChange={(event) => setAutoRefresh(event.target.checked)} />
      </label>
    </div>

    {toast && <div className={toastClass(toast.type)}>{toast.message}</div>}
    {error && <div className="cartOpsToast error">{error}</div>}

    <div className="cartOpsBody">
      <section className="orderQueuePane">
        <div className="queueHead">
          <div>
            <h2>Orders</h2>
            <span>Oldest confirmed first</span>
          </div>
          <button type="button" onClick={() => loadOrders({ silent: true })}><RefreshCw size={16} /> Sync</button>
        </div>

        {newOrdersNotice && <button className="newOrdersPill" type="button" onClick={() => {
          queueRef.current?.scrollTo({ top: 0, behavior: 'smooth' });
          setNewOrdersNotice(false);
        }}>New orders available</button>}

        <div className="orderQueueList" ref={queueRef}>
          {loading && !orders.length && <div className="cartOpsLoading">Loading orders…</div>}
          {!loading && !filteredOrders.length && <div className="emptyState queueEmpty"><ChefHat size={34} /><b>No orders here</b><span>There are no {selectedFilterLabel(statusFilter).toLowerCase()} orders for this cart.</span></div>}
          {filteredOrders.map((order) => <OrderCard
            key={order.id}
            order={order}
            selected={selectedOrder?.id === order.id}
            highlighted={highlightedOrderIds.has(order.id)}
            now={now}
            saving={savingOrderId}
            onSelect={() => setSelectedOrderId(order.id)}
            onStatus={updateOrderStatus}
            onScan={setScanningOrder}
            onOpenRecipe={openRecipe}
          />)}
        </div>
      </section>

      <OrderDetail
        order={selectedOrder}
        now={now}
        saving={savingOrderId}
        onStatus={updateOrderStatus}
        onScan={setScanningOrder}
        onOpenRecipe={openRecipe}
      />
    </div>

    <RecipeSheet payload={recipePayload} onClose={() => setRecipePayload(null)} />

    {scanningOrder && <PickupScanner
      order={scanningOrder}
      onClose={() => setScanningOrder(null)}
      onHandedOver={handleHandedOver}
    />}
  </div>;
}
