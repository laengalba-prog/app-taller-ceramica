# Área de alumnos para talleres de cerámica

Una app web sencilla para que un taller de cerámica gestione a su alumnado: calendario de clases, reservas, cancelaciones con clases de recuperación, pagos mensuales con Stripe y un panel de administración.

La creamos en **La Engalba** para nuestro propio taller y la compartimos por si le sirve a otros talleres.

## Licencia, en pocas palabras

La licencia completa está en [LICENSE](LICENSE) (MIT + Commons Clause). Esto es un resumen orientativo; si hay dudas, manda el texto de la licencia.

✅ **Puedes:**
- Usarla gratis para gestionar **tu propio taller**, estudio o escuela, aunque cobres por tus clases.
- Modificarla y adaptarla como quieras para tu taller.
- Alojarla donde quieras para tu taller.
- Compartir tus mejoras con otras personas en las mismas condiciones.

❌ **No puedes:**
- Vender la app, alquilarla ni ofrecerla como servicio (SaaS) a otros talleres o negocios.
- Cobrar a terceros por instalarla, adaptarla, alojarla, mantenerla o darle soporte.
- Usar el nombre «La Engalba», su logo o su identidad visual, ni presentar tu copia como si fuera nuestra.

Si quieres ayudar a otro taller a montarla **sin cobrar**, adelante.

> Técnicamente esto no es «código abierto» según la definición oficial (que no permite limitar el uso comercial), sino **código disponible**: puedes ver el código, usarlo y modificarlo con las condiciones de arriba.

## Qué incluye

- **Alumnas:** calendario mensual, reserva de turnos, cancelación hasta 2 h antes, créditos de recuperación (caducan a los 35 días), historial de clases, pago de la cuota mensual con tarjeta y cambio de contraseña.
- **Administración:** calendario con la lista de alumnas de cada turno, añadir o cancelar reservas, alta y baja de alumnas, crear clases y festivos, bloquear turnos y apuntar pagos manuales (efectivo, transferencia o Bizum).
- **Profesora:** ve las alumnas y reservas, y puede reservar o cancelar por ellas.
- Modalidades **Torno** y **Modelado**, y usuarias de **coworking** que solo ocupan plazas de torno libres.

## Qué necesitas

- Una cuenta gratuita de [Supabase](https://supabase.com) (base de datos y cuentas de acceso).
- Una cuenta de [Stripe](https://stripe.com), solo si quieres cobrar las cuotas con tarjeta.
- Un sitio donde publicar un archivo HTML: tu web de WordPress, Netlify, GitHub Pages, etc.
- [Node.js](https://nodejs.org) para instalar la herramienta de Supabase (`npm install -g supabase`).

## Instalación

### 1. Base de datos

1. Crea un proyecto nuevo en Supabase.
2. Abre [supabase/esquema.sql](supabase/esquema.sql) y cambia `admin@tu-taller.com` y `profe@tu-taller.com` por los emails reales de administración y de la profesora.
3. En Supabase, ve a **SQL Editor**, pega el archivo entero y pulsa **Run**.
4. En **Authentication → Users**, crea las cuentas de esos dos emails.

### 2. La app

1. Abre [index.html](index.html) y busca el bloque `CONFIGURACIÓN` (cerca de `const SUPABASE_URL`).
2. Rellena `SUPABASE_URL` y `SUPABASE_KEY` con los datos de **Project Settings → API**. Usa la clave *anon public*, nunca la *service_role*.
3. Pon los mismos `ADMIN_EMAIL` y `PROF_EMAIL` que en el paso anterior.
4. Cambia «Tu Taller» por el nombre de tu taller.
5. Pon los colores de tu taller: están todos juntos en el bloque `COLORES DEL TALLER` (`:root`), al principio del archivo. Al cambiarlos ahí cambian en toda la app, incluidos los arcos de la pantalla de entrada.
6. Publica el archivo. En WordPress puedes pegarlo en un bloque de código o con un plugin como WPCode, en una página sin cabecera ni pie.

### 3. Funciones del servidor

Desde esta carpeta:

```bash
supabase login
supabase link --project-ref TU_PROJECT_REF
supabase secrets set ADMIN_EMAIL=admin@tu-taller.com CONTRASENA_INICIAL=una-contraseña-inicial
supabase functions deploy admin-create-alumno
```

`admin-create-alumno` es la función que da de alta a las alumnas desde el panel. Cada alumna nueva recibe la `CONTRASENA_INICIAL`, que puede cambiar desde su perfil.

### 4. Pagos con Stripe (opcional)

1. Cambia los precios en [create-checkout-session/index.ts](supabase/functions/create-checkout-session/index.ts), en el bloque `PRECIOS`, en céntimos. También puedes poner un precio distinto a una alumna concreta en la columna `alumnos.precio_mensual`.
2. Configura las claves y despliega las funciones:
   ```bash
   supabase secrets set STRIPE_SECRET_KEY=sk_test_... NOMBRE_TALLER="Mi Taller" APP_URL=https://tu-web.com/area-de-alumnos
   supabase functions deploy create-checkout-session
   supabase functions deploy stripe-webhook --no-verify-jwt
   ```
3. En Stripe, ve a **Developers → Webhooks → Add endpoint**:
   - URL: `https://TU_PROJECT_REF.supabase.co/functions/v1/stripe-webhook`
   - Evento: `checkout.session.completed`
4. Copia el *signing secret* y guárdalo:
   ```bash
   supabase secrets set STRIPE_WEBHOOK_SECRET=whsec_...
   ```
5. Prueba primero en **modo test** con la tarjeta `4242 4242 4242 4242`. Cuando funcione, repite los pasos 2 a 4 con las claves de modo real (*live*).

### 5. Crear las clases

Desde el panel de administración puedes crear clases y festivos una a una. Para crear un curso entero de golpe, inserta filas en la tabla `clases` desde el SQL Editor. Cada fila lleva `fecha`, `dia_semana`, `hora` (formato `17:00-19:00`), `tipo_clase`, `capacidad_max` (plazas de torno) y `capacidad_alumnos` (alumnas por turno).

## Adaptar las reglas

| Regla | Dónde se cambia |
|---|---|
| Reservas hasta 30 min antes, cancelaciones hasta 2 h antes | `enforce_booking_limits` y `enforce_cancel_limit` en `esquema.sql`, y `puedeReservar` y `puedeCancelar` en `index.html` |
| Las recuperaciones caducan a los 35 días | `enforce_cancel_limit` en `esquema.sql` |
| Zona horaria `Europe/Madrid` | `esquema.sql` e `index.html` |
| Plazas por turno | Columnas `capacidad_max` y `capacidad_alumnos` de cada clase |
| Precios | `PRECIOS` en `create-checkout-session` |

## Seguridad

- **Nunca** pongas la clave `service_role` de Supabase ni las claves secretas de Stripe en `index.html` ni en ningún archivo que publiques. Solo van en `supabase secrets`.
- La seguridad real está en las reglas de la base de datos (RLS y triggers de `esquema.sql`). Si las modificas, comprueba que una alumna solo puede ver y tocar sus propios datos.

## Sin garantía

Se comparte tal cual, sin garantía ni soporte. La usamos a diario en nuestro taller, pero revisa que se ajusta a tu caso, sobre todo los pagos y la protección de datos de tu alumnado (RGPD).
