-- DBEAVER + ORACLE XE 21c.
-- Para SQL: ejecutar una sentencia. Para PL/SQL: seleccionar el bloque completo
-- DECLARE/BEGIN o CREATE...END; sin la linea / y usar Ejecutar sentencia SQL.
-- Conservar la misma conexion para SAVEPOINT/ROLLBACK. Activar salida DBMS Output.
-- ============================================================================
-- UNIVERSIDAD DEL QUINDIO - BASES DE DATOS II
-- PROYECTO INTEGRADOR TURISMOUQ - ENTREGA FINAL
-- 03_consultas_analiticas_TurismoUQ.sql
-- Integrantes: Maria Jose Vasquez, Luisa Osorio, Amed Santiago Vargas Zambrano
-- Motor: Oracle XE 21c | Esquema: TURISMOUQ
-- Requisito previo: ejecutar 01_modelo_tablas_TurismoUQ.sql y 02_carga_datos_TurismoUQ.sql.
-- Este archivo contiene SIETE CONSULTAS DE SOLO LECTURA (no altera datos).
-- En DBeaver: seleccionar cada consulta y ejecutar Ctrl+Enter;
-- o ejecutar el script completo con Alt+X (la consulta 5 solicita dos fechas como parametros String).
-- Capturas para Evidencias_TurismoUQ_APA.docx: figuras 1.4 a 1.10.
-- ============================================================================

-- ============================================================================
-- 1. PIVOT - OCUPACION MENSUAL POR MUNICIPIO (2025 Y 2026)
-- Pregunta: ¿Que porcentaje de habitaciones disponibles se ocupo cada mes?
-- Se cuentan NOCHES DE HABITACION (no solamente reservas que iniciaron ese mes).
-- Inventario historico: todas las habitaciones; ACTIVA solo controla nuevas reservas.
-- Solo reservas CONFIRMADAS o COMPLETADAS. Las canceladas y pendientes no ocupan.
-- 100% = todas las habitaciones del municipio ocupadas todas las noches del mes.
-- Evidencia Word: Figura 1.4.
-- ============================================================================
WITH
meses AS (
    SELECT ADD_MONTHS(DATE '2025-01-01', LEVEL - 1) AS inicio_mes
    FROM dual CONNECT BY LEVEL <= 24
),
fechas AS (
    SELECT DATE '2025-01-01' + LEVEL - 1 AS noche
    FROM dual CONNECT BY LEVEL <= (DATE '2027-01-01' - DATE '2025-01-01')
),
habitaciones_municipio AS (
    SELECT a.id_municipio, COUNT(*) AS cantidad_habitaciones
    FROM alojamiento a
    JOIN habitacion h ON h.id_alojamiento = a.id_alojamiento
    GROUP BY a.id_municipio
),
noches_ocupadas AS (
    SELECT a.id_municipio,
           TRUNC(f.noche, 'MM') AS inicio_mes,
           COUNT(*) AS noches_habitacion
    FROM fechas f
    JOIN reserva_habitacion rh
      ON f.noche >= TRUNC(rh.fecha_checkin)
     AND f.noche < TRUNC(rh.fecha_checkout)
    JOIN reserva r ON r.id_reserva = rh.id_reserva
    JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
    JOIN alojamiento a ON a.id_alojamiento = h.id_alojamiento
    WHERE r.estado IN ('CONFIRMADA', 'COMPLETADA')
    GROUP BY a.id_municipio, TRUNC(f.noche, 'MM')
),
por_mes AS (
    SELECT mu.nombre AS municipio,
           EXTRACT(YEAR FROM me.inicio_mes) AS anio,
           EXTRACT(MONTH FROM me.inicio_mes) AS mes,
           ROUND(100 * NVL(no.noches_habitacion, 0) /
                 NULLIF(hm.cantidad_habitaciones *
                        (ADD_MONTHS(me.inicio_mes, 1) - me.inicio_mes), 0), 2)
                 AS porcentaje_ocupacion
    FROM municipio mu
    JOIN habitaciones_municipio hm ON hm.id_municipio = mu.id_municipio
    CROSS JOIN meses me
    LEFT JOIN noches_ocupadas no
      ON no.id_municipio = mu.id_municipio
     AND no.inicio_mes = me.inicio_mes
)
SELECT *
FROM por_mes
PIVOT (
    MAX(porcentaje_ocupacion) FOR mes IN (
        1 AS ENE, 2 AS FEB, 3 AS MAR, 4 AS ABR,
        5 AS MAY, 6 AS JUN, 7 AS JUL, 8 AS AGO,
        9 AS SEP, 10 AS OCT, 11 AS NOV, 12 AS DIC
    )
)
ORDER BY municipio, anio;

