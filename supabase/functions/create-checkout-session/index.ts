// Edge Function: crea una Stripe Checkout Session dinámica para la alumna
// autenticada, con el precio correcto según su frecuencia y su user_id en
// la metadata (así el webhook sabe a quién marcar como pagada).
//
// Invocar desde el frontend con: sb.functions.invoke('create-checkout-session')
// Supabase adjunta automáticamente el JWT de la sesión en el header Authorization.
//
// Secrets necesarios (supabase secrets set ...): STRIPE_SECRET_KEY, NOMBRE_TALLER, APP_URL
// (APP_URL = dirección completa de la página de la app, p.ej. https://tutaller.com/area-de-alumnos)
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY ya vienen inyectadas por Supabase.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Stripe from 'https://esm.sh/stripe@17?target=deno';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2024-06-20',
});

// Céntimos de euro. Cambiar precios = editar aquí y redesplegar la función.
const PRECIOS: Record<string, { cents: number; label: string }> = {
  '1vez': { cents: 5500, label: '1 vez por semana — Cuota mensual' },
  '2veces': { cents: 10000, label: '2 veces por semana — Cuota mensual' },
};

const CORS_HEADERS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: CORS_HEADERS });
  }

  try {
    const authHeader = req.headers.get('Authorization');
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'No autenticado' }), {
        status: 401,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const sb = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const jwt = authHeader.replace('Bearer ', '');
    const { data: userData, error: userErr } = await sb.auth.getUser(jwt);
    if (userErr || !userData?.user) {
      return new Response(JSON.stringify({ error: 'Sesión inválida' }), {
        status: 401,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    const { data: alumno, error: alumnoErr } = await sb
      .from('alumnos')
      .select('id, nombre_alumno, email, frecuencia, precio_mensual')
      .eq('user_id', userData.user.id)
      .single();

    if (alumnoErr || !alumno) {
      return new Response(JSON.stringify({ error: 'Alumna no encontrada' }), {
        status: 404,
        headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
      });
    }

    // precio_mensual es una cuota específica de la alumna (p.ej. una tarifa
    // distinta) que sobrescribe el precio por defecto según frecuencia.
    const precioDefault = PRECIOS[alumno.frecuencia] || PRECIOS['1vez'];
    const precio = alumno.precio_mensual
      ? { cents: Math.round(alumno.precio_mensual * 100), label: precioDefault.label }
      : precioDefault;
    const appUrl = Deno.env.get('APP_URL') || req.headers.get('origin') || '';
    const nombreTaller = Deno.env.get('NOMBRE_TALLER') || 'Taller';

    const session = await stripe.checkout.sessions.create({
      mode: 'payment',
      payment_method_types: ['card'],
      customer_email: alumno.email || undefined,
      line_items: [
        {
          price_data: {
            currency: 'eur',
            product_data: { name: `${nombreTaller} — ${precio.label}` },
            unit_amount: precio.cents,
          },
          quantity: 1,
        },
      ],
      metadata: {
        alumno_id: alumno.id,
        user_id: userData.user.id,
        frecuencia: alumno.frecuencia,
      },
      success_url: `${appUrl}?pago=ok`,
      cancel_url: `${appUrl}?pago=cancelado`,
    });

    return new Response(JSON.stringify({ url: session.url }), {
      status: 200,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  } catch (err) {
    console.error('[create-checkout-session]', err);
    return new Response(JSON.stringify({ error: 'Error creando la sesión de pago' }), {
      status: 500,
      headers: { ...CORS_HEADERS, 'Content-Type': 'application/json' },
    });
  }
});
