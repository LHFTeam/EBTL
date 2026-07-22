import { Router } from 'express';
import { requireArea } from '../middleware/auth.js';
import { supabase } from '../lib/supabase.js';

export const dashboardRouter = Router();

dashboardRouter.get('/dashboard', requireArea('dashboard'), async (_req, res) => {
  const [orders, sales, lowStock, locations, transfers] = await Promise.all([
    supabase.from('orders').select('id,order_number,status,payment_status,total_amount,created_at,location_id').order('created_at', { ascending: false }).limit(200),
    supabase.from('v_daily_sales_by_location').select('*').order('sales_date', { ascending: false }).limit(30),
    supabase.from('v_inventory_low_stock').select('*').limit(100),
    supabase.from('locations').select('*').order('name'),
    supabase.from('stock_transfers').select('id,status,requested_at').in('status', ['draft', 'picked', 'in_transit']).limit(100)
  ]);
  for (const result of [orders, sales, lowStock, locations, transfers]) if (result.error) return res.status(400).json({ error: result.error.message });
  const completed = orders.data.filter((order) => order.status === 'completed');
  res.json({
    kpis: {
      recentOrders: orders.data.length,
      completedOrders: completed.length,
      recentRevenue: completed.reduce((sum, order) => sum + Number(order.total_amount || 0), 0),
      lowStockItems: lowStock.data.length,
      activeLocations: locations.data.filter((location) => location.is_active).length,
      openTransfers: transfers.data.length
    },
    recentOrders: orders.data.slice(0, 20),
    dailySales: sales.data,
    lowStock: lowStock.data,
    locations: locations.data
  });
});
