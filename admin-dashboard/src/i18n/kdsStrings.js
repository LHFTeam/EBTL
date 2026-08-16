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
    en: '{order} - {stage}. Swipe the handle, or press Enter, to {action}.',
    ar: '{order} - {stage}. اسحب المقبض أو اضغط Enter لـ{action}.'
  },

  // Swipe-to-advance action (the label inside the slider track)
  'swipe.preparing': { en: 'Slide to start', ar: 'اسحب للبدء' },
  'swipe.ready': { en: 'Slide when ready', ar: 'اسحب عند الجهوزية' },
  'swipe.completed': { en: 'Slide to complete', ar: 'اسحب للإنهاء' },
  'swipe.scan': { en: 'Slide to scan code', ar: 'اسحب لمسح الكود' },
  'swipe.action.preparing': { en: 'start preparing', ar: 'بدء التحضير' },
  'swipe.action.ready': { en: 'mark ready', ar: 'تعليم كجاهز' },
  'swipe.action.completed': { en: 'complete the order', ar: 'إنهاء الطلب' },
  'swipe.action.scan': { en: 'scan the pickup code', ar: 'مسح كود الاستلام' },
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

  // Pickup handoff sheet (scan the customer's code, check the bag, release)
  'pickup.eyebrow': { en: 'Hand over', ar: 'تسليم' },
  'pickup.scanTitle': { en: 'Scan the customer’s code', ar: 'امسح كود العميل' },
  'pickup.scanSubtitle': {
    en: '{order} is ready. Point the camera at the code on the customer’s phone.',
    ar: '{order} جاهز. وجّه الكاميرا نحو الكود على هاتف العميل.'
  },
  'pickup.reviewTitle': { en: 'Check the bag', ar: 'راجع الطلب' },
  'pickup.reviewSubtitle': {
    en: 'Match these items to what you are about to hand over.',
    ar: 'طابق هذه الأصناف مع ما ستسلّمه.'
  },
  'pickup.closeAria': { en: 'Close the handover sheet', ar: 'إغلاق لوحة التسليم' },
  'pickup.cameraUnavailable': { en: 'Camera unavailable', ar: 'الكاميرا غير متاحة' },
  'pickup.cameraBlocked': {
    en: 'Camera access was blocked. Allow it in the browser, or type the code.',
    ar: 'تم حظر الوصول إلى الكاميرا. اسمح به في المتصفح أو أدخل الكود يدويًا.'
  },
  'pickup.cameraMissing': {
    en: 'No camera on this screen. Type the code instead.',
    ar: 'لا توجد كاميرا على هذه الشاشة. أدخل الكود يدويًا.'
  },
  'pickup.cameraFailed': {
    en: 'Could not start the camera. Type the code instead.',
    ar: 'تعذّر تشغيل الكاميرا. أدخل الكود يدويًا.'
  },
  'pickup.checking': { en: 'Checking...', ar: 'جارٍ التحقق...' },
  'pickup.typeInstead': { en: 'Can’t scan - type the code', ar: 'تعذّر المسح - أدخل الكود' },
  'pickup.backToScanning': { en: 'Back to scanning', ar: 'العودة للمسح' },
  'pickup.manualHint': {
    en: 'The six digits under the code on the customer’s screen. They expire with it, so ask for a fresh one if it has been sitting a while.',
    ar: 'الأرقام الستة أسفل الكود على شاشة العميل. تنتهي صلاحيتها مع الكود، فاطلب كودًا جديدًا إذا مضى وقت.'
  },
  'pickup.orderNumberLabel': { en: 'Order number', ar: 'رقم الطلب' },
  'pickup.shortCodeLabel': { en: 'Six-digit code', ar: 'الكود المكوّن من ٦ أرقام' },
  'pickup.checkCode': { en: 'Check code', ar: 'تحقق من الكود' },
  'pickup.confirm': { en: 'Confirm handover', ar: 'تأكيد التسليم' },
  'pickup.scanAnother': { en: 'Scan another', ar: 'مسح كود آخر' },
  'pickup.methodScanned': { en: 'Scanned', ar: 'ممسوح' },
  'pickup.methodTyped': { en: 'Typed code', ar: 'كود مُدخل' },
  'pickup.itemCount': { en: '{count} items', ar: '{count} أصناف' },
  'pickup.differentOrder': {
    en: 'This code belongs to a different order from the ticket you opened. Hand over the one below.',
    ar: 'هذا الكود يخص طلبًا مختلفًا عن التذكرة التي فتحتها. سلّم الطلب الظاهر أدناه.'
  },
  'pickup.noCode': {
    en: 'No code at all? A supervisor releases the order from the dashboard - prep accounts cannot override.',
    ar: 'لا يوجد كود؟ يقوم المشرف بتسليم الطلب من لوحة التحكم - حسابات التحضير لا تملك صلاحية التجاوز.'
  },
  'pickup.handedOver': { en: '{order} handed over.', ar: 'تم تسليم {order}.' },
  'pickup.handedOverUnlogged': {
    en: '{order} handed over, but the handoff log did not save. Tell a supervisor.',
    ar: 'تم تسليم {order} لكن لم يُحفظ سجل التسليم. أبلغ المشرف.'
  },

  // Pickup problems, keyed by the `code` the handoff routes answer with. Codes
  // without an entry here fall back to the server's own (English) message.
  'pickupError.expired': {
    en: 'That code has expired. Ask the customer to refresh their screen, then scan again.',
    ar: 'انتهت صلاحية هذا الكود. اطلب من العميل تحديث الشاشة ثم امسح مرة أخرى.'
  },
  'pickupError.unrecognized': {
    en: 'That is not an EBTL pickup code.',
    ar: 'هذا ليس كود استلام من EBTL.'
  },
  'pickupError.unknown_order': {
    en: 'No order with that number is waiting at this cart.',
    ar: 'لا يوجد طلب بهذا الرقم في انتظار الاستلام من هذه العربة.'
  },
  'pickupError.code_mismatch': {
    en: 'Those digits do not match a current code. Ask the customer to refresh their screen.',
    ar: 'هذه الأرقام لا تطابق كودًا حاليًا. اطلب من العميل تحديث الشاشة.'
  },
  'pickupError.already_collected': {
    en: 'That order has already been collected.',
    ar: 'تم استلام هذا الطلب بالفعل.'
  },
  'pickupError.not_ready': {
    en: 'That order is not ready yet.',
    ar: 'هذا الطلب ليس جاهزًا بعد.'
  },
  'pickupError.unpaid': { en: 'That order is not paid for yet.', ar: 'لم يتم دفع هذا الطلب بعد.' },
  'pickupError.wrong_location': {
    en: 'That order belongs to another cart.',
    ar: 'هذا الطلب يخص عربة أخرى.'
  },
  'pickupError.not_pickup': {
    en: 'That order is a delivery, not a cart pickup.',
    ar: 'هذا الطلب توصيل وليس استلامًا من العربة.'
  },
  'pickupError.rate_limited': {
    en: 'Too many failed attempts. Wait a moment, then try again.',
    ar: 'محاولات فاشلة كثيرة. انتظر قليلًا ثم حاول مرة أخرى.'
  },
  'pickupError.failed': { en: 'Could not check that code.', ar: 'تعذّر التحقق من هذا الكود.' },
  'pickupError.confirmFailed': {
    en: 'Could not release that order.',
    ar: 'تعذّر تسليم هذا الطلب.'
  },

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

// Whether the catalog carries a key at all. `t` falls back to the key itself,
// which is fine for a missing label but wrong for a server-sent error code: an
// unmapped code should show what the server actually said, not `pickupError.x`.
export function hasString(key) {
  return Object.hasOwn(STRINGS, key);
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
