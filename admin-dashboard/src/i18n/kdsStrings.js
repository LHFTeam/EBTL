import { createContext, useContext } from 'react';

// Lightweight i18n for the KDS (Prep Orders) screen only. Deliberately
// dependency-free (no i18n library) to match the repo's minimal-deps policy.
// The KDS is a self-contained, full-screen route for `prep` staff, so the
// language state, RTL direction, and string catalog all live here rather than
// touching the rest of the (English/LTR) admin dashboard.

export const SUPPORTED_LANGS = ['ar', 'en'];
export const DEFAULT_LANG = 'ar';
export const LANG_STORAGE_KEY = 'ebtl.prep.lang';

export function normalizeLang(value) {
  return SUPPORTED_LANGS.includes(value) ? value : DEFAULT_LANG;
}

export function loadStoredLang() {
  try {
    return normalizeLang(window.localStorage.getItem(LANG_STORAGE_KEY));
  } catch {
    // Storage can be disabled; fall back to the default language.
    return DEFAULT_LANG;
  }
}

export function storeLang(lang) {
  try {
    window.localStorage.setItem(LANG_STORAGE_KEY, normalizeLang(lang));
  } catch {
    // Storage can be disabled; the in-memory choice still applies this session.
  }
}

// key -> { en, ar }. Templated strings use {placeholder} tokens.
const STRINGS = {
  // Order stages (stage banner + counts + aria)
  'stage.confirmed': { en: 'NEW', ar: 'جديد' },
  'stage.preparing': { en: 'PREPARING', ar: 'قيد التحضير' },
  'stage.ready': { en: 'READY', ar: 'جاهز' },
  'stage.completed': { en: 'COMPLETED', ar: 'مكتمل' },

  // Connection state
  'connection.live': { en: 'Live', ar: 'متصل' },
  'connection.offline': { en: 'Offline', ar: 'غير متصل' },
  'connection.reconnecting': { en: 'Reconnecting', ar: 'جارٍ إعادة الاتصال' },

  // Fulfillment
  'fulfillment.deliverTo': { en: 'Deliver to {address}', ar: 'توصيل إلى {address}' },
  'fulfillment.deliveryToUnit': { en: 'Delivery to unit', ar: 'توصيل إلى الوحدة' },
  'fulfillment.pickupAtCart': { en: 'Pickup at cart', ar: 'استلام من العربة' },

  // Variant label
  'variant.servings': { en: '{count} servings', ar: '{count} حصص' },
  'variant.standard': { en: 'Standard', ar: 'عادي' },

  // Item modifications
  'mod.no': { en: 'NO {name}', ar: 'بدون {name}' },
  'mod.add': { en: 'ADD {name}', ar: 'إضافة {name}' },
  'mod.addQty': { en: 'ADD {name} x{quantity}', ar: 'إضافة {name} ×{quantity}' },

  // Common fallbacks
  'common.item': { en: 'Item', ar: 'صنف' },
  'common.ingredient': { en: 'Ingredient', ar: 'مكوّن' },
  'common.extra': { en: 'Extra', ar: 'إضافة' },
  'common.employee': { en: 'Employee', ar: 'موظف' },
  'common.order': { en: 'Order', ar: 'طلب' },

  // Buttons
  'button.recipe': { en: 'Recipe', ar: 'الوصفة' },
  'button.close': { en: 'Close', ar: 'إغلاق' },
  'button.retry': { en: 'Retry', ar: 'إعادة' },
  'button.tryAgain': { en: 'Try again', ar: 'إعادة المحاولة' },
  'button.logout': { en: 'Log Out', ar: 'تسجيل الخروج' },

  // Ticket
  'ticket.ariaAdvance': {
    en: '{order} - {stage}. Press to advance.',
    ar: '{order} - {stage}. اضغط للمتابعة.'
  },
  'ticket.allergen': { en: 'ALLERGEN', ar: 'مسبب حساسية' },
  'ticket.note': { en: 'NOTE', ar: 'ملاحظة' },
  'ticket.done': { en: 'Done', ar: 'تم' },
  'ticket.completedAt': { en: 'Completed {time} Cairo', ar: 'اكتمل {time} بتوقيت القاهرة' },

  // Recipe overlay
  'recipe.closeAria': { en: 'Close recipe details', ar: 'إغلاق تفاصيل الوصفة' },
  'recipe.eyebrow': { en: '{order} / Recipe', ar: '{order} / الوصفة' },
  'recipe.elapsed': { en: '{timer} elapsed', ar: 'مضى {timer}' },
  'recipe.allergyWarning': { en: 'ALLERGY WARNING', ar: 'تحذير من مسببات الحساسية' },
  'recipe.customerMods': { en: 'Customer modifications', ar: 'تعديلات العميل' },
  'recipe.ingredients': { en: 'Ingredients for this order', ar: 'مكونات هذا الطلب' },
  'recipe.removed': { en: 'Removed from this order', ar: 'مُزال من هذا الطلب' },
  'recipe.optional': { en: 'Optional', ar: 'اختياري' },
  'recipe.customerSupplied': { en: 'Customer supplied', ar: 'يوفّره العميل' },
  'recipe.baseRecipe': { en: 'Base recipe', ar: 'الوصفة الأساسية' },
  'recipe.allergenLabel': { en: 'Allergen: {list}', ar: 'مسبب حساسية: {list}' },
  'recipe.empty': {
    en: 'No recipe ingredients are recorded for this item.',
    ar: 'لا توجد مكوّنات مسجّلة لهذا الصنف.'
  },
  'recipe.prepNotes': { en: 'Preparation notes', ar: 'ملاحظات التحضير' },
  'recipe.addedExtras': { en: 'Added extras', ar: 'إضافات' },
  'recipe.orderNote': { en: 'Order note', ar: 'ملاحظة الطلب' },

  // Header / filters / counts
  'header.fulfillment': { en: 'Fulfillment', ar: 'التجهيز' },
  'filter.active': { en: 'Active', ar: 'نشطة' },
  'filter.completed': { en: 'Completed', ar: 'مكتملة' },
  'filter.aria': { en: 'Order filter', ar: 'تصفية الطلبات' },
  'count.new': { en: 'New', ar: 'جديدة' },
  'count.preparing': { en: 'Preparing', ar: 'قيد التحضير' },
  'count.ready': { en: 'Ready', ar: 'جاهزة' },
  'nav.stationOperator': { en: 'Station operator', ar: 'مشغّل المحطة' },

  // Toast / errors
  'toast.dismissAria': { en: 'Dismiss message', ar: 'إغلاق الرسالة' },
  'toast.completed': { en: '{order} completed.', ar: 'اكتمل {order}.' },
  'toast.ready': { en: '{order} is ready for handoff.', ar: '{order} جاهز للتسليم.' },
  'toast.preparing': { en: '{order} moved to Preparing.', ar: 'انتقل {order} إلى قيد التحضير.' },
  'toast.conflict': {
    en: '{order} was already updated on another screen.',
    ar: 'تم تحديث {order} بالفعل على شاشة أخرى.'
  },
  'error.loadQueue': { en: 'Could not load the kitchen queue.', ar: 'تعذّر تحميل قائمة المطبخ.' },
  'error.loadLocation': {
    en: 'Could not load the assigned prep location.',
    ar: 'تعذّر تحميل موقع التحضير المخصّص.'
  },
  'error.updateOrder': { en: 'Could not update this order.', ar: 'تعذّر تحديث هذا الطلب.' },
  'error.logout': { en: 'Could not log out.', ar: 'تعذّر تسجيل الخروج.' },

  // Boot / empty / location-error states
  'boot.title': { en: 'Opening order display', ar: 'جارٍ فتح شاشة الطلبات' },
  'boot.subtitle': {
    en: 'Loading the assigned location and live queue...',
    ar: 'جارٍ تحميل الموقع المخصّص والقائمة المباشرة...'
  },
  'locationError.title': { en: 'Prep location unavailable', ar: 'موقع التحضير غير متاح' },
  'locationError.subtitle': {
    en: 'This prep employee does not have an active assigned cart location.',
    ar: 'لا يوجد موقع عربة نشط مخصّص لموظف التحضير هذا.'
  },
  'empty.activeTitle': { en: 'No active orders', ar: 'لا توجد طلبات نشطة' },
  'empty.activeSubtitle': {
    en: 'New orders will appear here automatically, in the order they arrive.',
    ar: 'ستظهر الطلبات الجديدة هنا تلقائيًا بترتيب وصولها.'
  },
  'empty.completedTitle': { en: 'No completed orders yet', ar: 'لا توجد طلبات مكتملة بعد' },
  'empty.completedSubtitle': {
    en: 'Orders you finish will appear here for the rest of your shift.',
    ar: 'ستظهر الطلبات التي تنهيها هنا حتى نهاية ورديتك.'
  }
};

