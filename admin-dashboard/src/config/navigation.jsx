import {
  BarChart3,
  Boxes,
  ClipboardList,
  FlaskConical,
  Gift,
  LineChart,
  MapPin,
  Martini,
  ShoppingBag,
  Ticket,
  Truck,
  Users,
  Wine
} from 'lucide-react';

export const cartOperationsRoles = ['prep', 'cart_operator', 'supervisor', 'manager', 'admin'];

export const navigationSections = [
  {
    key: 'overview',
    label: 'Overview',
    tabs: [
      { key: 'dashboard', label: 'Dashboard', icon: BarChart3 },
      { key: 'analytics', label: 'Analytics', icon: LineChart }
    ]
  },
  {
    key: 'cart-operations',
    label: 'Cart Operations',
    allowedRoles: cartOperationsRoles,
    tabs: [
      { key: 'orders', label: 'Orders', icon: ClipboardList, usesCustomHeader: true }
    ]
  },
  {
    key: 'stock-operations',
    label: 'Stock Operations',
    tabs: [
      { key: 'inventory', label: 'Inventory', icon: Boxes },
      { key: 'transfers', label: 'Transfers', icon: Truck },
      { key: 'ingredients', label: 'Ingredients', icon: FlaskConical }
    ]
  },
  {
    key: 'catalog',
    label: 'Catalog',
    tabs: [
      { key: 'cocktails', label: 'Cocktails', icon: Martini },
      { key: 'additional-products', label: 'Additional Products', icon: ShoppingBag },
      { key: 'liquors', label: 'Liquors', icon: Wine },
      { key: 'shop', label: 'Shop', icon: ShoppingBag }
    ]
  },
  {
    key: 'marketing',
    label: 'Marketing',
    tabs: [
      { key: 'promotions', label: 'Promo Codes', icon: Ticket },
      { key: 'referrals', label: 'Referrals', icon: Gift }
    ]
  },
  {
    key: 'admin',
    label: 'Admin',
    tabs: [
      { key: 'locations', label: 'Locations', icon: MapPin },
      { key: 'employees', label: 'Employees', icon: Users }
    ]
  }
];

export const tabs = navigationSections.flatMap((section) => section.tabs);
