/*
 * Minimal Firestore-shaped adapter over Supabase (Postgres + Realtime).
 *
 * The Order Hub app was originally written against a small Firestore-like
 * surface: db.collection(name).add(data), .doc(id).update(patch),
 * .orderBy(field, dir).onSnapshot(next, error). Rather than rewrite every
 * view for a different API, this file implements that same small surface
 * on top of Supabase, so the app code did not need to change.
 *
 * Table columns are created with the exact camelCase names the app already
 * uses (ticket, customerName, orderType, payMethod, createdAt, ...), so no
 * field-name translation layer is needed either. See supabase/schema.sql.
 *
 * Also re-exposes the underlying Supabase client's `auth` namespace, so
 * the Staff Hub can sign staff in/out without creating a second client
 * (Supabase recommends a single client instance per page).
 */
(function (global) {
  function createSupabaseDb(client) {
    function collection(name) {
      let orderField = null;
      let orderDir = 'asc';

      const api = {
        orderBy(field, dir) {
          orderField = field;
          orderDir = dir === 'desc' ? 'desc' : 'asc';
          return api;
        },

        doc(id) {
          return {
            id,
            async update(patch) {
              const { error } = await client.from(name).update(patch).eq('id', id);
              if (error) throw error;
            },
            async set(data) {
              const { error } = await client.from(name).upsert(Object.assign({ id }, data));
              if (error) throw error;
            },
            async delete() {
              const { error } = await client.from(name).delete().eq('id', id);
              if (error) throw error;
            },
            async get() {
              const { data, error } = await client.from(name).select('*').eq('id', id).maybeSingle();
              if (error) throw error;
              return { id, exists: !!data, data: () => data || undefined };
            },
          };
        },

        async add(data) {
          // Deliberately no .select() here: chaining .select() after
          // insert makes PostgREST read the new row back before
          // returning, which requires a SELECT policy. The anon role
          // (Customer Kiosk) only has INSERT on orders by design (see
          // supabase/schema.sql), so a request that also required SELECT
          // gets rejected as an RLS violation even though the insert
          // itself is allowed. Nothing in this app needs the row back
          // (the ticket number is generated client-side before this is
          // ever called), so a plain insert avoids the problem entirely.
          const { error } = await client.from(name).insert(data);
          if (error) throw error;
          return { id: data.id || null };
        },

        async get() {
          // One-shot fetch of the whole (RLS-filtered) table -- for
          // screens that just need a snapshot once (e.g. populating a
          // dropdown) rather than a live subscription. Same doc shape
          // as onSnapshot's callback gets, minus the ongoing realtime
          // channel.
          let q = client.from(name).select('*');
          if (orderField) q = q.order(orderField, { ascending: orderDir === 'asc' });
          const { data, error } = await q;
          if (error) throw error;
          const docs = (data || []).map((row) => ({ id: row.id, exists: true, data: () => row }));
          return { docs };
        },

        onSnapshot(next, error) {
          let closed = false;

          async function refetch() {
            if (closed) return;
            let q = client.from(name).select('*');
            if (orderField) q = q.order(orderField, { ascending: orderDir === 'asc' });
            const { data, error: qErr } = await q;
            if (qErr) {
              if (error) error({ code: qErr.code || 'unavailable', message: qErr.message });
              return;
            }
            const docs = (data || []).map((row) => ({
              id: row.id,
              exists: true,
              data: () => row,
            }));
            next({ docs });
          }

          refetch();

          const channel = client
            .channel('orders-changes-' + Math.random().toString(36).slice(2))
            .on('postgres_changes', { event: '*', schema: 'public', table: name }, refetch)
            .subscribe();

          return function unsubscribe() {
            closed = true;
            client.removeChannel(channel);
          };
        },
      };

      return api;
    }

    // Passthrough for Postgres functions (security definer RPCs like
    // rate_delivery/redeem_promo_code) that need to run server-side
    // logic RLS alone can't express -- general-purpose, not tied to any
    // one caller.
    async function rpc(name, params) {
      const { data, error } = await client.rpc(name, params);
      if (error) throw error;
      return data;
    }

    return { collection, auth: client.auth, rpc };
  }

  global.createSupabaseDb = createSupabaseDb;
})(window);
