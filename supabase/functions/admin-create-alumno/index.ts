// Edge Function: da de alta a una alumna nueva. Solo la admin puede llamarla.
// Si crear_cuenta=true, crea también su login (Admin API — necesita service
// role, por eso no se puede hacer directamente desde el navegador: usar
// sb.auth.signUp() ahí cerraría/reemplazaría la sesión de la propia admin).
//
// Invocar desde el frontend con: sb.functions.invoke('admin-create-alumno', {body:{...}})
// Se despliega CON verificación de JWT (comportamiento por defecto, sin
// --no-verify-jwt) porque solo debe poder llamarla alguien con sesión.
//
// Secrets necesarios (supabase secrets set ...): ADMIN_EMAIL, CONTRASENA_INICIAL
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY ya vienen inyectadas por Supabase.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const ADMIN_EMAIL = Deno.env.get('ADMIN_EMAIL')!;
// Contraseña con la que se crean las cuentas nuevas (la alumna puede cambiarla desde su perfil).
const DEFAULT_PASSWORD = Deno.env.get('CONTRASENA_INICIAL')!;

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

function jsonResponse(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
  });
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) return jsonResponse({ error: 'No autenticado' }, 401);

    const sb = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const jwt = authHeader.replace('Bearer ', '');
    const { data: userData, error: userErr } = await sb.auth.getUser(jwt);
    if (userErr || !userData?.user) return jsonResponse({ error: 'Sesión inválida' }, 401);
    if (userData.user.email !== ADMIN_EMAIL) return jsonResponse({ error: 'No autorizada' }, 403);

    const body = await req.json();
    const nombre_alumno: string = (body.nombre_alumno || '').trim();
    const email: string = (body.email || '').trim().toLowerCase();
    const telefono: string = (body.telefono || '').trim();
    const frecuencia: string = body.frecuencia === '2veces' ? '2veces' : '1vez';
    const tipo_clase_default: string = body.tipo_clase_default === 'Modelado' ? 'Modelado' : 'Torno';
    const dia_habitual: string = (body.dia_habitual || '').trim();
    const hora_habitual: string = (body.hora_habitual || '').trim();
    const crear_cuenta: boolean = !!body.crear_cuenta;

    if (!nombre_alumno) return jsonResponse({ error: 'Falta el nombre' }, 400);
    if (crear_cuenta && !email) return jsonResponse({ error: 'Falta el email para crear la cuenta' }, 400);

    let user_id: string | null = null;
    if (crear_cuenta) {
      const { data: created, error: createErr } = await sb.auth.admin.createUser({
        email,
        password: DEFAULT_PASSWORD,
        email_confirm: true,
      });
      if (createErr || !created?.user) {
        const msg = /already been registered|already registered/i.test(createErr?.message || '')
          ? 'Ya existe una cuenta con ese email'
          : 'Error creando la cuenta de acceso';
        return jsonResponse({ error: msg }, 400);
      }
      user_id = created.user.id;
    }

    const { data: alumno, error: insertErr } = await sb
      .from('alumnos')
      .insert({
        nombre_alumno,
        email: email || null,
        telefono: telefono || null,
        user_id,
        frecuencia,
        tipo_clase_default,
        dia_habitual: dia_habitual || null,
        hora_habitual: hora_habitual || null,
        tipo_usuario: 'alumno',
        clases_recuperar: 0,
        activo: true,
      })
      .select()
      .single();

    if (insertErr) {
      console.error('[admin-create-alumno]', insertErr);
      return jsonResponse({ error: 'Error guardando la alumna' }, 500);
    }

    return jsonResponse({ alumno, password: crear_cuenta ? DEFAULT_PASSWORD : null });
  } catch (err) {
    console.error('[admin-create-alumno]', err);
    return jsonResponse({ error: 'Error inesperado' }, 500);
  }
});
