-- DBEAVER + ORACLE XE 21c.
-- Para SQL: ejecutar una sentencia. Para PL/SQL: seleccionar el bloque completo
-- DECLARE/BEGIN o CREATE...END; sin la linea / y usar Ejecutar sentencia SQL.
-- Conservar la misma conexion para SAVEPOINT/ROLLBACK. Activar salida DBMS Output.
-- ============================================================
-- TURISMOUQ - ENTREGA 2 - PUNTO 2.7 - FIGURA 2.10
-- Ejecutar como SYSTEM en XEPDB1 (puerto host 1522).
-- IMPORTANTE: ejecutar una unica vez sobre una base limpia.
-- No ejecutar nuevamente el CREATE si el tablespace ya existe.
-- ============================================================

-- A. Verificar conexion como SYSTEM
SELECT SYS_CONTEXT('USERENV','CON_NAME') AS CONTENEDOR,
       SYS_CONTEXT('USERENV','SESSION_USER') AS USUARIO
FROM DUAL;

-- B. Ubicacion del datafile existente (verificacion opcional)
SELECT TABLESPACE_NAME, FILE_NAME FROM DBA_DATA_FILES
WHERE TABLESPACE_NAME = 'USERS';

-- La ruta admite separadores de servidor Linux y Windows.
-- C. Crear junto a un datafile de la PDB actual (preferir USERS) (sin fijar XE/FREE).
-- Instalacion limpia: el nombre TS_TURISMOUQ_HIST aun no debe existir.
DECLARE
  v_ruta VARCHAR2(2000);
BEGIN
  SELECT SUBSTR(FILE_NAME,1,GREATEST(INSTR(FILE_NAME,'/',-1),INSTR(FILE_NAME,CHR(92),-1))) INTO v_ruta
  FROM DBA_DATA_FILES
  ORDER BY CASE WHEN TABLESPACE_NAME='USERS' THEN 0
    WHEN TABLESPACE_NAME NOT IN ('SYSTEM','SYSAUX') THEN 1 ELSE 2 END
  FETCH FIRST 1 ROW ONLY;
  EXECUTE IMMEDIATE 'CREATE TABLESPACE TS_TURISMOUQ_HIST DATAFILE '''||
    REPLACE(v_ruta,'''','''''')||'turismouq_hist01.dbf'' SIZE 20M '||
    'AUTOEXTEND ON NEXT 10M MAXSIZE 200M EXTENT MANAGEMENT LOCAL SEGMENT SPACE MANAGEMENT AUTO';
END;
/

-- D. Habilitar creacion de segmentos por TURISMOUQ
ALTER USER TURISMOUQ QUOTA 200M ON TS_TURISMOUQ_HIST;

-- E. FIGURA 2.10 - Verificacion que aparece en el Word
SELECT TABLESPACE_NAME, FILE_NAME,
       BYTES / 1024 / 1024 AS TAMANO_MB, AUTOEXTENSIBLE
FROM DBA_DATA_FILES
WHERE TABLESPACE_NAME = 'TS_TURISMOUQ_HIST';

-- Verificacion complementaria
SELECT TABLESPACE_NAME, STATUS
FROM DBA_TABLESPACES
WHERE TABLESPACE_NAME = 'TS_TURISMOUQ_HIST';
