-- ═══════════════════════════════════════════════════════
-- ESQUEMA COMPLETO — Área de alumnos del taller
-- Ejecutar UNA vez en un proyecto de Supabase nuevo:
--   Supabase Dashboard → SQL Editor → pegar todo → Run
--
-- ANTES DE EJECUTAR: busca y cambia estos dos emails por los tuyos
--   admin@tu-taller.com  → cuenta de administración (gestiona todo)
--   profe@tu-taller.com  → cuenta de profesora (ve alumnas y reservas,
--                          puede reservar/cancelar por ellas)
-- Tienen que coincidir con ADMIN_EMAIL y PROF_EMAIL de index.html.
-- ═══════════════════════════════════════════════════════


-- ── 1. TABLAS ───────────────────────────────────────────

CREATE TABLE IF NOT EXISTS alumnos (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  nombre_alumno       text NOT NULL,
  email               text,
  telefono            text,
  user_id             uuid UNIQUE,               -- vincula con auth.users
  frecuencia          text DEFAULT '1vez',       -- '1vez' | '2veces'
  clases_recuperar    integer DEFAULT 0,
  tipo_usuario        text DEFAULT 'alumno',     -- 'alumno' | 'coworking'
  tipo_clase_default  text DEFAULT 'Torno',      -- 'Torno' | 'Modelado'
  dia_habitual        text,                      -- ej: 'Lunes' o 'Lunes,Jueves'
  hora_habitual       text,                      -- ej: '19:00-21:00'
  activo              boolean NOT NULL DEFAULT true,
  pagado              boolean DEFAULT false,
  ultimo_pago_mes     text,                      -- 'YYYY-MM'
  ultimo_pago_fecha   timestamptz,
  ultimo_pago_importe numeric,
  precio_mensual      numeric                    -- NULL = precio por defecto según frecuencia
);
COMMENT ON COLUMN alumnos.precio_mensual IS 'Cuota mensual específica en euros. NULL = usar precio por defecto según frecuencia.';

CREATE TABLE IF NOT EXISTS clases (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  fecha             date NOT NULL,
  dia_semana        text NOT NULL,
  hora              text NOT NULL,               -- ej: '17:00-19:00'
  tipo_clase        text NOT NULL,               -- 'Torno' | 'Modelado' | 'Festivo'
  capacidad_max     integer NOT NULL DEFAULT 8,  -- máximo de plazas de Torno (incluye coworking)
  es_festivo        boolean NOT NULL DEFAULT false,
  capacidad_alumnos integer DEFAULT 9,           -- máximo de alumnas (sin coworking) por turno
  bloqueada         boolean NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS recuperaciones (
  id                    uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alumno_id             uuid NOT NULL REFERENCES alumnos(id) ON DELETE CASCADE,
  clase_original_id     uuid NOT NULL REFERENCES clases(id) ON DELETE CASCADE,
  fecha_limite          date NOT NULL,
  estado                text NOT NULL DEFAULT 'pendiente', -- 'pendiente' | 'usada' | 'caducada'
  clase_recuperacion_id uuid REFERENCES clases(id),
  created_at            timestamptz NOT NULL DEFAULT now(),
  devuelto              boolean NOT NULL DEFAULT false
);

CREATE TABLE IF NOT EXISTS reservas (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alumno_id       uuid REFERENCES alumnos(id),
  clase_id        uuid REFERENCES clases(id),
  estado          text NOT NULL DEFAULT 'reservado', -- 'reservado' | 'cancelado'
  created_at      timestamptz DEFAULT now(),
  tipo_clase      text,                               -- 'Torno' | 'Modelado'
  es_recuperacion boolean NOT NULL DEFAULT false,
  recuperacion_id uuid REFERENCES recuperaciones(id)
);

CREATE TABLE IF NOT EXISTS pagos (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  alumno_id           uuid NOT NULL REFERENCES alumnos(id),
  fecha_pago          timestamptz NOT NULL DEFAULT now(),
  importe             numeric NOT NULL,
  mes_correspondiente text NOT NULL,
  stripe_session_id   text UNIQUE,                    -- NULL en pagos manuales
  metodo              text NOT NULL DEFAULT 'stripe'  -- 'stripe' | 'efectivo' | 'transferencia' | 'bizum'
);
CREATE INDEX IF NOT EXISTS idx_pagos_alumno_id ON pagos(alumno_id);

CREATE TABLE IF NOT EXISTS config (
  key   text PRIMARY KEY,
  value text NOT NULL DEFAULT ''
);


-- ── 2. ROLES: admin y profesora ─────────────────────────

CREATE OR REPLACE FUNCTION is_admin()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = auth.uid()
    AND email = 'admin@tu-taller.com'
  );
