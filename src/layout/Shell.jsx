import { useState } from 'react';
import { BarChart3 } from 'lucide-react';
import { tabs } from '../config/navigation.jsx';
import Cocktails from '../pages/Cocktails.jsx';
import Liquors from '../pages/Liquors.jsx';
import Dashboard from '../pages/Dashboard.jsx';
import Employees from '../pages/Employees.jsx';
import Ingredients from '../pages/Ingredients.jsx';
import Inventory from '../pages/Inventory.jsx';
import Locations from '../pages/Locations.jsx';
import Orders from '../pages/Orders.jsx';
import Transfers from '../pages/Transfers.jsx';

export default function Shell({ user, access, onLogout }) {
  const allowedTabs = tabs.filter(t => access.includes('*') || access.includes(t.key));
  const [active, setActive] = useState(allowedTabs[0]?.key || 'dashboard');
  const ActiveIcon = tabs.find(t => t.key === active)?.icon || BarChart3;
  return <div className="appShell"><aside>
    <div className="sideBrand"><span>EBTL</span><small>Operations</small></div>
    <nav>{allowedTabs.map(t => { const Icon = t.icon; return <button key={t.key} className={active === t.key ? 'active' : ''} onClick={() => setActive(t.key)}><Icon size={18} />{t.label}</button>; })}</nav>
    <div className="userBox"><b>{user.name}</b><span>{user.role}</span><button onClick={onLogout}>Logout</button></div>
  </aside><main>
    <header><div><h1><ActiveIcon size={24} /> {tabs.find(t => t.key === active)?.label}</h1><p>Central warehouse + compound beach carts</p></div></header>
    {active === 'dashboard' && <Dashboard />}
    {active === 'orders' && <Orders />}
    {active === 'inventory' && <Inventory />}
    {active === 'transfers' && <Transfers />}
    {active === 'ingredients' && <Ingredients />}
    {active === 'cocktails' && <Cocktails />}
    {active === 'liquors' && <Liquors />}
    {active === 'locations' && <Locations />}
    {active === 'employees' && <Employees />}
  </main></div>;
}