-- ============================================================================
-- 2. ROLLUP + GROUPING - INGRESOS POR MUNICIPIO, TIPO Y TEMPORADA
-- Pregunta: ¿Cuanto dinero se recibio por municipio, tipo y temporada?
-- Ingreso = recaudo neto (EXITOSO/REEMBOLSADO menos devoluciones). La temporada se identifica por el CHECK-IN.
-- Si una reserva involucra varios alojamientos, el pago se distribuye a partes
-- iguales entre esos alojamientos para NO duplicar el ingreso de una reserva.
-- Los subtotales y el total general se identifican mediante GROUPING().
-- Evidencia Word: Figura 1.5.
-- ============================================================================
WITH pagos_reserva AS (
    SELECT id_reserva, SUM(monto-monto_reembolsado) AS total_exitoso
    FROM pago
    WHERE estado IN ('EXITOSO','REEMBOLSADO')
    GROUP BY id_reserva
),
alojamientos_reserva AS (
    SELECT DISTINCT rh.id_reserva, h.id_alojamiento
    FROM reserva_habitacion rh
    JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
),
distribucion AS (
    SELECT ar.id_reserva, ar.id_alojamiento,
           COUNT(*) OVER (PARTITION BY ar.id_reserva) AS alojamientos_en_reserva
    FROM alojamientos_reserva ar
)
SELECT
    CASE WHEN GROUPING(m.nombre) = 1 THEN 'TOTAL GENERAL'
         ELSE m.nombre END AS municipio,
    CASE WHEN GROUPING(ta.nombre) = 1 THEN 'SUBTOTAL'
         ELSE ta.nombre END AS tipo_alojamiento,
    CASE WHEN GROUPING(t.tipo) = 1 THEN 'SUBTOTAL'
         ELSE t.tipo END AS temporada,
    ROUND(SUM(pr.total_exitoso / d.alojamientos_en_reserva), 2) AS ingresos_cop,
    GROUPING(m.nombre) AS es_total_municipio,
    GROUPING(ta.nombre) AS es_total_tipo,
    GROUPING(t.tipo) AS es_total_temporada
FROM distribucion d
JOIN pagos_reserva pr ON pr.id_reserva = d.id_reserva
JOIN reserva r ON r.id_reserva = d.id_reserva
JOIN alojamiento a ON a.id_alojamiento = d.id_alojamiento
JOIN municipio m ON m.id_municipio = a.id_municipio
JOIN tipo_alojamiento ta ON ta.id_tipo = a.id_tipo
JOIN temporada t ON TRUNC(r.fecha_checkin) BETWEEN t.fecha_inicio AND t.fecha_fin
GROUP BY ROLLUP(m.nombre, ta.nombre, t.tipo)
ORDER BY GROUPING(m.nombre), m.nombre,
         GROUPING(ta.nombre), ta.nombre,
         GROUPING(t.tipo), t.tipo;