// Allergen flags are a small, fixed vocabulary stored as tokens on ingredients.
// Map them to Arabic here (no DB change needed); unknown tokens fall back to
// the raw stored value so nothing is ever hidden from kitchen staff.
const ALLERGEN_LABELS = {
  nuts: { en: 'Nuts', ar: 'مكسرات' },
  tree_nuts: { en: 'Tree nuts', ar: 'مكسرات شجرية' },
  peanuts: { en: 'Peanuts', ar: 'فول سوداني' },
  peanut: { en: 'Peanuts', ar: 'فول سوداني' },
  dairy: { en: 'Dairy', ar: 'ألبان' },
  milk: { en: 'Milk', ar: 'حليب' },
  eggs: { en: 'Eggs', ar: 'بيض' },
  egg: { en: 'Eggs', ar: 'بيض' },
  gluten: { en: 'Gluten', ar: 'غلوتين' },
  wheat: { en: 'Wheat', ar: 'قمح' },
  soy: { en: 'Soy', ar: 'صويا' },
  soya: { en: 'Soy', ar: 'صويا' },
  sesame: { en: 'Sesame', ar: 'سمسم' },
  fish: { en: 'Fish', ar: 'أسماك' },
  shellfish: { en: 'Shellfish', ar: 'قشريات' },
  crustaceans: { en: 'Crustaceans', ar: 'قشريات' },
  molluscs: { en: 'Molluscs', ar: 'رخويات' },
  mollusks: { en: 'Molluscs', ar: 'رخويات' },
  sulfites: { en: 'Sulfites', ar: 'كبريتات' },
  sulphites: { en: 'Sulfites', ar: 'كبريتات' },
  mustard: { en: 'Mustard', ar: 'خردل' },
  celery: { en: 'Celery', ar: 'كرفس' },
  lupin: { en: 'Lupin', ar: 'ترمس' },
  alcohol: { en: 'Alcohol', ar: 'كحول' }
};

