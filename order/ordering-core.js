/*
 * Shared ordering logic used by both the Customer Kiosk (order/index.html)
 * and the Staff Hub (staff/index.html) -- pricing math and menu
 * normalization specifically, the two categories most likely to need a
 * fix applied consistently everywhere rather than in just one place.
 * Loaded by both pages via <script src>, same as db-supabase.js/geo.js.
 *
 * This is a deliberately narrow first step, not a full merge of the two
 * apps' ordering code -- cart state, the pizza-builder UI, and the
 * customer/POS-specific cart-pane markup all still live separately in
 * each file, since they're genuinely different between the two screens
 * (the POS cart pane has no promo-code field, for one) and extracting
 * them safely is a larger, separate piece of work. See ROADMAP.md's
 * "Priority 4" entry for the reasoning and what's still duplicated.
 */

/* Everything from here down to DAY_NAMES is the hardcoded fallback
   menu -- it's what both apps use if menu_config can't be loaded
   (offline, table not migrated yet, RLS hiccup, etc.), so ordering/
   pricing keeps working even when the database doesn't. loadMenuConfig()
   below overwrites these `let`-declared globals with the live values
   from Supabase when it can. See supabase/schema.sql and Staff Hub >
   Menu Editor. */
let TAX_RATE = 0.06625;

let PIZZA_SIZES = [
  { key:'personal', label:'Personal Pan (9")', base:8.00, perTopping:1.00 },
  { key:'medium',   label:'Medium (14")',      base:14.50, perTopping:3.00 },
  { key:'large',    label:'Large (16")',       base:15.99, perTopping:3.50 },
  { key:'sicilian', label:'Sicilian (16x16")', base:17.99, perTopping:4.00 },
];
let TOPPINGS = ['Pepperoni','Sausage','Bacon','Meatball','Ham','Extra Cheese','Green Pepper','Onion','Black Olive','Mushroom','Anchovy','Pineapple','Spinach','Broccoli'];
let SPECIALTY_PIZZAS = [
  { name:'Bacon BBQ Chicken Ranch', sizes:[{label:'Medium',price:24.00},{label:'Large',price:26.00}] },
  { name:'Buffalo Chicken',         sizes:[{label:'Medium',price:24.00},{label:'Large',price:26.00}] },
  { name:'Hawaiian',                sizes:[{label:'Medium',price:20.50},{label:'Large',price:22.99},{label:'Sicilian',price:24.99}] },
  { name:'White Pie',               sizes:[{label:'Medium',price:14.50},{label:'Large',price:15.99},{label:'Sicilian',price:17.99}] },
  { name:'The Works',               sizes:[{label:'Medium',price:24.00},{label:'Large',price:25.99},{label:'Sicilian',price:29.99}] },
];

