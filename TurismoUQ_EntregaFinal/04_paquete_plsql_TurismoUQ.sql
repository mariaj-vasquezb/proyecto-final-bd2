-- DBEAVER + ORACLE XE 21c.
-- Para SQL: ejecutar una sentencia. Para PL/SQL: seleccionar el bloque completo
-- DECLARE/BEGIN o CREATE...END; sin la linea / y usar Ejecutar sentencia SQL.
-- Conservar la misma conexion para SAVEPOINT/ROLLBACK. Activar salida DBMS Output.
-- ==============================================================
-- TURISMOUQ | ENTREGA 2 | 04 PAQUETE PL/SQL
-- Integrantes: Maria Jose Vasquez, Luisa Osorio,
--              Amed Santiago Vargas Zambrano
-- Oracle XE 21c | Esquema TURISMOUQ
-- ==============================================================
-- DBeaver: configurar '/' en linea independiente como delimitador PL/SQL.
-- Requiere 01_modelo_tablas y 02_carga_datos completados.
-- No modifica las 25.000 reservas al compilar.
-- ==============================================================

-- BLOQUE 1 DE 2: ESPECIFICACION DEL PAQUETE
CREATE OR REPLACE PACKAGE PKG_TURISMOUQ AS
  -- Suma las tarifas de cada noche; checkout no se cobra.
  FUNCTION FN_VALOR_ESTADIA(
    p_id_habitacion IN HABITACION.ID_HABITACION%TYPE,
    p_fecha_in      IN DATE,
    p_fecha_out     IN DATE
  ) RETURN NUMBER;

  -- Una reserva de una habitacion; crea cabecera y detalle.
  -- Toma primero el mutex y despues la habitacion, antes de consultar disponibilidad.
  PROCEDURE SP_CREAR_RESERVA(
    p_id_cliente     IN CLIENTE.ID_CLIENTE%TYPE,
    p_id_habitacion  IN HABITACION.ID_HABITACION%TYPE,
    p_fecha_in       IN DATE,
    p_fecha_out      IN DATE,
    p_num_huespedes  IN NUMBER,
    p_id_reserva     OUT RESERVA.ID_RESERVA%TYPE
  );

  -- Total vigente: noches a tarifa actual mas servicios a precio contratado.
  FUNCTION FN_TOTAL_RESERVA(p_id_reserva IN NUMBER) RETURN NUMBER;
  FUNCTION FN_SALDO_RESERVA(p_id_reserva IN NUMBER) RETURN NUMBER;
  FUNCTION FN_RESERVA_PAGADA(p_id_reserva IN NUMBER) RETURN VARCHAR2;
  -- Cinco dias exactos o menos: 0%; mas de cinco: 80% de pagos cobrados.
  FUNCTION FN_REEMBOLSO(p_id_reserva IN NUMBER, p_fecha_cancelacion IN DATE) RETURN NUMBER;
  -- Requiere los triggers de 05; no confirma la transaccion del llamador.
  PROCEDURE SP_CANCELAR_RESERVA(p_id_reserva IN NUMBER, p_fecha_cancelacion IN DATE DEFAULT SYSDATE);

  -- Cursor explicito parametrizado: liquidacion de pagos
  -- exitosos por alojamiento en un mes concreto.
  PROCEDURE SP_LIQUIDACION_MENSUAL(
    p_anio IN NUMBER,
    p_mes  IN NUMBER
  );
END PKG_TURISMOUQ;
/

