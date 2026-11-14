-- DBEAVER + ORACLE XE 21c.
-- Para SQL: ejecutar una sentencia. Para PL/SQL: seleccionar el bloque completo
-- DECLARE/BEGIN o CREATE...END; sin la linea / y usar Ejecutar sentencia SQL.
-- Conservar la misma conexion para SAVEPOINT/ROLLBACK. Activar salida DBMS Output.
-- ==============================================================
-- TURISMOUQ | ENTREGA 2 | 05 PRUEBAS DE TRIGGERS
-- Oracle XE 21c | Ejecutar conectado como TURISMOUQ
-- ==============================================================
-- Activar DBMS Output en DBeaver.
-- Cada prueba usa SAVEPOINT y ROLLBACK para no dejar cambios permanentes.
-- ==============================================================

-- ==============================================================
-- PRUEBAS 2.5A Y 2.5B - FIGURAS 2.7 Y 2.8
-- ==============================================================

DECLARE
    v_id_tarifa        TARIFA.ID_TARIFA%TYPE;
    v_anterior         TARIFA.PRECIO_NOCHE%TYPE;
    v_nuevo            TARIFA.PRECIO_NOCHE%TYPE;
    v_id_auditoria     AUDITORIA_TARIFA.ID_AUDITORIA%TYPE;
    v_aud_anterior     AUDITORIA_TARIFA.PRECIO_ANTERIOR%TYPE;
    v_aud_nuevo        AUDITORIA_TARIFA.PRECIO_NUEVO%TYPE;
    v_usuario          AUDITORIA_TARIFA.USUARIO_CAMBIO%TYPE;
    v_fecha            AUDITORIA_TARIFA.FECHA_CAMBIO%TYPE;
    v_total_antes      NUMBER;
    v_total_despues    NUMBER;
    v_filas            NUMBER;
BEGIN
    SAVEPOINT sp_prueba_auditoria;

    SELECT COUNT(*)
    INTO v_total_antes
    FROM AUDITORIA_TARIFA;

    SELECT ID_TARIFA, PRECIO_NOCHE
    INTO v_id_tarifa, v_anterior
    FROM TARIFA
    WHERE ID_TARIFA = (SELECT MIN(ID_TARIFA) FROM TARIFA);

    v_nuevo := v_anterior + 1000;

    UPDATE TARIFA
    SET PRECIO_NOCHE = v_nuevo
    WHERE ID_TARIFA = v_id_tarifa;

    v_filas := SQL%ROWCOUNT;

    DBMS_OUTPUT.PUT_LINE('PRUEBA 2.5A - FIGURA 2.7 - CAMBIO DE TARIFA');
    DBMS_OUTPUT.PUT_LINE('ID_TARIFA: ' || v_id_tarifa);
    DBMS_OUTPUT.PUT_LINE('PRECIO ANTERIOR: ' || v_anterior);
    DBMS_OUTPUT.PUT_LINE('PRECIO NUEVO: ' || v_nuevo);
    DBMS_OUTPUT.PUT_LINE('FILAS MODIFICADAS: ' || v_filas);

    SELECT COUNT(*)
    INTO v_total_despues
    FROM AUDITORIA_TARIFA;

    IF v_total_despues <> v_total_antes + 1 THEN
        RAISE_APPLICATION_ERROR(
            -20051,
            'La auditoria no registro exactamente un cambio'
        );
    END IF;

    SELECT
        ID_AUDITORIA,
        PRECIO_ANTERIOR,
        PRECIO_NUEVO,
        USUARIO_CAMBIO,
        FECHA_CAMBIO
    INTO
        v_id_auditoria,
        v_aud_anterior,
        v_aud_nuevo,
        v_usuario,
        v_fecha
    FROM AUDITORIA_TARIFA
    WHERE ID_AUDITORIA = (
        SELECT MAX(ID_AUDITORIA)
        FROM AUDITORIA_TARIFA
        WHERE ID_TARIFA = v_id_tarifa
    );

    IF v_aud_anterior<>v_anterior OR v_aud_nuevo<>v_nuevo THEN
      RAISE_APPLICATION_ERROR(-20052,'Valores auditados incorrectos');
    END IF;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('PRUEBA 2.5B - FIGURA 2.8 - REGISTRO DE AUDITORIA');
    DBMS_OUTPUT.PUT_LINE('ID_AUDITORIA: ' || v_id_auditoria);
    DBMS_OUTPUT.PUT_LINE('PRECIO ANTERIOR REGISTRADO: ' || v_aud_anterior);
    DBMS_OUTPUT.PUT_LINE('PRECIO NUEVO REGISTRADO: ' || v_aud_nuevo);
    DBMS_OUTPUT.PUT_LINE('USUARIO: ' || v_usuario);
    DBMS_OUTPUT.PUT_LINE(
        'FECHA: ' || TO_CHAR(v_fecha, 'YYYY-MM-DD HH24:MI:SS')
    );

    ROLLBACK TO sp_prueba_auditoria;
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('CAMBIOS DE PRUEBA REVERTIDOS');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO sp_prueba_auditoria;
        RAISE;
END;
/

-- ==============================================================
-- PRUEBA 2.6 - FIGURA 2.9 - ORA-20026
-- ==============================================================

DECLARE
    v_id_reserva_hab   RESERVA_HABITACION.ID_RESERVA_HAB%TYPE;
    v_fecha_inicio     RESERVA_HABITACION.FECHA_CHECKIN%TYPE;
    v_fecha_fin        RESERVA_HABITACION.FECHA_CHECKOUT%TYPE;
    v_rechazado        BOOLEAN := FALSE;