let CATEGORIES = [
  { key:'panzarotti', label:'Panzarotti', note:'Deep fried and golden brown', items:[
    { name:'Panzarotti', price:8.25, desc:'Add $0.75 per extra ingredient' },
  ]},
  { key:'stromboli', label:'Stromboli', photo:'../images/menu/stromboli.jpg', placeholder:'../images/menu/stromboli.svg', items:[
    { name:'Cheese Stromboli', price:17.99, desc:'+$2.50 per topping, +$5.00 steak or chicken' },
    { name:'Steak & Onion Stromboli', price:24.99 },
  ]},
  { key:'calzones', label:'Calzones', photo:'../images/menu/calzone.jpg', placeholder:'../images/menu/calzone.svg', items:[
    { name:'Calzone', price:14.99, desc:'Ham, ricotta, mozzarella and sauce' },
  ]},
  { key:'turnover', label:'Pizza Turnover', items:[
    { name:'Pizza Turnover', price:13.50, desc:'Mozzarella and pizza sauce, $1 per extra ingredient' },
  ]},
  { key:'wings', label:'Wings', note:'All wings come with bread and blue cheese', photo:'../images/menu/wings.jpg', placeholder:'../images/menu/wings.svg', items:[
    { name:'Wings', size:'8 pc', price:9.50 },
    { name:'Wings', size:'12 pc', price:14.99 },
    { name:'Wings', size:'16 pc', price:18.99 },
    { name:'Wings', size:'24 pc', price:27.99 },
  ]},
  { key:'steaks', label:'Steaks', note:'Chicken made with 100% boneless, skinless breast meat', items:[
    { name:'Plain Steak', price:11.00 }, { name:'Cheese Steak', price:12.00 }, { name:'Chicken Cheese Steak', price:12.00 },
    { name:'Bacon Cheese Steak', price:13.00 }, { name:'Cheese Steak Sub', price:13.00 }, { name:'Chicken Cheese Steak Sub', price:13.00 },
    { name:'Mushroom Cheese Steak', price:13.00 }, { name:'Pepperoni Cheese Steak', price:13.00 }, { name:'Pizza Steak', price:13.00 },
    { name:'Buffalo Chicken Cheese Steak', price:13.00 }, { name:'Broccoli Garlic & Oil Chicken Cheese Steak', price:13.00 },
    { name:'Cheese Steak Special', price:13.75 }, { name:'Cheese Steak Platter', price:14.99 },
  ]},
  { key:'hoagies', label:'Hoagies', note:'All hoagies made with lettuce, tomato, onion and oil', photo:'../images/menu/hoagie.jpg', placeholder:'../images/menu/hoagie.svg', items:[
    { name:'Mixed Cheese', price:11.00 }, { name:'American', price:11.50 }, { name:'Ham & Cheese', price:12.00 },
    { name:'Italian', price:12.00 }, { name:'Turkey & Cheese', price:12.00 }, { name:'Roast Beef, Provolone or American', price:13.00 },
    { name:'Fried Fish Hoagie', price:13.00 },
  ]},
  { key:'pasta', label:'Pasta', note:'Served with soup, salad and garlic bread, spaghetti or ziti', photo:'../images/menu/pasta.jpg', placeholder:'../images/menu/pasta.svg', items:[
    { name:'Tomato Sauce', price:12.99 }, { name:'Meatballs', price:16.99 }, { name:'Sausage', price:16.99 },
  ]},
  { key:'parm', label:'Parmigiana Dinners', note:'Served with salad and garlic bread or a side of spaghetti/ziti', items:[
    { name:'Eggplant Parmigiana', price:15.99 }, { name:'Chicken Cutlet Parmigiana', price:16.99 },
  ]},
  { key:'hotsand', label:'Hot Sandwiches', items:[
    { name:'Homemade Meatball Sandwich', price:11.50 }, { name:'Eggplant Parmigiana', price:11.00 },
    { name:'Homemade Meatball Parmigiana', price:12.50 }, { name:'Chicken Parmigiana', price:12.50 },
    { name:'Sausage Parmigiana', price:12.50 }, { name:'Hot Roast Beef', price:12.00 },
    { name:'Hot Roast Beef with Cheese', price:13.00 }, { name:'Sausage Supreme', price:12.99 },
  ]},
  { key:'italian', label:'Italian Specialties', note:'Served with soup, salad and garlic bread', items:[
    { name:'Baked Ziti', price:16.99 }, { name:'Cheese Ravioli', price:16.99 }, { name:'Stuffed Shells Parmigiana', price:16.99 },
  ]},
  { key:'platters', label:'Platters', items:[
    { name:'BLT Club', price:12.99 }, { name:'Chicken Finger Platter', price:13.99 }, { name:'Ham & Cheese Club', price:13.99 },
    { name:'Chicken Club', price:14.99 }, { name:'Roast Beef Club', price:14.99 }, { name:'Turkey Club', price:14.99 }, { name:'Shrimp Platter', price:14.99 },
  ]},
  { key:'burgers', label:'Quarter Pound Burgers', photo:'../images/menu/burger.jpg', placeholder:'../images/menu/burger.svg', items:[
    { name:'Hamburger', price:7.00 }, { name:'Cheeseburger', price:8.00 }, { name:'Bacon Cheeseburger', price:9.00 },
    { name:'Pizza Burger', price:9.00 }, { name:'Cheese Burger Sub', price:13.00 },
  ]},
  { key:'sides', label:'Side Orders', items:[
    { name:'French Fries', price:5.75 }, { name:'Onion Rings', price:8.00 }, { name:'Poppers', size:'Cheddar', price:8.00 },
    { name:'Breaded Mushrooms', price:8.50 }, { name:'Broccoli Bites', price:8.50 }, { name:'Meatballs', price:8.50 },
    { name:'Mozzarella Sticks', price:8.50 }, { name:'Pizza Fries', size:'Small', price:8.50 }, { name:'Pizza Fries', size:'Large', price:10.50 },
    { name:'Sausage', price:8.50 }, { name:'Fried Tomato', price:9.00 }, { name:'Cheese Fries', size:'Small', price:6.50 },
    { name:'Cheese Fries', size:'Large', price:9.00 }, { name:'Loaded Fries', size:'Small', price:9.50 }, { name:'Loaded Fries', size:'Large', price:10.50 },
    { name:'Homemade Cole Slaw', size:'Pint', price:3.50 }, { name:'Homemade Cole Slaw', size:'Quart', price:7.00 },
    { name:'Something Sweet Zeppoli', size:'Small', price:4.00 }, { name:'Something Sweet Zeppoli', size:'Large', price:8.00 },
  ]},
  { key:'soups', label:'Soups', items:[
    { name:'Pasta Faggioli', size:'Small', price:4.99 }, { name:'Pasta Faggioli', size:'Quart', price:8.99 },
    { name:'Chili', size:'Small, winter', price:6.50 }, { name:'Chili', size:'Quart, winter', price:11.99 },
  ]},
  { key:'salads', label:'Salads', photo:'../images/menu/salad.jpg', placeholder:'../images/menu/salad.svg', items:[
    { name:'Tossed Salad', price:7.99 }, { name:'Antipasta', price:12.99 }, { name:'Chef Salad', price:12.99 },
    { name:'Chicken Caesar Salad', price:12.99 }, { name:'Grilled Chicken Salad', price:12.99 },
  ]},
  { key:'breakfast', label:'Breakfast', items:[
    { name:'Grilled Cheese', price:7.00, desc:'+$1 to add ham or bacon' }, { name:'Bacon, Lettuce & Tomato', price:8.00 },
    { name:'Pepper and Egg', price:10.00 }, { name:'Bacon, Egg and Cheese', price:11.00 },
    { name:'Sausage, Egg and Cheese', price:11.00 }, { name:'Pork Roll, Egg and Cheese', price:11.00 },
  ]},
  { key:'knots', label:'Garlic Knots', items:[ { name:'Garlic Knots', size:'6 pc', price:4.75 } ]},
  { key:'drinks', label:'Drinks', note:'We carry Pepsi products -- names/prices are a starting point, adjust in Staff Hub > Menu Editor to match what you actually stock', items:[
    { name:'Pepsi', size:'20 oz', price:2.75 }, { name:'Diet Pepsi', size:'20 oz', price:2.75 },
    { name:'Pepsi Zero Sugar', size:'20 oz', price:2.75 }, { name:'Mountain Dew', size:'20 oz', price:2.75 },
    { name:'Starry', size:'20 oz', price:2.75 }, { name:'Mug Root Beer', size:'20 oz', price:2.75 },
    { name:'Brisk Iced Tea', size:'20 oz', price:2.75 }, { name:'Aquafina Water', size:'20 oz', price:2.00 },
    { name:'Pepsi', size:'2 Liter', price:4.50 }, { name:'Diet Pepsi', size:'2 Liter', price:4.50 },
    { name:'Mountain Dew', size:'2 Liter', price:4.50 }, { name:'Starry', size:'2 Liter', price:4.50 },
  ]},
];

let SPECIALS_BY_DAY = {
  0:{ name:'4 Original Panzarotti', price:25.99 },
  1:{ name:'2 Cheese Steaks', price:20.99 },
  2:{ name:'Large Pizza', price:13.99 },
  3:{ name:'Sicilian Pie', price:15.99 },
  4:{ name:'2 Chicken Finger Platters', price:22.99 },
  5:{ name:'Stromboli + 2 Liter Soda', price:18.50 },
  6:{ name:'Cheese Steak Platter', price:13.99 },
};
const DAY_NAMES = ['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday'];