-- BLOQUE 2 DE 2: CUERPO DEL PAQUETE
CREATE OR REPLACE PACKAGE BODY PKG_TURISMOUQ AS

  FUNCTION FN_VALOR_ESTADIA(
    p_id_habitacion IN HABITACION.ID_HABITACION%TYPE,
    p_fecha_in      IN DATE,
    p_fecha_out     IN DATE
  ) RETURN NUMBER IS
    v_dia     DATE;
    v_precio  TARIFA.PRECIO_NOCHE%TYPE;
    v_total   NUMBER(16,2) := 0;
    v_existe  NUMBER;
  BEGIN
    IF p_fecha_in IS NULL OR p_fecha_out IS NULL
       OR TRUNC(p_fecha_out) <= TRUNC(p_fecha_in) THEN
      RAISE_APPLICATION_ERROR(-20001,
        'La fecha de salida debe ser posterior a la entrada');
    END IF;

    SELECT COUNT(*) INTO v_existe
      FROM HABITACION
     WHERE ID_HABITACION = p_id_habitacion;
    IF v_existe = 0 THEN
      RAISE_APPLICATION_ERROR(-20002, 'Habitacion inexistente');
    END IF;

    v_dia := TRUNC(p_fecha_in);
    WHILE v_dia < TRUNC(p_fecha_out) LOOP
      BEGIN
        SELECT t.PRECIO_NOCHE INTO v_precio
          FROM TARIFA t
          JOIN TEMPORADA s ON s.ID_TEMPORADA = t.ID_TEMPORADA
         WHERE t.ID_HABITACION = p_id_habitacion
           AND v_dia >= TRUNC(s.FECHA_INICIO)
           AND v_dia <= TRUNC(s.FECHA_FIN);
      EXCEPTION
        WHEN NO_DATA_FOUND THEN
          RAISE_APPLICATION_ERROR(-20003,
            'Falta tarifa para la noche '||TO_CHAR(v_dia,'YYYY-MM-DD'));
        WHEN TOO_MANY_ROWS THEN
          RAISE_APPLICATION_ERROR(-20004,
            'Existen temporadas solapadas para '||TO_CHAR(v_dia,'YYYY-MM-DD'));
      END;
      v_total := v_total + v_precio;
      v_dia := v_dia + 1;
    END LOOP;
    RETURN v_total;
  END FN_VALOR_ESTADIA;

  PROCEDURE SP_CREAR_RESERVA(
    p_id_cliente     IN CLIENTE.ID_CLIENTE%TYPE,
    p_id_habitacion  IN HABITACION.ID_HABITACION%TYPE,
    p_fecha_in       IN DATE,
    p_fecha_out      IN DATE,
    p_num_huespedes  IN NUMBER,
    p_id_reserva     OUT RESERVA.ID_RESERVA%TYPE
  ) IS
    v_capacidad HABITACION.CAPACIDAD%TYPE;
    v_activa    HABITACION.ACTIVA%TYPE;
    v_ocupadas  NUMBER;
    v_cliente   NUMBER;
    v_control   NUMBER;
  BEGIN
    p_id_reserva:=NULL;
    SAVEPOINT sp_crear_reserva_interno;
    SELECT ID_CONTROL INTO v_control FROM CONTROL_INTEGRIDAD WHERE ID_CONTROL=1 FOR UPDATE;
    IF p_fecha_in IS NULL OR p_fecha_out IS NULL
       OR TRUNC(p_fecha_out) <= TRUNC(p_fecha_in) THEN
      RAISE_APPLICATION_ERROR(-20010,
        'CHECKOUT debe ser posterior a CHECKIN');
    END IF;

    IF p_num_huespedes IS NULL OR p_num_huespedes < 1
       OR p_num_huespedes <> TRUNC(p_num_huespedes) THEN
      RAISE_APPLICATION_ERROR(-20011,
        'Numero de huespedes debe ser entero positivo');
    END IF;

    SELECT COUNT(*) INTO v_cliente
      FROM CLIENTE WHERE ID_CLIENTE = p_id_cliente;
    IF v_cliente = 0 THEN
      RAISE_APPLICATION_ERROR(-20012, 'Cliente inexistente');
    END IF;

    BEGIN
      SELECT CAPACIDAD, ACTIVA INTO v_capacidad, v_activa
        FROM HABITACION
       WHERE ID_HABITACION = p_id_habitacion FOR UPDATE;
    EXCEPTION
      WHEN NO_DATA_FOUND THEN
        RAISE_APPLICATION_ERROR(-20013, 'Habitacion inexistente');
    END;

    IF v_activa <> 'S' THEN
      RAISE_APPLICATION_ERROR(-20014, 'Habitacion inactiva');
    END IF;
    IF p_num_huespedes > v_capacidad THEN
      RAISE_APPLICATION_ERROR(-20015,
        'Capacidad excedida. Maximo permitido: '||v_capacidad);
    END IF;

    -- Intervalos [entrada,salida): salir el mismo dia que
    -- otro grupo entra no constituye un solapamiento.
    SELECT COUNT(*) INTO v_ocupadas
      FROM RESERVA_HABITACION rh
      JOIN RESERVA r ON r.ID_RESERVA = rh.ID_RESERVA
     WHERE rh.ID_HABITACION = p_id_habitacion
       AND r.ESTADO IN ('CONFIRMADA', 'COMPLETADA')
       AND rh.FECHA_CHECKIN < TRUNC(p_fecha_out)
       AND rh.FECHA_CHECKOUT > TRUNC(p_fecha_in);

    IF v_ocupadas > 0 THEN
      RAISE_APPLICATION_ERROR(-20016,
        'Habitacion no disponible para las fechas solicitadas');
    END IF;

    -- Verifica que hay tarifa para cada noche antes de insertar.
    -- Permite detectar rangos fuera de las temporadas cargadas.
    DECLARE
      v_importe NUMBER;
    BEGIN
      v_importe := FN_VALOR_ESTADIA(p_id_habitacion,p_fecha_in,p_fecha_out);
    END;

    INSERT INTO RESERVA(
      ID_CLIENTE,FECHA_RESERVA,FECHA_CHECKIN,FECHA_CHECKOUT,ESTADO
    ) VALUES (
      p_id_cliente,SYSDATE,TRUNC(p_fecha_in),TRUNC(p_fecha_out),'PENDIENTE'
    ) RETURNING ID_RESERVA INTO p_id_reserva;

    INSERT INTO RESERVA_HABITACION(
      ID_RESERVA,ID_HABITACION,FECHA_CHECKIN,FECHA_CHECKOUT,NUM_HUESPEDES
    ) VALUES (
      p_id_reserva,p_id_habitacion,TRUNC(p_fecha_in),
      TRUNC(p_fecha_out),p_num_huespedes
    );

    UPDATE RESERVA SET ESTADO='CONFIRMADA' WHERE ID_RESERVA=p_id_reserva;
    -- No COMMIT: el llamador conserva el control de la transaccion.
  EXCEPTION
    WHEN OTHERS THEN
      ROLLBACK TO sp_crear_reserva_interno;
      p_id_reserva:=NULL;
      RAISE;
  END SP_CREAR_RESERVA;

  FUNCTION FN_TOTAL_RESERVA(p_id_reserva IN NUMBER) RETURN NUMBER IS
    v_total NUMBER:=0;
    v_servicios NUMBER;
    v_n NUMBER;
  BEGIN
    SELECT COUNT(*) INTO v_n FROM RESERVA WHERE ID_RESERVA=p_id_reserva;
    IF v_n=0 THEN RAISE_APPLICATION_ERROR(-20017,'Reserva inexistente'); END IF;
    FOR d IN (SELECT ID_HABITACION,FECHA_CHECKIN,FECHA_CHECKOUT
              FROM RESERVA_HABITACION WHERE ID_RESERVA=p_id_reserva) LOOP
      v_total:=v_total+FN_VALOR_ESTADIA(d.ID_HABITACION,d.FECHA_CHECKIN,d.FECHA_CHECKOUT);
    END LOOP;
    SELECT NVL(SUM(CANTIDAD*PRECIO_UNITARIO),0) INTO v_servicios
    FROM RESERVA_SERVICIO WHERE ID_RESERVA=p_id_reserva;
    RETURN ROUND(v_total+v_servicios,2);
  END;

  FUNCTION FN_SALDO_RESERVA(p_id_reserva IN NUMBER) RETURN NUMBER IS
    v_pagado NUMBER;
    v_estado RESERVA.ESTADO%TYPE;
  BEGIN
    BEGIN SELECT ESTADO INTO v_estado FROM RESERVA WHERE ID_RESERVA=p_id_reserva;
    EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20017,'Reserva inexistente'); END;
    IF v_estado='CANCELADA' THEN RETURN 0; END IF;
    SELECT NVL(SUM(MONTO-MONTO_REEMBOLSADO),0) INTO v_pagado FROM PAGO
    WHERE ID_RESERVA=p_id_reserva AND ESTADO IN ('EXITOSO','REEMBOLSADO');
    RETURN GREATEST(FN_TOTAL_RESERVA(p_id_reserva)-v_pagado,0);
  END;

  FUNCTION FN_RESERVA_PAGADA(p_id_reserva IN NUMBER) RETURN VARCHAR2 IS
    v_estado RESERVA.ESTADO%TYPE;
  BEGIN
    BEGIN SELECT ESTADO INTO v_estado FROM RESERVA WHERE ID_RESERVA=p_id_reserva;
    EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20017,'Reserva inexistente'); END;
    IF v_estado<>'CANCELADA' AND FN_TOTAL_RESERVA(p_id_reserva)>0 AND FN_SALDO_RESERVA(p_id_reserva)=0 THEN
      RETURN 'S';
    END IF;
    RETURN 'N';
  END;

  FUNCTION FN_REEMBOLSO(p_id_reserva IN NUMBER,p_fecha_cancelacion IN DATE) RETURN NUMBER IS
    v_entrada DATE;
    v_creacion DATE;
    v_importe NUMBER;
  BEGIN
    BEGIN SELECT FECHA_CHECKIN,FECHA_RESERVA INTO v_entrada,v_creacion
      FROM RESERVA WHERE ID_RESERVA=p_id_reserva;
    EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20017,'Reserva inexistente'); END;
    IF p_fecha_cancelacion IS NULL OR p_fecha_cancelacion<v_creacion OR p_fecha_cancelacion>v_entrada THEN
      RAISE_APPLICATION_ERROR(-20038,'Cancelacion fuera del periodo permitido');
    END IF;
    IF v_entrada-p_fecha_cancelacion<=5 THEN RETURN 0; END IF;
    SELECT NVL(SUM(ROUND(MONTO*.8,2)),0) INTO v_importe FROM PAGO
    WHERE ID_RESERVA=p_id_reserva AND ESTADO IN ('EXITOSO','REEMBOLSADO');
    RETURN v_importe;
  END;

  PROCEDURE SP_CANCELAR_RESERVA(p_id_reserva IN NUMBER,p_fecha_cancelacion IN DATE DEFAULT SYSDATE) IS
    v_control NUMBER;
    v_estado RESERVA.ESTADO%TYPE;
    v_cotizacion NUMBER;
  BEGIN
    SAVEPOINT sp_cancelar_reserva_interno;
    SELECT ID_CONTROL INTO v_control FROM CONTROL_INTEGRIDAD WHERE ID_CONTROL=1 FOR UPDATE;
    BEGIN SELECT ESTADO INTO v_estado FROM RESERVA WHERE ID_RESERVA=p_id_reserva FOR UPDATE;
    EXCEPTION WHEN NO_DATA_FOUND THEN RAISE_APPLICATION_ERROR(-20017,'Reserva inexistente'); END;
    IF v_estado IN ('COMPLETADA','CANCELADA') THEN
      RAISE_APPLICATION_ERROR(-20037,'No se cancela una reserva en estado final');
    END IF;
    v_cotizacion:=FN_REEMBOLSO(p_id_reserva,p_fecha_cancelacion);
    UPDATE RESERVA SET ESTADO='CANCELADA',FECHA_CANCELACION=p_fecha_cancelacion WHERE ID_RESERVA=p_id_reserva;
    -- El trigger de cabecera registra en PAGO el reembolso de cada abono.
  EXCEPTION WHEN OTHERS THEN
    ROLLBACK TO sp_cancelar_reserva_interno;
    RAISE;
  END;

  PROCEDURE SP_LIQUIDACION_MENSUAL(
    p_anio IN NUMBER,
    p_mes  IN NUMBER
  ) IS
    v_desde DATE;
    v_hasta DATE;
    -- Evita contar un pago completo mas de una vez si la
    -- reserva contiene varias habitaciones/alojamientos.
    CURSOR c_liquidacion(cp_desde DATE, cp_hasta DATE) IS
      WITH aloj_por_reserva AS (
        SELECT rh.ID_RESERVA, h.ID_ALOJAMIENTO,
               COUNT(*) AS CANT_HAB
          FROM RESERVA_HABITACION rh
          JOIN HABITACION h ON h.ID_HABITACION = rh.ID_HABITACION
         GROUP BY rh.ID_RESERVA, h.ID_ALOJAMIENTO
      ), total_hab AS (
        SELECT ID_RESERVA, SUM(CANT_HAB) AS TOTAL_HAB
          FROM aloj_por_reserva GROUP BY ID_RESERVA
      )
      SELECT a.ID_ALOJAMIENTO, a.NOMBRE,
             ROUND(SUM((p.MONTO-p.MONTO_REEMBOLSADO) * ar.CANT_HAB / th.TOTAL_HAB),2) INGRESO_MES
        FROM PAGO p
        JOIN aloj_por_reserva ar ON ar.ID_RESERVA = p.ID_RESERVA
        JOIN total_hab th ON th.ID_RESERVA = p.ID_RESERVA
        JOIN ALOJAMIENTO a ON a.ID_ALOJAMIENTO = ar.ID_ALOJAMIENTO
       WHERE p.ESTADO IN ('EXITOSO','REEMBOLSADO')
         AND p.FECHA_PAGO >= cp_desde
         AND p.FECHA_PAGO < cp_hasta
       GROUP BY a.ID_ALOJAMIENTO, a.NOMBRE
       ORDER BY a.ID_ALOJAMIENTO;
    v_id ALOJAMIENTO.ID_ALOJAMIENTO%TYPE;
    v_nombre ALOJAMIENTO.NOMBRE%TYPE;
    v_ingreso NUMBER;
    v_filas PLS_INTEGER := 0;
  BEGIN
    IF p_anio IS NULL OR p_mes IS NULL OR p_anio<>TRUNC(p_anio) OR
       p_anio NOT BETWEEN 2024 AND 2100 OR p_mes NOT BETWEEN 1 AND 12 OR p_mes <> TRUNC(p_mes) THEN
      RAISE_APPLICATION_ERROR(-20020, 'Anio o mes invalido');
    END IF;

    v_desde := TO_DATE(TO_CHAR(p_anio,'FM0000')||'-'||
                       LPAD(TO_CHAR(p_mes),2,'0')||'-01','YYYY-MM-DD');
    v_hasta := ADD_MONTHS(v_desde,1);

    DBMS_OUTPUT.PUT_LINE('LIQUIDACION MENSUAL '||TO_CHAR(v_desde,'YYYY-MM'));
    OPEN c_liquidacion(v_desde,v_hasta);
    LOOP
      FETCH c_liquidacion INTO v_id,v_nombre,v_ingreso;
      EXIT WHEN c_liquidacion%NOTFOUND;
      v_filas := v_filas + 1;
      DBMS_OUTPUT.PUT_LINE(v_id||' | '||v_nombre||' | COP '||
                           TO_CHAR(v_ingreso,'FM999G999G999G990D00'));
    END LOOP;
    CLOSE c_liquidacion;
    DBMS_OUTPUT.PUT_LINE('Alojamientos con ingresos: '||v_filas);
  END SP_LIQUIDACION_MENSUAL;

END PKG_TURISMOUQ;
/

-- BLOQUE DE VERIFICACION (ejecutar al terminar ambos CREATE)
SELECT OBJECT_NAME, OBJECT_TYPE, STATUS
  FROM USER_OBJECTS
 WHERE OBJECT_NAME = 'PKG_TURISMOUQ'
 ORDER BY OBJECT_TYPE;

-- Si algun objeto es INVALID, consultar:
-- SELECT TYPE, LINE, POSITION, TEXT FROM USER_ERRORS
-- WHERE NAME = 'PKG_TURISMOUQ' ORDER BY SEQUENCE;
