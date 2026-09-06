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
          const { data: rows, error } = await client.from(name).insert(data).select('id').single();
          if (error) throw error;
          return { id: rows.id };
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

    return { collection, auth: client.auth };
  }

  global.createSupabaseDb = createSupabaseDb;
})(window);