function applyMenuConfig(cfg){
  if (!cfg || typeof cfg !== 'object') return false;
  if (typeof cfg.TAX_RATE === 'number') TAX_RATE = cfg.TAX_RATE;
  if (Array.isArray(cfg.PIZZA_SIZES) && cfg.PIZZA_SIZES.length) PIZZA_SIZES = cfg.PIZZA_SIZES;
  if (Array.isArray(cfg.TOPPINGS) && cfg.TOPPINGS.length) TOPPINGS = cfg.TOPPINGS;
  if (Array.isArray(cfg.SPECIALTY_PIZZAS)) SPECIALTY_PIZZAS = cfg.SPECIALTY_PIZZAS;
  if (Array.isArray(cfg.CATEGORIES) && cfg.CATEGORIES.length) CATEGORIES = cfg.CATEGORIES;
  if (cfg.SPECIALS_BY_DAY && typeof cfg.SPECIALS_BY_DAY === 'object') SPECIALS_BY_DAY = cfg.SPECIALS_BY_DAY;
  return true;
}

async function loadMenuConfig(db){
  if (!db) return false;
  try{
    const doc = await db.collection('menu_config').doc(1).get();
    const row = doc.data(); // the whole menu_config row: {id, data, version, updatedAt, updatedBy}
    return applyMenuConfig(row && row.data); // .data is the actual menu JSON -- applyMenuConfig
      // expects {TAX_RATE, CATEGORIES, ...} directly, not the wrapping row.
  }catch(e){
    console.error('Could not load live menu config, using built-in defaults:', e);
    reportAppError('menu-config-load', (e && e.message) || 'unknown error');
    return false;
  }
}

/* Structured error telemetry (Phase 4: Operational Monitoring, Staff
   Hub > System Health) -- fire-and-forget, deliberately never awaited
   by a caller and never throws back into one. Only ever pass a short,
   generic error message here, NEVER a customer name/phone/address/cart
   contents -- report_app_error() itself also truncates and this is the
   one boundary that keeps sensitive data out of a table staff can
   browse. Deduped server-side by (source, message), so calling this
   from a busy retry loop can't flood the table. A failure to report a
   failure is itself just silently swallowed -- monitoring must never
   become a second way for something to break. */
function reportAppError(source, message){
  try{
    if (typeof App !== 'undefined' && App && App.db && typeof App.db.rpc === 'function'){
      App.db.rpc('report_app_error', { p_source: source, p_message: String(message || 'unknown error').slice(0, 300) }).catch(()=>{});
    }
  }catch(e){ /* see comment above -- never let this be the thing that breaks */ }
}

/* Pricing math + small formatting/normalization helpers used
   everywhere an order total, a line item, or user-supplied text gets
   rendered. */
function money(n){ return '$' + (Math.round(n*100)/100).toFixed(2); }

function escapeHtml(s){
  return String(s==null?'':s).replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
}

function lineLabel(it){
  return it.name + (it.size ? ' (' + it.size + ')' : '');
}

function computeTotals(items, tip, discount){
  const subtotal = items.reduce((s,it)=> s + it.unitPrice*it.qty, 0);
  const discountAmt = Math.min(discount || 0, subtotal); // never let a discount exceed the subtotal
  const taxableSubtotal = subtotal - discountAmt;
  const tax = taxableSubtotal * TAX_RATE;
  const tipAmt = tip || 0;
  return { subtotal, discount: discountAmt, tax, tip: tipAmt, total: taxableSubtotal + tax + tipAmt };
}

/* =========================================================================
   CART STATE + PIZZA-BUILDER/CART-PANE UI -- shared by the customer kiosk
   (order/index.html, mode='customer') and the Staff Hub POS (staff/index.html,
   mode='pos'). Both pages keep their own `orderCtx` global and their own
   submit/receipt/queue logic; everything below is the identical building,
   rendering, and wiring code that used to be duplicated in both files.
   Mode-specific bits (kiosk-only cart drawer, promo codes, saved-address
   autofill, POS-only cash tendering/queue) are branched or self-guarded
   inline exactly as they were before the merge. */

function isSignatureItem(cat, it){
  return cat.key === 'panzarotti';
}

/* Resolves a stored cart-line `ref` (see addLine's callers below --
   catalog/specialty/custom/special) against the CURRENT in-memory menu
   data, for "Reorder these items" (order/index.html). Mirrors the same
   resolution create_order() does server-side, but this copy is only
   ever used to build a fresh cart line for display/editing before
   submit -- the server re-validates everything for real at checkout, so
   this doesn't need to be a security boundary, just accurate enough
   that reordering shows today's real price/availability instead of
   whatever was true when the original order was placed. Returns null
   for anything that no longer resolves (item removed, sold out, a
   topping discontinued, size changed) so the caller can skip it and
   tell the customer, rather than silently reordering at a stale price
   the way this used to work. */
function resolveRefToLine(ref){
  if (!ref || !ref.kind) return null;
  if (ref.kind === 'catalog'){
    const cat = CATEGORIES.find(c => c.key === ref.categoryKey);
    if (!cat) return null;
    const it = cat.items.find(i => i.name === ref.itemName);
    if (!it || it.soldOut) return null;
    return { name: it.name, size: it.size || '', unitPrice: it.price, notes: '', ref: { kind:'catalog', categoryKey: cat.key, itemName: it.name } };
  }
  if (ref.kind === 'specialty'){
    const p = SPECIALTY_PIZZAS.find(x => x.name === ref.pizzaName);
    if (!p) return null;
    const s = p.sizes.find(x => x.label === ref.sizeLabel);
    if (!s) return null;
    return { name: p.name, size: s.label, unitPrice: s.price, notes: '', ref: { kind:'specialty', pizzaName: p.name, sizeLabel: s.label } };
  }
  if (ref.kind === 'custom'){
    const sizeObj = PIZZA_SIZES.find(s => s.key === ref.sizeKey);
    if (!sizeObj) return null;
    const requested = ref.toppings || [];
    const stillValid = requested.filter(t => TOPPINGS.includes(t));
    if (stillValid.length !== requested.length) return null; // a topping was discontinued -- don't silently rebuild without it
    const unitPrice = sizeObj.base + sizeObj.perTopping * stillValid.length;
    return {
      name: sizeObj.label.replace(/\s*\(.+\)$/,'') + ' Pizza', size: sizeObj.label, unitPrice,
      notes: stillValid.join(', '), ref: { kind:'custom', sizeKey: sizeObj.key, toppings: stillValid },
    };
  }
  if (ref.kind === 'special'){
    // Daily specials are date-bound by design -- always resolves to
    // TODAY's actual special, never whatever day the original order
    // happened to be placed on.
    const today = SPECIALS_BY_DAY[new Date().getDay()];
    if (!today) return null;
    return { name: today.name, size: '', unitPrice: today.price, notes: 'Daily special', ref: { kind:'special' } };
  }
  return null;
}

