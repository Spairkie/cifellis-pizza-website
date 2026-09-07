-- =========================================================================
-- Menu configuration
-- =========================================================================
-- Replaces the menu/pricing constants that used to be hardcoded directly
-- in order/index.html and staff/index.html (TAX_RATE, PIZZA_SIZES,
-- TOPPINGS, SPECIALTY_PIZZAS, CATEGORIES, SPECIALS_BY_DAY). Both files
-- still carry those same values as a hardcoded fallback (DEFAULT_MENU),
-- so nothing breaks if this table doesn't exist yet or a fetch fails --
-- this migration only turns the live values into something an admin can
-- edit from Staff Hub > Menu Editor, without a code deploy.
--
-- Run this once in the Supabase SQL Editor (same as schema.sql was run).
-- Safe to re-run: guards with "if not exists" / "or replace" and the
-- seed insert is a no-op if row id=1 already exists.

create table if not exists public.menu_config (
  id int primary key default 1,
  data jsonb not null,
  version int not null default 1,
  "updatedAt" timestamptz not null default now(),
  "updatedBy" uuid references auth.users(id),
  constraint menu_config_singleton check (id = 1)
);

alter table public.menu_config enable row level security;

drop policy if exists menu_config_public_read on public.menu_config;
create policy menu_config_public_read on public.menu_config
  for select
  to anon, authenticated
  using (true);

drop policy if exists menu_config_admin_update on public.menu_config;
create policy menu_config_admin_update on public.menu_config
  for update
  to authenticated
  using (exists (
    select 1 from public.staff s where s.id = auth.uid() and s.active and s."isAdmin"
  ))
  with check (exists (
    select 1 from public.staff s where s.id = auth.uid() and s.active and s."isAdmin"
  ));

-- No insert/delete policy for anyone: this is a singleton row seeded
-- once below and only ever updated after that, never replaced or removed.

create or replace function public.bump_menu_config_version()
returns trigger language plpgsql as $fn$
begin
  new.version := old.version + 1;
  new."updatedAt" := now();
  new."updatedBy" := auth.uid();
  return new;
end;
$fn$;

drop trigger if exists menu_config_bump_version on public.menu_config;
create trigger menu_config_bump_version
  before update on public.menu_config
  for each row execute function public.bump_menu_config_version();

