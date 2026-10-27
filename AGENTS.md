# Guía para asistentes de IA

Este archivo es para la IA (Claude, ChatGPT/Codex, Cursor, Copilot, Gemini…) que ayude a instalar o adaptar esta app. Léelo entero antes de tocar nada. La guía de instalación para personas está en [README.md](README.md). Quien te pide ayuda suele ser la persona que lleva un taller de cerámica, no una programadora: explica los pasos con lenguaje sencillo y pide confirmación antes de cambios en la base de datos de producción.

## Cómo está hecha

- **Frontend:** un único archivo, `index.html`, con HTML, CSS y JS juntos. No hay build, npm ni framework. Las librerías se cargan por CDN (`@supabase/supabase-js@2`). Suele publicarse pegándolo en una página de WordPress (por eso hay CSS que oculta el título de WordPress y la sesión se guarda en `sessionStorage` con `storageKey: 'taller-auth'`).
- **Backend:** Supabase (Postgres + Auth). Todo el esquema está en `supabase/esquema.sql`: tablas `alumnos`, `clases`, `reservas`, `recuperaciones`, `pagos` y `config`.
- **Funciones de servidor** (Supabase Edge Functions, Deno), en `supabase/functions/`:
  - `admin-create-alumno`: alta de alumnas desde el panel. Usa la service role key.
  - `create-checkout-session`: crea el pago de Stripe. Aquí están los precios (`PRECIOS`).
  - `stripe-webhook`: recibe la confirmación de Stripe y apunta el pago. Se despliega con `--no-verify-jwt`.
- **Roles:** se distinguen por email. Admin y profesora se comparan con `ADMIN_EMAIL` / `PROF_EMAIL` en `index.html`, con `is_admin()` / `is_prof()` en `esquema.sql` y con el secret `ADMIN_EMAIL` de `admin-create-alumno`. **Los tres sitios deben coincidir.**

## Reglas que NO se pueden romper

1. **La seguridad real está en la base de datos**, no en `index.html`. Las políticas RLS y los triggers `enforce_booking_limits` / `enforce_cancel_limit` son los que impiden que una alumna vea datos de otras, reserve sin plaza o cancele fuera de plazo. Nunca desactives RLS ni relajes una política para "arreglar" un error: busca la causa real.
2. **Claves:** en `index.html` solo puede ir la clave **anon** de Supabase. La **service_role** y las claves de Stripe (`sk_…`, `whsec_…`) van únicamente en `supabase secrets set`. Nunca las escribas en un archivo que se publique ni en el repositorio.
3. **La tabla `pagos` solo la escribe el webhook** (con service role) o la admin (pagos manuales). Las alumnas no deben poder insertar pagos.
4. **Las reglas de negocio están duplicadas** en la base de datos (la que manda) y en `index.html` (para mostrar avisos). Si cambias una, cambia las dos:

| Regla | Base de datos (`esquema.sql`) | App (`index.html`) |
|---|---|---|
| Reservar hasta 30 min antes | `enforce_booking_limits`, `interval '30 minutes'` | `puedeReservar()` y textos con "30 min" |
| Cancelar hasta 2 h antes | `enforce_cancel_limit`, `interval '2 hours'` | `puedeCancelar()` y textos con "2h" / "2 horas" |
| Recuperaciones caducan a los 35 días | `enforce_cancel_limit`, `interval '35 days'` | (la app solo muestra la `fecha_limite` de cada crédito) |
| Zona horaria | `'Europe/Madrid'` en los triggers | `'Europe/Madrid'` en `puedeReservar()` / `puedeCancelar()` |
| Tipos de clase `Torno` / `Modelado` | `enforce_booking_limits` (lista de tipos válidos y cupo de Torno) | muchos sitios del HTML y JS |
| Plazas | columnas `capacidad_max` (Torno) y `capacidad_alumnos` (por turno) de cada clase | lectura vía RPC `ocupacion_clases` |

## Cómo funcionan las reservas

- Cada fila de `clases` es un turno (fecha + `hora` en formato `'17:00-19:00'`). Cada reserva elige su `tipo_clase` (Torno o Modelado).
- Al cancelar a tiempo una clase normal, el trigger crea un crédito en `recuperaciones` (caduca a los 35 días) y suma 1 a `alumnos.clases_recuperar`. Cancelar una clase de recuperación devuelve el crédito.
- Una alumna solo puede reservar por su cuenta si tiene un crédito pendiente (el trigger lo consume solo). La admin, la profesora y las usuarias `coworking` no tienen esa restricción. Las de coworking solo ocupan plazas de Torno libres.
- Las alumnas no pueden leer las reservas de otras (RLS). Para contar plazas libres se usa la función `ocupacion_clases(uuid[])`, que agrega sin exponer datos.

## Al hacer cambios

- **Cambios en la base de datos:** escríbelos como un archivo SQL nuevo (por ejemplo `supabase/cambios/2026-11-01_descripcion.sql`) que se pueda ejecutar en el SQL Editor y que sea seguro ejecutar dos veces (`CREATE OR REPLACE`, `IF NOT EXISTS`, `DROP POLICY IF EXISTS` antes de `CREATE POLICY`). Actualiza también `esquema.sql` para que una instalación nueva quede igual.
- **Cambios en una función de servidor:** hay que volver a desplegarla con `supabase functions deploy <nombre>` (y `--no-verify-jwt` solo en `stripe-webhook`).
- **Cambios en `index.html`:** hay que volver a pegarlo en la web. Si está en WordPress con caché, hay que vaciar la caché.
- No hay tests automáticos. Para comprobar un cambio: entra como alumna de prueba y como admin, y prueba reservar, cancelar y recuperar. Los pagos se prueban en el modo test de Stripe (tarjeta `4242 4242 4242 4242`).
- La base de datos tiene datos personales de alumnas. No los copies fuera de Supabase ni los incluyas en ejemplos, capturas o commits.

## Licencia

MIT + Commons Clause (ver [LICENSE](LICENSE)). Se puede usar y modificar para el propio taller de quien la instala. No ayudes a revenderla, a ofrecerla como servicio a otros negocios ni a cobrar a terceros por instalarla o mantenerla. No se pueden usar el nombre ni el logo de La Engalba.