function resetOrderCtx(mode){
  orderCtx = { mode, cart:[], pizzaSize:'medium', pizzaToppings:new Set(), orderType:null, payMethod:'cash', tip:0, tipPct:null, deliveryInfo:null, promoCode:null, discountAmount:0, discountLabel:'', formLoadedAt:Date.now(), editingOrderId:null };
}

const CART_STORAGE_KEY = 'cifellisCart';
const CART_STORAGE_MAX_AGE_MS = 6 * 60 * 60 * 1000; // 6 hours -- long enough
  // to survive an accidental reload or a closed tab, short enough that a
  // customer doesn't come back tomorrow and reorder yesterday's cart
  // without realizing it's stale (prices/menu may have changed too).

function saveCartToStorage(){
  if (orderCtx.mode !== 'customer') return;
  try{
    if (!orderCtx.cart.length){ localStorage.removeItem(CART_STORAGE_KEY); return; }
    localStorage.setItem(CART_STORAGE_KEY, JSON.stringify({
      cart: orderCtx.cart, orderType: orderCtx.orderType, tip: orderCtx.tip, tipPct: orderCtx.tipPct,
      payMethod: orderCtx.payMethod, deliveryInfo: orderCtx.deliveryInfo,
      pizzaSize: orderCtx.pizzaSize, pizzaToppings: Array.from(orderCtx.pizzaToppings || []),
      savedAt: Date.now(),
    }));
  }catch(e){ /* storage full/unavailable -- cart just won't survive a reload, not fatal */ }
}

function addLine(line){
  const key = line.name+'|'+(line.size||'')+'|'+(line.notes||'');
  const existing = orderCtx.cart.find(l => l._key===key);
  if (existing){ existing.qty += line.qty||1; }
  else { orderCtx.cart.push(Object.assign({_key:key, qty:line.qty||1}, line)); }
  renderCart(orderCtx.mode);
}
function changeQty(key, delta){
  const l = orderCtx.cart.find(x=>x._key===key);
  if (!l) return;
  l.qty += delta;
  if (l.qty<=0) orderCtx.cart = orderCtx.cart.filter(x=>x._key!==key);
  renderCart(orderCtx.mode);
}

function buildMenuPaneHTML(mode){
  const today = SPECIALS_BY_DAY[new Date().getDay()];
  let html = '';
  if (mode === 'customer' && ORDERS_PAUSED){
    html += `<div class="paused-banner" style="background:var(--ink-soft); border:1px solid var(--gold); border-radius:10px; padding:14px 16px; margin-bottom:16px; font-size:14px; line-height:1.5;">
      <div style="font-family:'IBM Plex Mono',monospace; font-size:11px; text-transform:uppercase; letter-spacing:.12em; color:var(--gold); margin-bottom:4px;">Online Ordering Paused</div>
      <div>${escapeHtml(PAUSE_MESSAGE)}</div>
    </div>`;
  }
  if (mode === 'customer'){
    html += `<div class="menu-hero">
      <div class="menu-hero-photos">
        <img src="../images/order-pizza-thumb.jpg" alt="Fresh pizza from Cifelli's oven" loading="lazy" width="416" height="416">
        <img src="../images/order-sauce-thumb.jpg" alt="Sauce spread by hand on fresh dough" loading="lazy" width="416" height="416">
        <img src="../images/order-oven-thumb.jpg" alt="A pizza in Cifelli's wood-fired oven" loading="lazy" width="416" height="416">
      </div>
      <div>
        <div class="t">Hand-stretched, fired fresh</div>
        <div class="d">Every pie is built to order, right when you send it in.</div>
      </div>
    </div>`;
  }
  html += `<div class="cat-bar" id="catbar-${mode}">
    <button class="pill" data-cat="all" aria-pressed="true">All</button>
    <button class="pill" data-cat="pizza">Pizza</button>`;
  CATEGORIES.forEach(c => html += `<button class="pill" data-cat="${c.key}">${escapeHtml(c.label)}</button>`);
  html += `</div>`;

  html += `<div class="today-banner" id="todaybanner-${mode}">
    <div><div class="t">Today's Special, ${DAY_NAMES[new Date().getDay()]}</div><div class="n">${escapeHtml(today.name)}</div></div>
    <div class="p">${money(today.price)}</div>
  </div>`;

  html += `<div class="menu-section" data-section="pizza">
    <h3>Pizza</h3>
    <div class="builder" id="builder-${mode}">
      <div style="font-size:12.5px; color:var(--paper-dim); margin-bottom:4px;">Build your own</div>
      <div class="size-row" id="sizerow-${mode}"></div>
      <div style="font-size:12.5px; color:var(--paper-dim); margin:6px 0 2px;">Toppings</div>
      <div class="topping-grid" id="toppingrow-${mode}"></div>
      <div class="builder-total">
        <div class="mono" id="buildertotal-${mode}" style="font-weight:700; font-size:16px; color:var(--gold);"></div>
        <button class="btn btn-sauce" id="addpizza-${mode}" type="button">Add Pizza</button>
      </div>
    </div>
    <div style="margin-top:14px; display:flex; align-items:center; gap:8px;">
      <span class="signature-badge">Signature</span>
      <span style="font-size:13px; color:var(--paper-dim); font-weight:700;">Specialty Pies</span>
    </div>
    <div class="item-grid" style="margin-top:8px;" id="specialty-${mode}"></div>
  </div>`;

  CATEGORIES.forEach(cat => {
    html += `<div class="menu-section" data-section="${cat.key}">
      ${cat.photo ? `<img class="menu-section-banner" src="${cat.photo}" alt="${escapeHtml(cat.label)}" loading="lazy" onerror="this.onerror=null; this.src='${cat.placeholder}';">` : ''}
      <h3>${escapeHtml(cat.label)}${cat.note ? ` <span class="note">${escapeHtml(cat.note)}</span>` : ''}</h3>
      <div class="item-grid">`;
    cat.items.forEach((it, idx) => {
      const soldOut = !!it.soldOut;
      html += `<button type="button" class="item-card${soldOut ? ' item-card--soldout' : ''}${isSignatureItem(cat, it) ? ' item-card--signature' : ''}" data-add-cat="${cat.key}" data-add-idx="${idx}" ${soldOut ? 'aria-disabled="true"' : ''}>
        <span><span class="n">${escapeHtml(it.name)}${isSignatureItem(cat, it) ? '<span class="signature-badge">Signature</span>' : ''}</span>${it.size?`<span class="s">${escapeHtml(it.size)}</span>`:''}${it.desc?`<span class="s">${escapeHtml(it.desc)}</span>`:''}</span>
        <span style="display:flex; align-items:center; gap:8px;">${soldOut ? `<span class="soldout-badge">Sold Out</span>` : `<span class="p">${money(it.price)}</span><span class="plus">+</span>`}</span>
      </button>`;
    });
    html += `</div></div>`;
  });
  return html;
}