$$;

CREATE OR REPLACE FUNCTION is_prof()
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM auth.users
    WHERE id = auth.uid()
    AND email = 'profe@tu-taller.com'
  );
$$;


-- ── 3. SEGURIDAD (RLS) ──────────────────────────────────

ALTER TABLE alumnos        ENABLE ROW LEVEL SECURITY;
ALTER TABLE clases         ENABLE ROW LEVEL SECURITY;
ALTER TABLE reservas       ENABLE ROW LEVEL SECURITY;
ALTER TABLE recuperaciones ENABLE ROW LEVEL SECURITY;
ALTER TABLE pagos          ENABLE ROW LEVEL SECURITY;
ALTER TABLE config         ENABLE ROW LEVEL SECURITY;

-- alumnos: cada alumna ve y edita su ficha; admin todo; profesora puede leer
CREATE POLICY "alumnos_select" ON alumnos FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR is_admin() OR is_prof());
CREATE POLICY "alumnos_insert" ON alumnos FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid() OR is_admin());
CREATE POLICY "alumnos_update" ON alumnos FOR UPDATE TO authenticated
  USING (user_id = auth.uid() OR is_admin());
CREATE POLICY "alumnos_delete" ON alumnos FOR DELETE TO authenticated
  USING (is_admin());

-- clases: todas las personas con sesión las ven; solo admin las gestiona
CREATE POLICY "clases_select" ON clases FOR SELECT TO authenticated USING (true);
CREATE POLICY "clases_insert" ON clases FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY "clases_update" ON clases FOR UPDATE TO authenticated USING (is_admin());
CREATE POLICY "clases_delete" ON clases FOR DELETE TO authenticated USING (is_admin());

-- reservas: cada alumna (activa) las suyas; admin y profesora todas
CREATE POLICY "reservas_select" ON reservas FOR SELECT TO authenticated
  USING (
    alumno_id IN (SELECT id FROM alumnos WHERE user_id = auth.uid())
    OR is_admin() OR is_prof()
  );
CREATE POLICY "reservas_insert" ON reservas FOR INSERT TO authenticated
  WITH CHECK (
    is_admin() OR is_prof()
    OR alumno_id IN (SELECT a.id FROM alumnos a WHERE a.user_id = auth.uid() AND a.activo = true)
  );
CREATE POLICY "reservas_update" ON reservas FOR UPDATE TO authenticated
  USING (
    is_admin() OR is_prof()
    OR alumno_id IN (SELECT id FROM alumnos WHERE user_id = auth.uid() AND activo = true)
  );
CREATE POLICY "reservas_delete" ON reservas FOR DELETE TO authenticated
  USING (is_admin());

-- recuperaciones: cada alumna ve las suyas; solo admin las toca a mano
-- (el resto lo hacen los triggers, que corren como SECURITY DEFINER)
CREATE POLICY "recuperaciones_select" ON recuperaciones FOR SELECT TO authenticated
  USING (
    alumno_id IN (SELECT id FROM alumnos WHERE user_id = auth.uid())
    OR is_admin()
  );
CREATE POLICY "recuperaciones_admin_write" ON recuperaciones FOR ALL TO authenticated
  USING (is_admin()) WITH CHECK (is_admin());

-- pagos: cada alumna ve los suyos; admin todos y puede apuntar pagos manuales.
-- Los pagos de Stripe los inserta el webhook con la service role key.
CREATE POLICY "pagos_select" ON pagos FOR SELECT TO authenticated
  USING (
    alumno_id IN (SELECT id FROM alumnos WHERE user_id = auth.uid())
    OR is_admin()
  );
CREATE POLICY "pagos_insert_admin" ON pagos FOR INSERT TO authenticated
  WITH CHECK (is_admin());

-- config
CREATE POLICY "config_select" ON config FOR SELECT TO authenticated USING (true);
CREATE POLICY "config_insert" ON config FOR INSERT TO authenticated WITH CHECK (is_admin());
CREATE POLICY "config_update" ON config FOR UPDATE TO authenticated USING (is_admin());
CREATE POLICY "config_delete" ON config FOR DELETE TO authenticated USING (is_admin());