insert into public.menu_config (id, data)
values (1, $json${"TAX_RATE": 0.06625, "PIZZA_SIZES": [{"key": "personal", "label": "Personal Pan (9\")", "base": 8, "perTopping": 1}, {"key": "medium", "label": "Medium (14\")", "base": 14.5, "perTopping": 3}, {"key": "large", "label": "Large (16\")", "base": 15.99, "perTopping": 3.5}, {"key": "sicilian", "label": "Sicilian (16x16\")", "base": 17.99, "perTopping": 4}], "TOPPINGS": ["Pepperoni", "Sausage", "Bacon", "Meatball", "Ham", "Extra Cheese", "Green Pepper", "Onion", "Black Olive", "Mushroom", "Anchovy", "Pineapple", "Spinach", "Broccoli"], "SPECIALTY_PIZZAS": [{"name": "Bacon BBQ Chicken Ranch", "sizes": [{"label": "Medium", "price": 24}, {"label": "Large", "price": 26}]}, {"name": "Buffalo Chicken", "sizes": [{"label": "Medium", "price": 24}, {"label": "Large", "price": 26}]}, {"name": "Hawaiian", "sizes": [{"label": "Medium", "price": 20.5}, {"label": "Large", "price": 22.99}, {"label": "Sicilian", "price": 24.99}]}, {"name": "White Pie", "sizes": [{"label": "Medium", "price": 14.5}, {"label": "Large", "price": 15.99}, {"label": "Sicilian", "price": 17.99}]}, {"name": "The Works", "sizes": [{"label": "Medium", "price": 24}, {"label": "Large", "price": 25.99}, {"label": "Sicilian", "price": 29.99}]}], "CATEGORIES": [{"key": "panzarotti", "label": "Panzarotti", "note": "Deep fried and golden brown", "items": [{"name": "Panzarotti", "price": 8.25, "desc": "Add $0.75 per extra ingredient"}]}, {"key": "stromboli", "label": "Stromboli", "photo": "../images/menu/stromboli.jpg", "placeholder": "../images/menu/stromboli.svg", "items": [{"name": "Cheese Stromboli", "price": 17.99, "desc": "+$2.50 per topping, +$5.00 steak or chicken"}, {"name": "Steak & Onion Stromboli", "price": 24.99}]}, {"key": "calzones", "label": "Calzones", "photo": "../images/menu/calzone.jpg", "placeholder": "../images/menu/calzone.svg", "items": [{"name": "Calzone", "price": 14.99, "desc": "Ham, ricotta, mozzarella and sauce"}]}, {"key": "turnover", "label": "Pizza Turnover", "items": [{"name": "Pizza Turnover", "price": 13.5, "desc": "Mozzarella and pizza sauce, $1 per extra ingredient"}]}, {"key": "wings", "label": "Wings", "note": "All wings come with bread and blue cheese", "photo": "../images/menu/wings.jpg", "placeholder": "../images/menu/wings.svg", "items": [{"name": "Wings", "size": "8 pc", "price": 9.5}, {"name": "Wings", "size": "12 pc", "price": 14.99}, {"name": "Wings", "size": "16 pc", "price": 18.99}, {"name": "Wings", "size": "24 pc", "price": 27.99}]}, {"key": "steaks", "label": "Steaks", "note": "Chicken made with 100% boneless, skinless breast meat", "items": [{"name": "Plain Steak", "price": 11}, {"name": "Cheese Steak", "price": 12}, {"name": "Chicken Cheese Steak", "price": 12}, {"name": "Bacon Cheese Steak", "price": 13}, {"name": "Cheese Steak Sub", "price": 13}, {"name": "Chicken Cheese Steak Sub", "price": 13}, {"name": "Mushroom Cheese Steak", "price": 13}, {"name": "Pepperoni Cheese Steak", "price": 13}, {"name": "Pizza Steak", "price": 13}, {"name": "Buffalo Chicken Cheese Steak", "price": 13}, {"name": "Broccoli Garlic & Oil Chicken Cheese Steak", "price": 13}, {"name": "Cheese Steak Special", "price": 13.75}, {"name": "Cheese Steak Platter", "price": 14.99}]}, {"key": "hoagies", "label": "Hoagies", "note": "All hoagies made with lettuce, tomato, onion and oil", "photo": "../images/menu/hoagie.jpg", "placeholder": "../images/menu/hoagie.svg", "items": [{"name": "Mixed Cheese", "price": 11}, {"name": "American", "price": 11.5}, {"name": "Ham & Cheese", "price": 12}, {"name": "Italian", "price": 12}, {"name": "Turkey & Cheese", "price": 12}, {"name": "Roast Beef, Provolone or American", "price": 13}, {"name": "Fried Fish Hoagie", "price": 13}]}, {"key": "pasta", "label": "Pasta", "note": "Served with soup, salad and garlic bread, spaghetti or ziti", "photo": "../images/menu/pasta.jpg", "placeholder": "../images/menu/pasta.svg", "items": [{"name": "Tomato Sauce", "price": 12.99}, {"name": "Meatballs", "price": 16.99}, {"name": "Sausage", "price": 16.99}]}, {"key": "parm", "label": "Parmigiana Dinners", "note": "Served with salad and garlic bread or a side of spaghetti/ziti", "items": [{"name": "Eggplant Parmigiana", "price": 15.99}, {"name": "Chicken Cutlet Parmigiana", "price": 16.99}]}, {"key": "hotsand", "label": "Hot Sandwiches", "items": [{"name": "Homemade Meatball Sandwich", "price": 11.5}, {"name": "Eggplant Parmigiana", "price": 11}, {"name": "Homemade Meatball Parmigiana", "price": 12.5}, {"name": "Chicken Parmigiana", "price": 12.5}, {"name": "Sausage Parmigiana", "price": 12.5}, {"name": "Hot Roast Beef", "price": 12}, {"name": "Hot Roast Beef with Cheese", "price": 13}, {"name": "Sausage Supreme", "price": 12.99}]}, {"key": "italian", "label": "Italian Specialties", "note": "Served with soup, salad and garlic bread", "items": [{"name": "Baked Ziti", "price": 16.99}, {"name": "Cheese Ravioli", "price": 16.99}, {"name": "Stuffed Shells Parmigiana", "price": 16.99}]}, {"key": "platters", "label": "Platters", "items": [{"name": "BLT Club", "price": 12.99}, {"name": "Chicken Finger Platter", "price": 13.99}, {"name": "Ham & Cheese Club", "price": 13.99}, {"name": "Chicken Club", "price": 14.99}, {"name": "Roast Beef Club", "price": 14.99}, {"name": "Turkey Club", "price": 14.99}, {"name": "Shrimp Platter", "price": 14.99}]}, {"key": "burgers", "label": "Quarter Pound Burgers", "photo": "../images/menu/burger.jpg", "placeholder": "../images/menu/burger.svg", "items": [{"name": "Hamburger", "price": 7}, {"name": "Cheeseburger", "price": 8}, {"name": "Bacon Cheeseburger", "price": 9}, {"name": "Pizza Burger", "price": 9}, {"name": "Cheese Burger Sub", "price": 13}]}, {"key": "sides", "label": "Side Orders", "items": [{"name": "French Fries", "price": 5.75}, {"name": "Onion Rings", "price": 8}, {"name": "Poppers", "size": "Cheddar", "price": 8}, {"name": "Breaded Mushrooms", "price": 8.5}, {"name": "Broccoli Bites", "price": 8.5}, {"name": "Meatballs", "price": 8.5}, {"name": "Mozzarella Sticks", "price": 8.5}, {"name": "Pizza Fries", "size": "Small", "price": 8.5}, {"name": "Pizza Fries", "size": "Large", "price": 10.5}, {"name": "Sausage", "price": 8.5}, {"name": "Fried Tomato", "price": 9}, {"name": "Cheese Fries", "size": "Small", "price": 6.5}, {"name": "Cheese Fries", "size": "Large", "price": 9}, {"name": "Loaded Fries", "size": "Small", "price": 9.5}, {"name": "Loaded Fries", "size": "Large", "price": 10.5}, {"name": "Homemade Cole Slaw", "size": "Pint", "price": 3.5}, {"name": "Homemade Cole Slaw", "size": "Quart", "price": 7}, {"name": "Something Sweet Zeppoli", "size": "Small", "price": 4}, {"name": "Something Sweet Zeppoli", "size": "Large", "price": 8}]}, {"key": "soups", "label": "Soups", "items": [{"name": "Pasta Faggioli", "size": "Small", "price": 4.99}, {"name": "Pasta Faggioli", "size": "Quart", "price": 8.99}, {"name": "Chili", "size": "Small, winter", "price": 6.5}, {"name": "Chili", "size": "Quart, winter", "price": 11.99}]}, {"key": "salads", "label": "Salads", "photo": "../images/menu/salad.jpg", "placeholder": "../images/menu/salad.svg", "items": [{"name": "Tossed Salad", "price": 7.99}, {"name": "Antipasta", "price": 12.99}, {"name": "Chef Salad", "price": 12.99}, {"name": "Chicken Caesar Salad", "price": 12.99}, {"name": "Grilled Chicken Salad", "price": 12.99}]}, {"key": "breakfast", "label": "Breakfast", "items": [{"name": "Grilled Cheese", "price": 7, "desc": "+$1 to add ham or bacon"}, {"name": "Bacon, Lettuce & Tomato", "price": 8}, {"name": "Pepper and Egg", "price": 10}, {"name": "Bacon, Egg and Cheese", "price": 11}, {"name": "Sausage, Egg and Cheese", "price": 11}, {"name": "Pork Roll, Egg and Cheese", "price": 11}]}, {"key": "knots", "label": "Garlic Knots", "items": [{"name": "Garlic Knots", "size": "6 pc", "price": 4.75}]}, {"key": "drinks", "label": "Drinks", "note": "We carry Pepsi products", "items": [{"name": "Bottled Soda", "size": "20 oz", "price": 2.75}, {"name": "Bottled Soda", "size": "2 Liter", "price": 4.5}]}], "SPECIALS_BY_DAY": {"0": {"name": "4 Original Panzarotti", "price": 25.99}, "1": {"name": "2 Cheese Steaks", "price": 20.99}, "2": {"name": "Large Pizza", "price": 13.99}, "3": {"name": "Sicilian Pie", "price": 15.99}, "4": {"name": "2 Chicken Finger Platters", "price": 22.99}, "5": {"name": "Stromboli + 2 Liter Soda", "price": 18.5}, "6": {"name": "Cheese Steak Platter", "price": 13.99}}}$json$::jsonb)
on conflict (id) do nothing;