function buildCartPaneHTML(mode){
  if (mode==='customer'){
    return `
      <div class="cart-drag-handle" id="cartdraghandle-${mode}"></div>
      <div class="cart-head cart-head--customer">
        <img src="../images/order-cheesepull-thumb.jpg" alt="Fresh cheese pull from a Cifelli's pizza" class="cart-hero-thumb">
        <h3>Your Order</h3>
        <button type="button" class="cart-close-btn" id="cartclose-${mode}" aria-label="Close cart">&times;</button>
      </div>
      <div class="cart-items" id="cartitems-${mode}"></div>
      <div class="cart-foot">
        <div class="field-group"><label>Order Type</label>
          <div class="seg" id="ordertype-${mode}">
            <button type="button" data-v="pickup" aria-pressed="true">Pickup</button>
            <button type="button" data-v="delivery">Delivery</button>
          </div>
        </div>
        <div aria-hidden="true" style="position:absolute; left:-9999px; width:1px; height:1px; overflow:hidden;">
          <label>Company</label><input id="hp-${mode}" name="company" tabindex="-1" autocomplete="off">
        </div>
        <div class="field-group"><label>Name</label><input id="custname-${mode}" placeholder="Your name"></div>
        <div class="field-group"><label>Phone</label><input id="custphone-${mode}" placeholder="(856) 555-0100"></div>
        <div class="field-group" style="display:flex; align-items:center; gap:8px;">
          <input type="checkbox" id="smsoptin-${mode}" style="width:auto;">
          <label for="smsoptin-${mode}" style="margin:0; text-transform:none; font-size:13px; letter-spacing:normal; color:var(--paper-dim); font-family:inherit;">Text me when my order's ready (standard rates may apply)</label>
        </div>
        <div class="field-group" id="addrgroup-${mode}" hidden><label>Delivery Address</label>
          <div style="display:flex; gap:8px;">
            <input id="custaddr-${mode}" placeholder="Street, Lindenwold NJ" autocomplete="street-address" style="flex:1;">
            <button type="button" class="btn btn-outline" id="addrcheck-${mode}" style="padding:0 14px; white-space:nowrap;">Check Address</button>
          </div>
          <div id="addrinfo-${mode}" style="font-size:11.5px; color:var(--paper-dim); margin-top:6px; min-height:14px;"></div>
        </div>
        <div class="field-group"><label>Notes (optional)</label><input id="custnotes-${mode}" placeholder="Allergies, extra sauce, etc."></div>
        <div class="field-group" id="promogroup-${mode}"><label>Promo Code (optional)</label>
          <div style="display:flex; gap:8px;">
            <input id="promocode-${mode}" placeholder="Enter code" style="flex:1; text-transform:uppercase;">
            <button class="btn btn-outline" id="promoapply-${mode}" type="button" style="padding:0 16px; white-space:nowrap;">Apply</button>
          </div>
          <div id="promostatus-${mode}" style="font-size:12px; margin-top:6px;"></div>
        </div>
        <div class="field-group"><label>Payment</label>
          <div class="seg" id="paymethod-${mode}">
            <button type="button" data-v="cash" aria-pressed="true">Cash</button>
            <button type="button" data-v="card">Card</button>
          </div>
          <div style="font-size:11px; color:var(--paper-dim); margin-top:6px;">Paid in person at pickup or delivery. Card processing isn't connected here.</div>
        </div>
        <div class="field-group" id="tipgroup-${mode}"><label id="tiplabel-${mode}">Add a Tip</label>
          <div class="seg" id="tipseg-${mode}">
            <button type="button" data-v="0" aria-pressed="true">No Tip</button>
            <button type="button" data-v="0.15">15%</button>
            <button type="button" data-v="0.18">18%</button>
            <button type="button" data-v="0.20">20%</button>
            <button type="button" data-v="custom">Custom</button>
          </div>
          <input id="tipcustom-${mode}" type="number" step="0.01" min="0" placeholder="Custom tip amount" hidden style="margin-top:8px;">
        </div>
        <div class="row-between" style="margin-top:14px;"><span>Subtotal</span><span class="mono" id="subtotal-${mode}"></span></div>
        <div class="row-between" id="discountrow-${mode}" hidden style="color:var(--gold);"><span>Discount</span><span class="mono" id="discountamount-${mode}"></span></div>
        <div class="row-between"><span>Tax</span><span class="mono" id="tax-${mode}"></span></div>
        <div class="row-between" id="tiprow-${mode}" hidden><span>Tip</span><span class="mono" id="tipamount-${mode}"></span></div>
        <div class="row-between total"><span>Total</span><span id="total-${mode}"></span></div>
        <button class="btn btn-sauce" id="submit-${mode}" type="button" style="width:100%; justify-content:center; margin-top:14px; padding:14px;">Place Order</button>
        <div style="text-align:center; margin-top:10px; font-size:11.5px; color:var(--paper-dim);">Paid in person at pickup or delivery. See our <a href="../policies.html" target="_blank" style="color:inherit; text-decoration:underline;">ordering &amp; privacy policies</a>.</div>
      </div>`;
  }
  return `
    <div class="cart-head" style="display:flex; justify-content:space-between; align-items:center;">
      <h3 style="font-size:18px;">New Order</h3>
      <button class="btn-ghost" id="viewqueue-${mode}" type="button">Manage current orders &rarr;</button>
    </div>
    <div class="cart-items" id="cartitems-${mode}"></div>
    <div class="cart-foot">
      <div class="field-group"><label>Order Type</label>
        <div class="seg" id="ordertype-${mode}">
          <button type="button" data-v="phone" aria-pressed="true">Phone</button>
          <button type="button" data-v="walkin">Walk-in</button>
          <button type="button" data-v="delivery">Delivery</button>
        </div>
      </div>
      <div class="field-group"><label>Name</label><input id="custname-${mode}" placeholder="Customer name"></div>
      <div class="field-group"><label>Phone</label><input id="custphone-${mode}" placeholder="(856) 555-0100"></div>
      <div class="field-group" id="addrgroup-${mode}" hidden><label>Delivery Address</label><input id="custaddr-${mode}" placeholder="Street, Lindenwold NJ" autocomplete="street-address">
          <div id="addrinfo-${mode}" style="font-size:11.5px; color:var(--paper-dim); margin-top:6px; min-height:14px;"></div>
        </div>
      <div class="field-group"><label>Notes (optional)</label><input id="custnotes-${mode}" placeholder="Order notes"></div>
      <div class="field-group"><label>Tender</label>
        <div class="seg" id="paymethod-${mode}">
          <button type="button" data-v="cash" aria-pressed="true">Cash</button>
          <button type="button" data-v="card">Card</button>
        </div>
      </div>
      <div class="field-group" id="cashgroup-${mode}"><label>Cash Tendered</label><input id="tendered-${mode}" type="number" step="0.01" placeholder="0.00"></div>
      <div class="field-group" id="tipgroup-${mode}"><label id="tiplabel-${mode}">Add a Tip</label>
        <div class="seg" id="tipseg-${mode}">
          <button type="button" data-v="0" aria-pressed="true">No Tip</button>
          <button type="button" data-v="0.15">15%</button>
          <button type="button" data-v="0.18">18%</button>
          <button type="button" data-v="0.20">20%</button>
          <button type="button" data-v="custom">Custom</button>
        </div>
        <input id="tipcustom-${mode}" type="number" step="0.01" min="0" placeholder="Custom tip amount" hidden style="margin-top:8px;">
      </div>
      <div class="row-between" style="margin-top:10px;"><span>Subtotal</span><span class="mono" id="subtotal-${mode}"></span></div>
      <div class="row-between"><span>Tax</span><span class="mono" id="tax-${mode}"></span></div>
      <div class="row-between" id="tiprow-${mode}" hidden><span>Tip</span><span class="mono" id="tipamount-${mode}"></span></div>
      <div class="row-between total"><span>Total</span><span id="total-${mode}"></span></div>
      <div class="row-between" id="changerow-${mode}" style="color:var(--gold); font-weight:700;"></div>
      <button class="btn btn-sauce" id="submit-${mode}" type="button" style="width:100%; justify-content:center; margin-top:14px; padding:14px;">Ring Up Order</button>
    </div>`;
}