-- ============================================================================
-- 3. RANK + PARTITION BY - TRES ALOJAMIENTOS DE MAYOR INGRESO POR MUNICIPIO
-- Pregunta: ¿Que alojamientos lideran los ingresos dentro de cada municipio?
-- Se evita duplicar pagos al unir una reserva con varias habitaciones.
-- RANK asigna la misma posicion cuando existen empates.
-- Nota: los empates en el tercer puesto pueden producir mas de 3 filas.
-- Evidencia Word: Figura 1.6.
-- ============================================================================
WITH pagos_reserva AS (
    SELECT id_reserva, SUM(monto-monto_reembolsado) AS total_exitoso
    FROM pago
    WHERE estado IN ('EXITOSO','REEMBOLSADO')
    GROUP BY id_reserva
),
alojamientos_reserva AS (
    SELECT DISTINCT rh.id_reserva, h.id_alojamiento
    FROM reserva_habitacion rh
    JOIN habitacion h ON h.id_habitacion = rh.id_habitacion
),
distribucion AS (
    SELECT ar.id_reserva, ar.id_alojamiento,
           COUNT(*) OVER (PARTITION BY ar.id_reserva) AS cantidad_alojamientos
    FROM alojamientos_reserva ar
),
ingresos AS (
    SELECT m.nombre AS municipio,
           a.id_alojamiento,
           a.nombre AS alojamiento,
           ROUND(SUM(pr.total_exitoso / d.cantidad_alojamientos), 2) AS ingresos_cop
    FROM distribucion d
    JOIN pagos_reserva pr ON pr.id_reserva = d.id_reserva
    JOIN alojamiento a ON a.id_alojamiento = d.id_alojamiento
    JOIN municipio m ON m.id_municipio = a.id_municipio
    GROUP BY m.nombre, a.id_alojamiento, a.nombre
),
clasificacion AS (
    SELECT municipio, alojamiento, ingresos_cop,
           RANK() OVER (PARTITION BY municipio ORDER BY ingresos_cop DESC) AS posicion
    FROM ingresos
)
SELECT municipio, posicion, alojamiento, ingresos_cop
FROM clasificacion
WHERE posicion <= 3
ORDER BY municipio, posicion, alojamiento;

-- ============================================================================
-- 4. LAG - VARIACION DE INGRESOS DE UN MES AL SIGUIENTE
-- Pregunta: ¿Como cambiaron los pagos exitosos frente al mes anterior?
-- Se usa fecha del cobro original, neta de su devolucion acumulada.
-- No es un flujo de caja por fecha de desembolso de devoluciones.
-- Se generan todos los meses 2024-2026 para que LAG compare meses contiguos.
-- Evidencia Word: Figura 1.7.
-- ============================================================================
WITH meses AS (
    SELECT ADD_MONTHS(DATE '2024-01-01', LEVEL - 1) AS inicio_mes
    FROM dual CONNECT BY LEVEL <= 36
),
ingresos_mes AS (
    SELECT TRUNC(fecha_pago, 'MM') AS inicio_mes,
           SUM(monto-monto_reembolsado) AS ingresos_cop
    FROM pago
    WHERE estado IN ('EXITOSO','REEMBOLSADO')
      AND fecha_pago >= DATE '2024-01-01'
      AND fecha_pago < DATE '2027-01-01'
    GROUP BY TRUNC(fecha_pago, 'MM')
),
serie AS (
    SELECT me.inicio_mes,
           NVL(im.ingresos_cop, 0) AS ingresos_cop,
           LAG(NVL(im.ingresos_cop, 0)) OVER (ORDER BY me.inicio_mes)
               AS ingresos_mes_anterior
    FROM meses me
    LEFT JOIN ingresos_mes im ON im.inicio_mes = me.inicio_mes
)
SELECT TO_CHAR(inicio_mes, 'YYYY-MM') AS mes,
       ingresos_cop,
       ingresos_mes_anterior,
       ingresos_cop - ingresos_mes_anterior AS variacion_cop,
       ROUND(100 * (ingresos_cop - ingresos_mes_anterior) /
             NULLIF(ingresos_mes_anterior, 0), 2) AS variacion_porcentaje
FROM serie
ORDER BY inicio_mes;

