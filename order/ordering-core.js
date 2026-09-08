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
    return false;
  }
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