function wireCategoryBar(mode){
  const bar = document.getElementById(`catbar-${mode}`);
  bar.querySelectorAll('.pill').forEach(btn=>{
    btn.addEventListener('click', ()=>{
      bar.querySelectorAll('.pill').forEach(b=>b.setAttribute('aria-pressed','false'));
      btn.setAttribute('aria-pressed','true');
      const cat = btn.getAttribute('data-cat');
      document.querySelectorAll(`#menupane-${mode} .menu-section`).forEach(sec=>{
        sec.hidden = !(cat==='all' || sec.getAttribute('data-section')===cat);
      });
    });
  });
}

function wireItemButtons(mode){
  document.querySelectorAll(`#menupane-${mode} [data-add-cat]`).forEach(btn=>{
    btn.addEventListener('click', ()=>{
      const cat = CATEGORIES.find(c=>c.key===btn.getAttribute('data-add-cat'));
      const it = cat.items[+btn.getAttribute('data-add-idx')];
      if (it.soldOut){
        showToast(mode === 'customer' ? it.name+' is sold out right now' : it.name+' is marked sold out — clear it in Menu Editor to sell it');
        return;
      }
      addLine({ name: it.name, size: it.size||'', unitPrice: it.price, qty:1, notes:'', ref: { kind:'catalog', categoryKey: cat.key, itemName: it.name } });
      showToast(it.name+' added');
    });
  });
}