-- ── 4. REGLAS DE RESERVA Y CANCELACIÓN (triggers) ───────
-- Reservar:  cierra 30 min antes; máx. capacidad_alumnos alumnas y
--            capacidad_max plazas de Torno por turno; una alumna solo puede
--            reservar por su cuenta si tiene un crédito de recuperación.
-- Cancelar:  hasta 2 h antes; genera un crédito de recuperación que caduca
--            a los 35 días. Cancelar una recuperación devuelve el crédito.
-- Para cambiar estos márgenes, edita los intervalos de abajo (y los mismos
-- márgenes en index.html, funciones puedeReservar/puedeCancelar).
-- La zona horaria es 'Europe/Madrid'; cámbiala si tu taller está en otra.

CREATE OR REPLACE FUNCTION enforce_booking_limits()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_clase        record;
  v_alumno       record;
  v_start_hora   text;
  v_clase_start  timestamptz;
  v_count_alum   integer;
  v_count_torno  integer;
  v_rec          record;
begin
  select * into v_clase from clases where id = new.clase_id;
  if not found then
    raise exception 'Clase no encontrada';
  end if;

  select * into v_alumno from alumnos where id = new.alumno_id;
  if not found then
    raise exception 'Alumna no encontrada';
  end if;

  -- Corte de 30 minutos antes de la clase (hora de Madrid)
  v_start_hora := split_part(v_clase.hora, '-', 1);
  v_clase_start := (v_clase.fecha::text || ' ' || v_start_hora)::timestamp at time zone 'Europe/Madrid';

  if not is_admin() and v_clase_start - now() < interval '30 minutes' then
    raise exception 'La reserva cierra 30 minutos antes de la clase';
  end if;

  -- Si no se especifica (p.ej. reservas creadas por la admin desde el panel),
  -- se usa la modalidad por defecto de la alumna.
  if new.tipo_clase is null then
    new.tipo_clase := coalesce(v_alumno.tipo_clase_default, 'Torno');
  end if;
  if new.tipo_clase not in ('Torno', 'Modelado') then
    raise exception 'Tipo de clase no válido: debe ser Torno o Modelado';
  end if;

  -- Cupo: máximo 9 alumnas (no coworking) por turno, y máximo 8 en Torno
  -- (contando también a coworking, que solo puede ocupar plazas de Torno sobrantes).
  select count(*) into v_count_alum
  from reservas r join alumnos a on a.id = r.alumno_id
  where r.clase_id = new.clase_id and r.estado = 'reservado'
    and a.tipo_usuario is distinct from 'coworking';

  select count(*) into v_count_torno
  from reservas r
  where r.clase_id = new.clase_id and r.estado = 'reservado' and r.tipo_clase = 'Torno';

  if v_alumno.tipo_usuario is distinct from 'coworking' and v_count_alum >= v_clase.capacidad_alumnos then
    raise exception 'La clase está completa';
  end if;

  if new.tipo_clase = 'Torno' and v_count_torno >= v_clase.capacidad_max then
    raise exception 'No quedan plazas de Torno en este turno';
  end if;

  -- Reserva de autoservicio (alumna con sesión propia, no admin, no coworking):
  -- exige un crédito de recuperación pendiente y lo aplica automáticamente si
  -- no se ha indicado uno explícito.
  if auth.uid() is not null and not is_admin() and v_alumno.tipo_usuario is distinct from 'coworking' then
    if new.recuperacion_id is null then
      select id into new.recuperacion_id
      from recuperaciones
      where alumno_id = new.alumno_id and estado = 'pendiente' and fecha_limite >= current_date
      order by fecha_limite asc
      limit 1;

      if new.recuperacion_id is null then
        raise exception 'No tienes clases pendientes de recuperar';
      end if;
    end if;
  end if;

  -- Si la reserva usa un crédito de recuperación, validarlo y consumirlo
  if new.recuperacion_id is not null then
    select * into v_rec from recuperaciones where id = new.recuperacion_id;
    if not found or v_rec.alumno_id <> new.alumno_id then
      raise exception 'Crédito de recuperación no válido';
    end if;
    if v_rec.estado <> 'pendiente' then
      raise exception 'Ese crédito de recuperación ya no está disponible';
    end if;
    if v_rec.fecha_limite < current_date then
      raise exception 'Ese crédito de recuperación ha caducado';
    end if;

    update recuperaciones
      set estado = 'usada', clase_recuperacion_id = new.clase_id
      where id = new.recuperacion_id;

    new.es_recuperacion := true;

    update alumnos set clases_recuperar = greatest(0, coalesce(clases_recuperar,0) - 1)
      where id = new.alumno_id;
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION enforce_cancel_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
declare
  v_clase       record;
  v_start_hora  text;
  v_clase_start timestamptz;
  v_count_torno integer;
  v_rec         record;
