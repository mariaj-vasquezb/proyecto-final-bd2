-- DBEAVER + ORACLE XE 21c.
-- Para SQL: ejecutar una sentencia. Para PL/SQL: seleccionar el bloque completo
-- DECLARE/BEGIN o CREATE...END; sin la linea / y usar Ejecutar sentencia SQL.
-- Conservar la misma conexion para SAVEPOINT/ROLLBACK. Activar salida DBMS Output.
-- ENTREGA 3. Ejecutar como TURISMOUQ despues de la entrega 2.
CREATE GLOBAL TEMPORARY TABLE E3_DEMO_TX (
 ETIQUETA VARCHAR2(40) PRIMARY KEY, ID_RESERVA NUMBER, ID_PAGO NUMBER
) ON COMMIT PRESERVE ROWS;

CREATE OR REPLACE PROCEDURE SP_RESERVA_PAGO_ATOMICA(
 p_cliente NUMBER,p_habitacion NUMBER,p_entrada DATE,p_salida DATE,
 p_huespedes NUMBER,p_monto NUMBER,p_metodo VARCHAR2,
 p_reserva OUT NUMBER,p_pago OUT NUMBER
) AUTHID DEFINER IS
BEGIN
 p_reserva:=NULL; p_pago:=NULL;
 SAVEPOINT e3_reserva_pago;
 PKG_TURISMOUQ.SP_CREAR_RESERVA(p_cliente,p_habitacion,p_entrada,p_salida,p_huespedes,p_reserva);
 -- Se comprueba el pago DESPUES de crear la reserva para probar el rollback.
 IF p_monto IS NULL OR p_monto<=0 OR p_metodo IS NULL OR
    p_metodo NOT IN ('CREDITO','DEBITO','PSE','TRANSFERENCIA','EFECTIVO') THEN
   RAISE_APPLICATION_ERROR(-20101,'Pago invalido: reserva y pago se revierten juntos');
 END IF;
 INSERT INTO PAGO(ID_RESERVA,MONTO,METODO,ESTADO)
 VALUES(p_reserva,p_monto,p_metodo,'EXITOSO') RETURNING ID_PAGO INTO p_pago;
 -- No COMMIT: el llamador decide el destino de la unidad completa.
EXCEPTION WHEN OTHERS THEN
 ROLLBACK TO e3_reserva_pago; p_reserva:=NULL; p_pago:=NULL; RAISE;
END;
/
