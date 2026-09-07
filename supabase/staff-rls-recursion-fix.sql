-- =========================================================================
-- Hotfix: infinite recursion in public.staff's RLS policies
-- =========================================================================
-- Found 2026-09-07 while building the Menu Editor: EVERY query against
-- public.staff (as any signed-in staff member, for any operation --
-- select, insert, or update) has always failed with
--   "infinite recursion detected in policy for relation \"staff\""
-- since the original schema.sql was first run. The three policies on
-- staff (staff_select_staff, staff_admin_insert, staff_admin_update)
-- each checked admin/active status by selecting from public.staff
-- itself inside their own USING/WITH CHECK clause -- which re-triggers
-- the same policy on every row check, forever, until Postgres gives up
-- and errors.
--
-- Practical effect: App.isAdmin has silently evaluated to false for
-- every staff member, always (the error was caught and swallowed in
-- loadMyStaffRow()'s try/catch in staff/index.html, so nothing visibly
-- crashed -- Driver Roster's Approve button just never worked for
-- anyone, and would have failed with this same error even if it had
-- been clickable, since staff_admin_insert/update have the identical
-- bug). This went unnoticed because no one had tested Driver Roster's
-- approve flow with a real admin account before now.
--
-- The fix: public.is_staff() and public.is_admin() already existed in
-- schema.sql as `security definer` functions built for exactly this --
-- bypassing RLS for their own internal lookup so the outer policy that
-- calls them doesn't recurse -- but the three staff policies were never
-- wired up to use them. This makes them use them.
--
-- Run this once in the Supabase SQL Editor. Safe to run more than once.
-- schema.sql has also been corrected to match (function definitions
-- moved before these policies, policies updated to call them), so this
-- file only exists to patch a project that already ran the old version.

drop policy if exists "staff_select_staff" on public.staff;
create policy "staff_select_staff" on public.staff
  for select to authenticated
  using (public.is_staff());

drop policy if exists "staff_admin_insert" on public.staff;
create policy "staff_admin_insert" on public.staff
  for insert to authenticated
  with check (public.is_admin());

drop policy if exists "staff_admin_update" on public.staff;
create policy "staff_admin_update" on public.staff
  for update to authenticated
  using (public.is_admin())
  with check (public.is_admin());
