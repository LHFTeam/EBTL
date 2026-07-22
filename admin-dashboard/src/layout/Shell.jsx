import { useEffect, useMemo, useState } from 'react';
import { BarChart3, ChevronLeft, ChevronRight, LogOut, MapPin } from 'lucide-react';
import { api } from '../api/client.js';
import { cartOperationsRoles, navigationSections, tabs } from '../config/navigation.jsx';
import Cocktails from '../pages/Cocktails.jsx';
import AdditionalProducts from '../pages/AdditionalProducts.jsx';
import Liquors from '../pages/Liquors.jsx';
import Shop from '../pages/Shop.jsx';
import Dashboard from '../pages/Dashboard.jsx';
import Employees from '../pages/Employees.jsx';
import Ingredients from '../pages/Ingredients.jsx';
import Inventory from '../pages/Inventory.jsx';
import Locations from '../pages/Locations.jsx';
import Orders from '../pages/Orders.jsx';
import Transfers from '../pages/Transfers.jsx';

const CART_LOCATION_STORAGE_KEY = 'ebtl.cart_operations.location_id';

function canAccessTab(access, key) {
  return access.includes('*') || access.includes(key);
}

function sectionIsAllowedForRole(section, role) {
  return !section.allowedRoles || section.allowedRoles.includes(role);
}

export default function Shell({ user, access, onLogout }) {
  const allowedSections = useMemo(() => {
    return navigationSections
      .filter((section) => sectionIsAllowedForRole(section, user.role))
      .map((section) => ({
        ...section,
        tabs: section.tabs.filter((tab) => canAccessTab(access, tab.key))
      }))
      .filter((section) => section.tabs.length > 0);
  }, [access, user.role]);

  const allowedTabs = useMemo(() => allowedSections.flatMap((section) => section.tabs), [allowedSections]);
  const [active, setActive] = useState(allowedTabs[0]?.key || 'dashboard');
  const [sidebarCollapsed, setSidebarCollapsed] = useState(false);
  const [cartLocationState, setCartLocationState] = useState({
    loading: false,
    error: '',
    locations: [],
    selectedLocationId: '',
    canSwitchLocations: false
  });

  const activeTab = tabs.find((tab) => tab.key === active) || allowedTabs[0];
  const ActiveIcon = activeTab?.icon || BarChart3;
  const isCartOperationsUser = cartOperationsRoles.includes(user.role) && canAccessTab(access, 'orders');
  const selectedCartLocation = cartLocationState.locations.find((location) => location.id === cartLocationState.selectedLocationId) || null;

  useEffect(() => {
    if (!allowedTabs.some((tab) => tab.key === active)) {
      setActive(allowedTabs[0]?.key || 'dashboard');
    }
  }, [active, allowedTabs]);

  useEffect(() => {
    if (!isCartOperationsUser) return undefined;

    let cancelled = false;
    setCartLocationState((state) => ({ ...state, loading: true, error: '' }));

    api('/api/cart-operations/locations')
      .then((payload) => {
        if (cancelled) return;

        const locations = payload.locations || [];
        const storedLocationId = window.localStorage.getItem(CART_LOCATION_STORAGE_KEY) || '';
        const storedLocationIsValid = payload.can_switch_locations && locations.some((location) => location.id === storedLocationId);
        const selectedLocationId = storedLocationIsValid
          ? storedLocationId
          : (payload.selected_location_id || locations[0]?.id || '');

        if (selectedLocationId) {
          window.localStorage.setItem(CART_LOCATION_STORAGE_KEY, selectedLocationId);
        }

        setCartLocationState({
          loading: false,
          error: '',
          locations,
          selectedLocationId,
          canSwitchLocations: Boolean(payload.can_switch_locations)
        });
      })
      .catch((error) => {
        if (cancelled) return;
        setCartLocationState({
          loading: false,
          error: error.message,
          locations: [],
          selectedLocationId: '',
          canSwitchLocations: false
        });
      });

    return () => {
      cancelled = true;
    };
  }, [isCartOperationsUser]);

  function selectCartLocation(locationId) {
    setCartLocationState((state) => ({ ...state, selectedLocationId: locationId }));
    if (locationId) window.localStorage.setItem(CART_LOCATION_STORAGE_KEY, locationId);
  }

  return <div className={`appShell ${sidebarCollapsed ? 'sidebarCollapsed' : ''}`}>
    <aside>
      <div className="sideTop">
        <div className="sideBrand"><span>EBTL</span><small>Operations</small></div>
        <button className="sidebarToggle" type="button" onClick={() => setSidebarCollapsed((value) => !value)} aria-label={sidebarCollapsed ? 'Expand sidebar' : 'Collapse sidebar'}>
          {sidebarCollapsed ? <ChevronRight size={18} /> : <ChevronLeft size={18} />}
        </button>
      </div>

      <nav className="sideNav">
        {allowedSections.map((section) => <div className="navSection" key={section.key}>
          <div className="navSectionLabel">{section.label}</div>

          {section.key === 'cart-operations' && cartLocationState.canSwitchLocations && !sidebarCollapsed && <label className="cartLocationSwitcher">
            <span><MapPin size={14} /> Cart location</span>
            <select
              value={cartLocationState.selectedLocationId}
              onChange={(event) => selectCartLocation(event.target.value)}
              disabled={cartLocationState.loading || !cartLocationState.locations.length}
            >
              {cartLocationState.locations.map((location) => <option key={location.id} value={location.id}>{location.name}</option>)}
            </select>
            {cartLocationState.error && <small>{cartLocationState.error}</small>}
          </label>}

          {section.tabs.map((tab) => {
            const Icon = tab.icon;
            return <button
              key={tab.key}
              className={active === tab.key ? 'active' : ''}
              onClick={() => setActive(tab.key)}
              title={sidebarCollapsed ? tab.label : undefined}
            >
              <Icon size={18} />
              <span>{tab.label}</span>
            </button>;
          })}
        </div>)}
      </nav>

      <div className="userBox">
        <b>{user.name}</b>
        <span>{user.role}</span>
        {selectedCartLocation && <small>{selectedCartLocation.name}</small>}
        <button onClick={onLogout}><LogOut size={16} /><span>Logout</span></button>
      </div>
    </aside>

    <main className={activeTab?.usesCustomHeader ? 'mainNoPad' : ''}>
      {!activeTab?.usesCustomHeader && <header>
        <div>
          <h1><ActiveIcon size={24} /> {activeTab?.label}</h1>
          <p>Central warehouse + compound beach carts</p>
        </div>
      </header>}
      {active === 'dashboard' && <Dashboard />}
      {active === 'orders' && <Orders
        selectedLocationId={cartLocationState.selectedLocationId}
        selectedLocation={selectedCartLocation}
        locationLoading={cartLocationState.loading}
        locationError={cartLocationState.error}
        canSwitchLocations={cartLocationState.canSwitchLocations}
      />}
      {active === 'inventory' && <Inventory />}
      {active === 'transfers' && <Transfers />}
      {active === 'ingredients' && <Ingredients />}
      {active === 'cocktails' && <Cocktails />}
      {active === 'additional-products' && <AdditionalProducts />}
      {active === 'liquors' && <Liquors />}
      {active === 'shop' && <Shop />}
      {active === 'locations' && <Locations />}
      {active === 'employees' && <Employees />}
    </main>
  </div>;
}