BEGIN
    SAVEPOINT prueba_final_solapamiento;

    SELECT id_reserva_hab, fecha_checkin, fecha_checkout
    INTO v_id_reserva_hab, v_fecha_inicio, v_fecha_fin
    FROM (
        SELECT
            a.ID_RESERVA_HAB AS id_reserva_hab,
            b.FECHA_CHECKIN AS fecha_checkin,
            b.FECHA_CHECKOUT AS fecha_checkout
        FROM RESERVA_HABITACION a
        JOIN RESERVA ra
          ON ra.ID_RESERVA = a.ID_RESERVA
        JOIN RESERVA_HABITACION b
          ON b.ID_HABITACION = a.ID_HABITACION
         AND b.ID_RESERVA_HAB <> a.ID_RESERVA_HAB
        JOIN RESERVA rb
          ON rb.ID_RESERVA = b.ID_RESERVA
        WHERE ra.ESTADO IN ('CONFIRMADA', 'COMPLETADA')
          AND rb.ESTADO IN ('CONFIRMADA', 'COMPLETADA')
          AND b.FECHA_CHECKIN < b.FECHA_CHECKOUT
    )
    WHERE ROWNUM = 1;

    BEGIN
        UPDATE RESERVA_HABITACION
        SET FECHA_CHECKIN = v_fecha_inicio,
            FECHA_CHECKOUT = v_fecha_fin
        WHERE ID_RESERVA_HAB = v_id_reserva_hab;

        DBMS_OUTPUT.PUT_LINE('ERROR: SE PERMITIO EL SOLAPAMIENTO');

    EXCEPTION
        WHEN OTHERS THEN
            IF SQLCODE = -20026 THEN
                v_rechazado := TRUE;
                DBMS_OUTPUT.PUT_LINE('PRUEBA 2.6 - FIGURA 2.9');
                DBMS_OUTPUT.PUT_LINE('PRUEBA CORRECTA: ORA-20026');
                DBMS_OUTPUT.PUT_LINE('EL TRIGGER IMPIDIO EL SOLAPAMIENTO');
            ELSE
                RAISE;
            END IF;
    END;

    IF NOT v_rechazado THEN
        RAISE_APPLICATION_ERROR(
            -20050,
            'El solapamiento no fue rechazado'
        );
    END IF;

    ROLLBACK TO prueba_final_solapamiento;
    DBMS_OUTPUT.PUT_LINE('CAMBIOS DE PRUEBA REVERTIDOS');

EXCEPTION
    WHEN OTHERS THEN
        ROLLBACK TO prueba_final_solapamiento;
        RAISE;
END;
/

-- ==============================================================
-- VERIFICACION FINAL
-- ==============================================================

SELECT (
        SELECT COUNT(*)
        FROM RESERVA_HABITACION
    ) AS REGISTROS_ORIGINALES,
    (
        SELECT COUNT(*)
        FROM CONTROL_OCUPACION_RH
    ) AS REGISTROS_AUXILIARES,
    (
        SELECT COUNT(*)
        FROM (
                SELECT
                    ID_RESERVA_HAB, ID_RESERVA, ID_HABITACION, FECHA_CHECKIN, FECHA_CHECKOUT
                FROM RESERVA_HABITACION MINUS
                SELECT
                    ID_RESERVA_HAB, ID_RESERVA, ID_HABITACION, FECHA_CHECKIN, FECHA_CHECKOUT
                FROM CONTROL_OCUPACION_RH
            )
    ) AS FALTANTES,
    (
        SELECT COUNT(*)
        FROM (
                SELECT
                    ID_RESERVA_HAB, ID_RESERVA, ID_HABITACION, FECHA_CHECKIN, FECHA_CHECKOUT
                FROM CONTROL_OCUPACION_RH MINUS
                SELECT
                    ID_RESERVA_HAB, ID_RESERVA, ID_HABITACION, FECHA_CHECKIN, FECHA_CHECKOUT
                FROM RESERVA_HABITACION
            )
    ) AS SOBRANTES
FROM DUAL;

SELECT
    TRIGGER_NAME,
    TRIGGER_TYPE,
    TRIGGERING_EVENT,
    TABLE_NAME,
    STATUS
FROM USER_TRIGGERS
WHERE
    TRIGGER_NAME IN (
        'TRG_AUDITORIA_TARIFA',
        'TRG_CAPTURAR_CAMBIOS_TARIFA',
        'TRG_EVITAR_SOLAPAMIENTO'
    )
ORDER BY TRIGGER_NAME;
-- Rejillas que producen las Figuras 2.7 y 2.8, en la misma conexion y SIN autocommit.
-- Ejecutar este grupo completo; tomar ambas capturas antes del ROLLBACK TO.
SAVEPOINT captura_auditoria;
UPDATE TARIFA SET PRECIO_NOCHE=PRECIO_NOCHE+1000 WHERE ID_TARIFA=1;
SELECT ID_TARIFA,PRECIO_NOCHE FROM TARIFA WHERE ID_TARIFA=1;
SELECT ID_AUDITORIA,ID_TARIFA,PRECIO_ANTERIOR,PRECIO_NUEVO,USUARIO_CAMBIO,FECHA_CAMBIO
FROM AUDITORIA_TARIFA WHERE ID_TARIFA=1 ORDER BY ID_AUDITORIA DESC FETCH FIRST 1 ROW ONLY;
ROLLBACK TO captura_auditoria;
