-- DBEAVER + ORACLE XE 21c.
-- Para SQL: ejecutar una sentencia. Para PL/SQL: seleccionar el bloque completo
-- DECLARE/BEGIN o CREATE...END; sin la linea / y usar Ejecutar sentencia SQL.
-- Conservar la misma conexion para SAVEPOINT/ROLLBACK. Activar salida DBMS Output.
-- TURISMOUQ - ENTREGA 2 - PUNTO 2.8
-- Ejecutar conectado como TURISMOUQ en XEPDB1 (puerto 1522)
-- Si ORA-01031, ejecutar con SYSTEM en XEPDB1:
-- GRANT CREATE MATERIALIZED VIEW TO TURISMOUQ;
-- (volver a conectar como TURISMOUQ para continuar)

-- FIGURA 2.12 - Creacion de la vista materializada de ocupacion mensual
-- Ocupacion = noches efectivamente ocupadas / noches disponibles.
-- Una estancia que atraviesa meses se reparte correctamente entre ellos.
-- Solo se consideran reservas CONFIRMADA y COMPLETADA.
-- Mismo criterio que consulta 1: inventario total registrado, incluido el que
-- ahora esta inactivo, para no alterar capacidad historica al desactivarlo.
-- No modela cierres temporales; eso requeriria un calendario de disponibilidad.
-- Todos los municipios con habitaciones y todos los meses tarifarios, con ceros.
-- Politica: refresco manual despues de confirmar un lote de cambios y antes
-- de emitir el informe mensual. El encargado ejecuta DBMS_MVIEW.REFRESH(...,'C').

CREATE MATERIALIZED VIEW MV_OCUPACION_MENSUAL
BUILD IMMEDIATE
REFRESH COMPLETE ON DEMAND
AS
WITH limites AS (
    SELECT TRUNC(MIN(FECHA_INICIO), 'MM') AS MES_INICIAL,
           TRUNC(MAX(FECHA_FIN), 'MM') AS MES_FINAL
    FROM TEMPORADA
),
meses AS (
    SELECT ADD_MONTHS(l.MES_INICIAL, LEVEL - 1) AS MES
    FROM limites l
    CONNECT BY LEVEL <= MONTHS_BETWEEN(l.MES_FINAL, l.MES_INICIAL) + 1
),
capacidad AS (
    SELECT a.ID_MUNICIPIO, COUNT(*) AS TOTAL_HABITACIONES
    FROM HABITACION h
    JOIN ALOJAMIENTO a ON a.ID_ALOJAMIENTO = h.ID_ALOJAMIENTO
    GROUP BY a.ID_MUNICIPIO
),
ocupadas AS (
    SELECT a.ID_MUNICIPIO, m.MES,
           SUM(LEAST(rh.FECHA_CHECKOUT, ADD_MONTHS(m.MES, 1))
                 - GREATEST(rh.FECHA_CHECKIN, m.MES)) AS NOCHES_OCUPADAS,
           COUNT(DISTINCT rh.ID_RESERVA) AS RESERVAS
    FROM RESERVA_HABITACION rh
    JOIN RESERVA r ON r.ID_RESERVA = rh.ID_RESERVA
    JOIN HABITACION h ON h.ID_HABITACION = rh.ID_HABITACION
    JOIN ALOJAMIENTO a ON a.ID_ALOJAMIENTO = h.ID_ALOJAMIENTO
    JOIN meses m ON rh.FECHA_CHECKIN < ADD_MONTHS(m.MES, 1)
                AND rh.FECHA_CHECKOUT > m.MES
    WHERE r.ESTADO IN ('CONFIRMADA', 'COMPLETADA')
    GROUP BY a.ID_MUNICIPIO, m.MES
)
SELECT c.ID_MUNICIPIO,
       m.MES,
       NVL(o.RESERVAS,0) AS RESERVAS,
       NVL(o.NOCHES_OCUPADAS,0) AS NOCHES_OCUPADAS,
       c.TOTAL_HABITACIONES*(ADD_MONTHS(m.MES,1)-m.MES) AS NOCHES_DISPONIBLES,
       ROUND(100*NVL(o.NOCHES_OCUPADAS,0)/
         NULLIF(c.TOTAL_HABITACIONES*(ADD_MONTHS(m.MES,1)-m.MES),0),2) AS PORCENTAJE_OCUPACION
FROM capacidad c CROSS JOIN meses m
LEFT JOIN ocupadas o ON o.ID_MUNICIPIO=c.ID_MUNICIPIO AND o.MES=m.MES;

-- FIGURA 2.12 - Verificacion de existencia y politica de refresco (ejecutar separado)
SELECT MVIEW_NAME, REFRESH_MODE, REFRESH_METHOD, BUILD_MODE,
       LAST_REFRESH_DATE
FROM USER_MVIEWS
WHERE MVIEW_NAME = 'MV_OCUPACION_MENSUAL';

-- FIGURA 2.13 - Consultar resultados de ocupacion mensual
SELECT m.NOMBRE AS MUNICIPIO,
       TO_CHAR(v.MES, 'YYYY-MM') AS MES,
       v.RESERVAS,
       v.NOCHES_OCUPADAS,
       v.NOCHES_DISPONIBLES,
       v.PORCENTAJE_OCUPACION
FROM MV_OCUPACION_MENSUAL v
JOIN MUNICIPIO m ON m.ID_MUNICIPIO = v.ID_MUNICIPIO
ORDER BY v.MES, m.NOMBRE
FETCH FIRST 20 ROWS ONLY;

-- Prueba adicional REFRESH MANUAL: no requiere figura distinta en Word.
-- Actualizacion manual de la vista (ejecutar separado)
ALTER MATERIALIZED VIEW MV_OCUPACION_MENSUAL COMPILE;
BEGIN
    DBMS_MVIEW.REFRESH('MV_OCUPACION_MENSUAL', 'C');
END;
/

-- Verificar ultima actualizacion (ejecutar separado)
SELECT MVIEW_NAME, REFRESH_MODE, REFRESH_METHOD, LAST_REFRESH_DATE
FROM USER_MVIEWS
WHERE MVIEW_NAME = 'MV_OCUPACION_MENSUAL';