function renderSpecialtyPizzas(mode){
  const el = document.getElementById(`specialty-${mode}`);
  let html='';
  SPECIALTY_PIZZAS.forEach((p,pi)=>{
    p.sizes.forEach((s,si)=>{
      html += `<button type="button" class="item-card" data-sp="${pi}" data-ss="${si}">
        <span><span class="n">${escapeHtml(p.name)}</span><span class="s">${escapeHtml(s.label)}</span></span>
        <span style="display:flex; align-items:center; gap:8px;"><span class="p">${money(s.price)}</span><span class="plus">+</span></span>
      </button>`;
    });
  });
  el.innerHTML = html;
}
function wireSpecialtyButtons(mode){
  document.querySelectorAll(`#specialty-${mode} [data-sp]`).forEach(btn=>{
    btn.addEventListener('click', ()=>{
      const p = SPECIALTY_PIZZAS[+btn.getAttribute('data-sp')];
      const s = p.sizes[+btn.getAttribute('data-ss')];
      addLine({ name:p.name, size:s.label, unitPrice:s.price, qty:1, notes:'', ref: { kind:'specialty', pizzaName: p.name, sizeLabel: s.label } });
      showToast(p.name+' added');
    });
  });
}
function renderPizzaBuilder(mode){
  const sizeRow = document.getElementById(`sizerow-${mode}`);
  sizeRow.innerHTML = PIZZA_SIZES.map(s => `<button type="button" class="size-opt" data-size="${s.key}" aria-pressed="${orderCtx.pizzaSize===s.key}"><div class="n">${s.label}</div><div class="p">${money(s.base)} + ${money(s.perTopping)}/topping</div></button>`).join('');
  sizeRow.querySelectorAll('.size-opt').forEach(btn=>{
    btn.addEventListener('click', ()=>{ orderCtx.pizzaSize = btn.getAttribute('data-size'); renderPizzaBuilder(mode); });
  });
  const topRow = document.getElementById(`toppingrow-${mode}`);
  topRow.innerHTML = TOPPINGS.map(t => `<button type="button" class="topping-chip" data-t="${escapeHtml(t)}" aria-pressed="${orderCtx.pizzaToppings.has(t)}">${escapeHtml(t)}</button>`).join('');
  topRow.querySelectorAll('.topping-chip').forEach(btn=>{
    btn.addEventListener('click', ()=>{
      const t = btn.getAttribute('data-t');
      if (orderCtx.pizzaToppings.has(t)) orderCtx.pizzaToppings.delete(t); else orderCtx.pizzaToppings.add(t);
      renderPizzaBuilder(mode);
    });
  });
  const sizeObj = PIZZA_SIZES.find(s=>s.key===orderCtx.pizzaSize);
  const total = sizeObj.base + sizeObj.perTopping*orderCtx.pizzaToppings.size;
  document.getElementById(`buildertotal-${mode}`).textContent = money(total);
  document.getElementById(`addpizza-${mode}`).onclick = () => {
    const toppingsArr = Array.from(orderCtx.pizzaToppings);
    addLine({
      name: sizeObj.label.replace(/\s*\(.+\)$/,'') + ' Pizza',
      size: sizeObj.label,
      unitPrice: total,
      qty: 1,
      notes: toppingsArr.length ? toppingsArr.join(', ') : '',
      ref: { kind:'custom', sizeKey: sizeObj.key, toppings: toppingsArr },
    });
    orderCtx.pizzaToppings = new Set();
    renderPizzaBuilder(mode);
    showToast('Pizza added');
  };
}

function wireSeg(segId, stateKey, onChange){
  const seg = document.getElementById(segId);
  seg.querySelectorAll('button').forEach(btn=>{
    btn.addEventListener('click', ()=>{
      seg.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed','false'));
      btn.setAttribute('aria-pressed','true');
      orderCtx[stateKey] = btn.getAttribute('data-v');
      if (onChange) onChange(orderCtx[stateKey]);
    });
  });
}

function updateChangeDue(mode, total){
  const row = document.getElementById(`changerow-${mode}`);
  if (!row) return;
  if (orderCtx.payMethod!=='cash'){ row.innerHTML=''; return; }
  const tenderedInput = document.getElementById(`tendered-${mode}`);
  const tendered = tenderedInput ? parseFloat(tenderedInput.value||'0') : 0;
  if (!tendered){ row.innerHTML = ''; return; }
  row.innerHTML = `<span>Change Due</span><span class="mono">${money(Math.max(0,tendered-total))}</span>`;
}

function updateCartButtonBadge(){
  const badge = document.getElementById('cartBtnBadge');
  if (!badge) return;
  const count = orderCtx.cart.reduce((n,l)=>n+l.qty, 0);
  if (count>0){ badge.hidden = false; badge.textContent = count; }
  else { badge.hidden = true; }
}

function openMobileCart(){
  const pane = document.getElementById('cartpane-customer');
  const backdrop = document.getElementById('cartBackdrop');
  if (pane) pane.classList.add('is-open');
  if (backdrop) backdrop.classList.add('is-open');
  document.body.style.overflow = 'hidden';
}

function closeMobileCart(){
  const pane = document.getElementById('cartpane-customer');
  const backdrop = document.getElementById('cartBackdrop');
  if (pane) pane.classList.remove('is-open');
  if (backdrop) backdrop.classList.remove('is-open');
  document.body.style.overflow = '';
}

function wireMobileCart(mode){
  if (mode !== 'customer') return;
  const cartBtn = document.getElementById('cartBtn');
  const closeBtn = document.getElementById(`cartclose-${mode}`);
  const backdrop = document.getElementById('cartBackdrop');
  if (cartBtn) cartBtn.onclick = openMobileCart;
  if (closeBtn) closeBtn.onclick = closeMobileCart;
  if (backdrop) backdrop.onclick = closeMobileCart;
}

function renderCart(mode){
  if (!mode) return;
  saveCartToStorage();
  const wrap = document.getElementById(`cartitems-${mode}`);
  if (!wrap) return;
  if (!orderCtx.cart.length){
    wrap.innerHTML = `<div class="cart-empty">Nothing in the order yet.<br>Tap items on the left to add them.</div>`;
  } else {
    wrap.innerHTML = orderCtx.cart.map(l => `
      <div class="cart-line">
        <div style="flex:1;">
          <div class="n">${escapeHtml(lineLabel(l))}</div>
          ${l.notes ? `<div class="meta">${escapeHtml(l.notes)}</div>` : ''}
          <div class="qty" style="margin-top:6px;">
            <button type="button" class="qty-btn" data-key="${escapeHtml(l._key)}" data-d="-1">&minus;</button>
            <span class="mono">${l.qty}</span>
            <button type="button" class="qty-btn" data-key="${escapeHtml(l._key)}" data-d="1">+</button>
          </div>
        </div>
        <div class="p">${money(l.unitPrice*l.qty)}</div>
      </div>`).join('');
    wrap.querySelectorAll('.qty-btn').forEach(btn=>{
      btn.addEventListener('click', ()=> changeQty(btn.getAttribute('data-key'), +btn.getAttribute('data-d')));
    });
  }
  if (orderCtx.tipPct != null){
    const rawSubtotal = orderCtx.cart.reduce((s,it)=> s + it.unitPrice*it.qty, 0);
    orderCtx.tip = Math.round(rawSubtotal * orderCtx.tipPct * 100) / 100;
  }
  const totals = computeTotals(orderCtx.cart, orderCtx.tip, orderCtx.discountAmount);
  document.getElementById(`subtotal-${mode}`).textContent = money(totals.subtotal);
  document.getElementById(`tax-${mode}`).textContent = money(totals.tax);
  const discountRow = document.getElementById(`discountrow-${mode}`);
  const discountAmountEl = document.getElementById(`discountamount-${mode}`);
  if (discountRow && discountAmountEl){
    discountRow.hidden = totals.discount <= 0;
    discountAmountEl.textContent = '-' + money(totals.discount);
  }
  const tipRow = document.getElementById(`tiprow-${mode}`);
  const tipAmountEl = document.getElementById(`tipamount-${mode}`);
  if (tipRow && tipAmountEl){
    tipRow.hidden = totals.tip <= 0;
    tipAmountEl.textContent = money(totals.tip);
  }
  document.getElementById(`total-${mode}`).textContent = money(totals.total);
  if (mode==='pos') updateChangeDue(mode, totals.total);
  const submitBtn = document.getElementById(`submit-${mode}`);
  if (submitBtn) submitBtn.disabled = orderCtx.cart.length===0;
  if (mode==='customer') updateCartButtonBadge();
}

