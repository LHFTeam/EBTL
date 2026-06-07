import { BarChart3, Boxes, ClipboardList, MapPin, Martini, ShoppingBag, Truck, Users, FlaskConical, Wine } from 'lucide-react';

export const tabs = [
  { key: 'dashboard', label: 'Dashboard', icon: BarChart3 },
  { key: 'orders', label: 'Orders', icon: ClipboardList },
  { key: 'inventory', label: 'Inventory', icon: Boxes },
  { key: 'transfers', label: 'Transfers', icon: Truck },
  { key: 'ingredients', label: 'Ingredients', icon: FlaskConical },
  { key: 'cocktails', label: 'Cocktails', icon: Martini },
  { key: 'additional-products', label: 'Additional Products', icon: ShoppingBag },
  { key: 'liquors', label: 'Liquors', icon: Wine },
  { key: 'shop', label: 'Shop', icon: ShoppingBag },
  { key: 'locations', label: 'Locations', icon: MapPin },
  { key: 'employees', label: 'Employees', icon: Users }
];
