// Edge Function: webhook receptor de Stripe. Escucha checkout.session.completed,
// verifica la firma y marca a la alumna como pagada este mes en Supabase.
//
// IMPORTANTE: desplegar con --no-verify-jwt (Stripe no manda un JWT de Supabase,
// así que la verificación de JWT del gateway hay que desactivarla para esta función).
//
// Configurar en Stripe Dashboard → Developers → Webhooks:
//   URL: https://<project-ref>.supabase.co/functions/v1/stripe-webhook
//   Evento: checkout.session.completed
//
// Secrets necesarios: STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET
// SUPABASE_URL y SUPABASE_SERVICE_ROLE_KEY ya vienen inyectadas por Supabase.

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import Stripe from 'https://esm.sh/stripe@17?target=deno';

const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
  apiVersion: '2024-06-20',
});
const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')!;

const sbAdmin = createClient(
  Deno.env.get('SUPABASE_URL')!,
  Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
);

Deno.serve(async (req) => {
  const signature = req.headers.get('stripe-signature');
  const body = await req.text();

  if (!signature) {
    return new Response('Falta stripe-signature', { status: 400 });
  }

  let event: Stripe.Event;
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature, webhookSecret);
  } catch (err) {
    console.error('[stripe-webhook] Firma inválida:', (err as Error).message);
    return new Response('Firma inválida', { status: 400 });
  }

  if (event.type === 'checkout.session.completed') {
    const session = event.data.object as Stripe.Checkout.Session;
    const alumnoId = session.metadata?.alumno_id;

    if (!alumnoId) {
      console.error('[stripe-webhook] Sesión sin alumno_id en metadata:', session.id);
      return new Response('ok', { status: 200 });
    }

    const importe = (session.amount_total || 0) / 100;
    const fechaPago = new Date();
    const mesCorrespondiente = fechaPago.toISOString().slice(0, 7); // 'YYYY-MM'

    const { error: pagoErr } = await sbAdmin
      .from('pagos')
      .upsert(
        {
          alumno_id: alumnoId,
          fecha_pago: fechaPago.toISOString(),
          importe,
          mes_correspondiente: mesCorrespondiente,
          stripe_session_id: session.id,
        },
        { onConflict: 'stripe_session_id', ignoreDuplicates: true }
      );
    if (pagoErr) console.error('[stripe-webhook] Error insertando pago:', pagoErr.message);

    const { error: alumnoErr } = await sbAdmin
      .from('alumnos')
      .update({
        ultimo_pago_mes: mesCorrespondiente,
        ultimo_pago_fecha: fechaPago.toISOString(),
        ultimo_pago_importe: importe,
      })
      .eq('id', alumnoId);
    if (alumnoErr) console.error('[stripe-webhook] Error actualizando alumno:', alumnoErr.message);
  }

  return new Response('ok', { status: 200 });
});
