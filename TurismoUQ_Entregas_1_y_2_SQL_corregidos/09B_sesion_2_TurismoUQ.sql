-- DBEAVER + ORACLE XE 21c.
-- Para SQL: ejecutar una sentencia. Para PL/SQL: seleccionar el bloque completo
-- DECLARE/BEGIN o CREATE...END; sin la linea / y usar Ejecutar sentencia SQL.
-- Conservar la misma conexion para SAVEPOINT/ROLLBACK. Activar salida DBMS Output.
-- CONEXION DBEAVER: TURISMOUQ. Ejecutar solo en esta cuenta.
DECLARE
BEGIN
 IF SYS_CONTEXT('USERENV','SESSION_USER')<>'TURISMOUQ' THEN
  RAISE_APPLICATION_ERROR(-20410,'Seleccionar la conexion TURISMOUQ en DBeaver');
 END IF;
END;
/
SELECT SYS_CONTEXT('USERENV','SID') SID_B FROM DUAL;
-- DBEAVER + ORACLE XE 21c.
-- Para SQL: ejecutar una sentencia. Para PL/SQL: seleccionar el bloque completo
-- DECLARE/BEGIN o CREATE...END; sin la linea / y usar Ejecutar sentencia SQL.
-- Conservar la misma conexion para SAVEPOINT/ROLLBACK. Activar salida DBMS Output.
BEGIN DBMS_APPLICATION_INFO.SET_MODULE('TQ_E3_B',NULL); END;
/
-- FASE 1: ejecutar SOLO cuando A haya tomado la Figura 3.5.
-- ABRIR OTRA CONEXION FISICA como TURISMOUQ. AUTOCOMMIT OFF.
-- Ejecutar SOLO el bloque que indique CAPTURAS_EN_ORDEN_TurismoUQ.sql.
-- FASE SIN BLOQUEO: despues de la insercion no confirmada de A, Figura 3.5.
BEGIN
 DBMS_APPLICATION_INFO.SET_MODULE('TQ_E3_B',NULL);
 SP_E3_RESERVAR_LAB('B_SIN_BLOQUEO',0);
END;
/
COMMIT;
SELECT * FROM E3_LAB_RESERVA ORDER BY ID_RESERVA;
-- TOMAR FIGURA 3.6. No ejecutar FASE 2 hasta que A lo indique.

-- FASE 2 CON BLOQUEO: solo cuando A indique Figura 3.7.
-- Este bloque DEBE quedar esperando hasta el COMMIT de A.
BEGIN
 DBMS_APPLICATION_INFO.SET_MODULE('TQ_E3_B',NULL);
 SP_E3_RESERVAR_LAB('B_CON_BLOQUEO',1);
 RAISE_APPLICATION_ERROR(-20990,'Fallo: se acepto la segunda reserva');
EXCEPTION WHEN OTHERS THEN
 IF SQLCODE<>-20201 THEN RAISE; END IF;
 DBMS_OUTPUT.PUT_LINE('CORRECTO: ORA-20201 despues del COMMIT de A; segunda reserva rechazada');
END;
/
ROLLBACK;