function renderOrderLayout(mode){
  const view = document.getElementById(mode==='customer' ? 'view-customer' : 'view-pos');
  view.innerHTML = `
    <div class="order-layout">
      <div class="order-menu-pane" id="menupane-${mode}"></div>
      <div class="order-cart-pane" id="cartpane-${mode}"></div>
    </div>`;
  document.getElementById(`menupane-${mode}`).innerHTML = buildMenuPaneHTML(mode);
  document.getElementById(`cartpane-${mode}`).innerHTML = buildCartPaneHTML(mode);
  wireCategoryBar(mode);
  wireItemButtons(mode);
  wireMobileCart(mode);
  renderSpecialtyPizzas(mode);
  wireSpecialtyButtons(mode);
  renderPizzaBuilder(mode);
  wireSeg(`ordertype-${mode}`, 'orderType', (v) => {
    const addrGroup = document.getElementById(`addrgroup-${mode}`);
    if (addrGroup) addrGroup.hidden = (v !== 'delivery');
    const tipLabel = document.getElementById(`tiplabel-${mode}`);
    if (tipLabel) tipLabel.textContent = v === 'delivery' ? 'Add a Tip for Your Driver' : 'Add a Tip for the Counter';
    if (v === 'delivery' && mode === 'customer'){
      const addrInputEl = document.getElementById(`custaddr-${mode}`);
      const saved = CustomerAccount.profile && CustomerAccount.profile.preferences && CustomerAccount.profile.preferences.savedAddress;
      if (addrInputEl && saved && !addrInputEl.value){
        addrInputEl.value = saved;
        addrInputEl.dispatchEvent(new Event('input'));
      }
    }
  });
  const addrInput = document.getElementById(`custaddr-${mode}`);
  const addrInfo = document.getElementById(`addrinfo-${mode}`);
  const addrCheckBtn = document.getElementById(`addrcheck-${mode}`);
  if (addrInput && addrInfo && typeof wireDeliveryLookup === 'function'){
    wireDeliveryLookup(addrInput, addrInfo, (result) => {
      orderCtx.deliveryInfo = result;
    }, addrCheckBtn);
  }
  const promoApplyBtn = document.getElementById(`promoapply-${mode}`);
  if (promoApplyBtn) promoApplyBtn.addEventListener('click', () => applyPromoCode(mode));
  const tipSeg = document.getElementById(`tipseg-${mode}`);
  const tipCustom = document.getElementById(`tipcustom-${mode}`);
  if (tipSeg){
    tipSeg.querySelectorAll('button').forEach(btn=>{
      btn.addEventListener('click', () => {
        tipSeg.querySelectorAll('button').forEach(b=>b.setAttribute('aria-pressed','false'));
        btn.setAttribute('aria-pressed','true');
        const v = btn.getAttribute('data-v');
        const subtotal = computeTotals(orderCtx.cart, 0).subtotal;
        if (v === 'custom'){
          tipCustom.hidden = false;
          tipCustom.focus();
          orderCtx.tip = Number(tipCustom.value) || 0;
          orderCtx.tipPct = null;
        } else {
          tipCustom.hidden = true;
          orderCtx.tipPct = Number(v);
          orderCtx.tip = Math.round(subtotal * Number(v) * 100) / 100;
        }
        renderCart(mode);
      });
    });
  }
  if (tipCustom){
    tipCustom.addEventListener('input', () => {
      orderCtx.tip = Number(tipCustom.value) || 0;
      orderCtx.tipPct = null;
      renderCart(mode);
    });
  }
  wireSeg(`paymethod-${mode}`, 'payMethod', () => {
    if (mode === 'pos'){
      const cashGroup = document.getElementById(`cashgroup-${mode}`);
      if (cashGroup) cashGroup.hidden = (orderCtx.payMethod !== 'cash');
      renderCart(mode);
    }
  });
  if (mode === 'pos'){
    const tenderedInput = document.getElementById(`tendered-${mode}`);
    if (tenderedInput) tenderedInput.addEventListener('input', () => renderCart(mode));
    const queueBtn = document.getElementById(`viewqueue-${mode}`);
    if (queueBtn) queueBtn.addEventListener('click', () => renderPosQueue());
  }
  const banner = document.getElementById(`todaybanner-${mode}`);
  if (banner){
    banner.addEventListener('click', () => {
      const today = SPECIALS_BY_DAY[new Date().getDay()];
      addLine({ name: today.name, size:'', unitPrice: today.price, qty:1, notes:'Daily special', ref: { kind:'special' } });
      showToast(today.name + ' added');
    });
  }
  const submitBtn = document.getElementById(`submit-${mode}`);
  if (mode === 'customer' && ORDERS_PAUSED){
    submitBtn.disabled = true;
    submitBtn.textContent = 'Online Ordering Paused';
  }
  submitBtn.addEventListener('click', () => mode === 'customer' ? submitCustomerOrder() : submitPosOrder());
  renderCart(mode);
}