begin
  if old.estado = 'cancelado' and new.estado = 'reservado' and not is_admin() then
    raise exception 'No se puede reactivar una reserva cancelada; vuelve a reservar la clase';
  end if;

  if new.estado = 'reservado' and new.tipo_clase is distinct from old.tipo_clase and new.tipo_clase = 'Torno' then
    select * into v_clase from clases where id = new.clase_id;
    select count(*) into v_count_torno
    from reservas
    where clase_id = new.clase_id and estado = 'reservado' and tipo_clase = 'Torno' and id <> new.id;
    if v_count_torno >= v_clase.capacidad_max then
      raise exception 'No quedan plazas de Torno en este turno';
    end if;
  end if;

  if old.estado = 'reservado' and new.estado = 'cancelado' then
    select * into v_clase from clases where id = new.clase_id;

    v_start_hora := split_part(v_clase.hora, '-', 1);
    v_clase_start := (v_clase.fecha::text || ' ' || v_start_hora)::timestamp at time zone 'Europe/Madrid';

    if not is_admin() and v_clase_start - now() < interval '2 hours' then
      raise exception 'No puedes cancelar con menos de 2 horas de antelación';
    end if;

    if not old.es_recuperacion then
      insert into recuperaciones (alumno_id, clase_original_id, fecha_limite)
      values (new.alumno_id, new.clase_id, v_clase.fecha + interval '35 days');

      update alumnos set clases_recuperar = coalesce(clases_recuperar,0) + 1
        where id = new.alumno_id;
    elsif old.recuperacion_id is not null then
      -- Cancelar una recuperación no genera un crédito nuevo, pero devuelve el
      -- que se usó (todas las veces que haga falta, mientras no haya caducado).
      select * into v_rec from recuperaciones where id = old.recuperacion_id;
      if found and v_rec.fecha_limite >= current_date then
        update recuperaciones
          set estado = 'pendiente', clase_recuperacion_id = null, devuelto = true
          where id = old.recuperacion_id;

        update alumnos set clases_recuperar = coalesce(clases_recuperar,0) + 1
          where id = new.alumno_id;
      end if;
    end if;
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION ocupacion_clases(p_clase_ids uuid[])
 RETURNS TABLE(clase_id uuid, total integer, alumnos integer, torno integer)
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT r.clase_id,
         COUNT(*)::int AS total,
         COUNT(*) FILTER (WHERE a.tipo_usuario IS DISTINCT FROM 'coworking')::int AS alumnos,
         COUNT(*) FILTER (WHERE r.tipo_clase = 'Torno')::int AS torno
  FROM reservas r
  LEFT JOIN alumnos a ON a.id = r.alumno_id
  WHERE r.clase_id = ANY(p_clase_ids) AND r.estado = 'reservado'
  GROUP BY r.clase_id;
$function$;

CREATE OR REPLACE FUNCTION creditos_pendientes(p_alumno_id uuid)
 RETURNS TABLE(id uuid, fecha_limite date, clase_original_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
AS $function$
  SELECT r.id, r.fecha_limite, r.clase_original_id
  FROM recuperaciones r
  WHERE r.alumno_id = p_alumno_id
    AND r.estado = 'pendiente'
    AND r.fecha_limite >= CURRENT_DATE
    AND (
      p_alumno_id IN (SELECT id FROM alumnos WHERE user_id = auth.uid())
      OR is_admin()
    )
  ORDER BY r.fecha_limite ASC;
$function$;

DROP TRIGGER IF EXISTS trg_booking_limits ON reservas;
CREATE TRIGGER trg_booking_limits
  BEFORE INSERT ON reservas
  FOR EACH ROW
  EXECUTE FUNCTION enforce_booking_limits();

DROP TRIGGER IF EXISTS trg_cancel_limit ON reservas;
CREATE TRIGGER trg_cancel_limit
  BEFORE UPDATE ON reservas
  FOR EACH ROW
  EXECUTE FUNCTION enforce_cancel_limit();

GRANT EXECUTE ON FUNCTION ocupacion_clases(uuid[]) TO authenticated;
GRANT EXECUTE ON FUNCTION creditos_pendientes(uuid) TO authenticated;