-- ============================================================================
-- 5. CONSULTA PARAMETRIZADA - RESERVAS POR RANGO DE FECHAS
-- Pregunta: ¿Cuantas reservas se iniciaron en un periodo, por estado?
-- Variables de enlace reales: :fecha_inicio y :fecha_fin.
-- En DBeaver habilitar parametros SQL y elegir String para ambos valores.
-- Introducir 2026-01-01 y 2026-06-30 sin comillas adicionales.
-- La fecha final se incluye completa; el filtro se aplica al check-in.
-- Evidencia Word: Figura 1.8 (capturar SQL, valores y resultado; no claves).
-- ============================================================================
WITH parametros AS (
    SELECT TO_DATE(:fecha_inicio, 'FXYYYY-MM-DD') AS fecha_inicio,
           TO_DATE(:fecha_fin, 'FXYYYY-MM-DD') AS fecha_fin
    FROM dual
)
SELECT r.estado,
       COUNT(*) AS cantidad_reservas,
       COUNT(DISTINCT r.id_cliente) AS clientes_diferentes
FROM reserva r
CROSS JOIN parametros p
WHERE r.fecha_checkin >= p.fecha_inicio
  AND r.fecha_checkin < p.fecha_fin + 1
GROUP BY r.estado
ORDER BY cantidad_reservas DESC, r.estado;

-- ============================================================================
-- 6. UNPIVOT - ESTADOS DE RESERVAS POR MUNICIPIO
-- Pregunta: ¿Cuantas reservas hay en cada estado en cada municipio?
-- Primero se agrupan columnas por estado; UNPIVOT las convierte en filas.
-- DISTINCT evita contar dos veces una reserva con varias habitaciones
-- del mismo alojamiento o municipio.
-- Evidencia Word: Figura 1.9.
-- ============================================================================
WITH reservas_municipio AS (
    SELECT DISTINCT m.nombre AS municipio, r.id_reserva, r.estado
    FROM municipio m
    JOIN alojamiento a ON a.id_municipio = m.id_municipio
    JOIN habitacion h ON h.id_alojamiento = a.id_alojamiento
    JOIN reserva_habitacion rh ON rh.id_habitacion = h.id_habitacion
    JOIN reserva r ON r.id_reserva = rh.id_reserva
),
resumen AS (
    SELECT municipio,
           SUM(CASE WHEN estado = 'PENDIENTE' THEN 1 ELSE 0 END) AS pendientes,
           SUM(CASE WHEN estado = 'CONFIRMADA' THEN 1 ELSE 0 END) AS confirmadas,
           SUM(CASE WHEN estado = 'CANCELADA' THEN 1 ELSE 0 END) AS canceladas,
           SUM(CASE WHEN estado = 'COMPLETADA' THEN 1 ELSE 0 END) AS completadas
    FROM reservas_municipio
    GROUP BY municipio
)
SELECT municipio, estado_reserva, cantidad_reservas
FROM resumen
UNPIVOT (
    cantidad_reservas FOR estado_reserva IN (
        pendientes AS 'PENDIENTE',
        confirmadas AS 'CONFIRMADA',
        canceladas AS 'CANCELADA',
        completadas AS 'COMPLETADA'
    )
)
ORDER BY municipio, estado_reserva;

-- ============================================================================
-- 7. CONSULTA LIBRE - CALIDAD DE SERVICIO SEGUN RESENAS
-- Pregunta: ¿Que alojamientos tienen mejor calificacion de sus huespedes?
-- Solo reservas COMPLETADAS y alojamientos con al menos 5 resenas.
-- Evidencia Word: Figura 1.10.
-- ============================================================================
SELECT m.nombre AS municipio,
       a.nombre AS alojamiento,
       COUNT(*) AS numero_resenas,
       ROUND(AVG(re.calificacion), 2) AS promedio_calificacion,
       SUM(CASE WHEN re.calificacion >= 4 THEN 1 ELSE 0 END) AS resenas_positivas
FROM resena re
JOIN reserva r ON r.id_reserva = re.id_reserva
JOIN alojamiento a ON a.id_alojamiento = re.id_alojamiento
JOIN municipio m ON m.id_municipio = a.id_municipio
WHERE r.estado = 'COMPLETADA'
GROUP BY m.nombre, a.nombre
HAVING COUNT(*) >= 5
ORDER BY promedio_calificacion DESC, numero_resenas DESC, municipio, alojamiento;

-- ============================================================================
-- FIN DEL ARCHIVO 03. No ejecutar nuevamente las cargas 01 y 02.
-- Para el documento de evidencias, guardar el resultado REAL de cada consulta.
-- ============================================================================