export function t(key, lang, params) {
  const normalized = normalizeLang(lang);
  const entry = STRINGS[key];
  let template = entry ? (entry[normalized] ?? entry.en) : key;

  if (params) {
    for (const [name, value] of Object.entries(params)) {
      template = template.replaceAll(`{${name}}`, String(value));
    }
  }

  return template;
}

export function allergenLabel(token, lang) {
  const raw = String(token || '').trim();
  if (!raw) return '';
  const normalized = normalizeLang(lang);
  const entry = ALLERGEN_LABELS[raw.toLowerCase().replace(/[\s-]+/g, '_')];
  return entry ? (entry[normalized] ?? entry.en) : raw;
}

// Resolve a display name for a DB entity that may carry an Arabic `name_ar`
// column (Phase 2). Always falls back to the English `name` so untranslated
// rows still render — safe even before the DB columns exist.
export function localizedName(entity, lang) {
  if (!entity) return '';
  if (normalizeLang(lang) === 'ar') return entity.name_ar || entity.name || '';
  return entity.name || entity.name_ar || '';
}

// Pick a display name preferring the Arabic live-join value, then the frozen
// English snapshot, then the English live-join value.
export function resolveItemName(entity, snapshot, lang) {
  if (normalizeLang(lang) === 'ar') return entity?.name_ar || snapshot || entity?.name || '';
  return snapshot || entity?.name || '';
}

export const KdsLangContext = createContext(DEFAULT_LANG);

export function useKdsLang() {
  return useContext(KdsLangContext);
}

export function useT() {
  const lang = useContext(KdsLangContext);
  return (key, params) => t(key, lang, params);
}
