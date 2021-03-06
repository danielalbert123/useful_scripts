--/*
--#########################################
--## AUTOR=DAP
--## FECHA_CREACION=20180420
--## ARTEFACTO=batch
--## VERSION_ARTEFACTO=?
--## INCIDENCIA_LINK=XXXX
--## PRODUCTO=NO
--## 
--## Finalidad: Proceso de borrado lógico o físico
--##            , según V_BORRADO_FISICO
--## INSTRUCCIONES:  
--## VERSIONES:
--##        0.1 Versión inicial
--#########################################
--*/
--Para permitir la visualización de texto en un bloque PL/SQL utilizando DBMS_OUTPUT.PUT_LINE
WHENEVER SQLERROR EXIT SQL.SQLCODE;
SET SERVEROUTPUT ON;
SET DEFINE OFF;

DECLARE

	V_TABLA VARCHAR2(30 CHAR) := 'ACT_ACTIVO'; -- Variable para tabla de salida para el borrado
	V_USUARIO VARCHAR2(50 CHAR) := 'DAP';

	V_ESQUEMA VARCHAR2(25 CHAR):= 'ESQ_01';-- '#ESQUEMA#'; -- Configuracion Esquema
	V_ESQUEMA_M VARCHAR2(25 CHAR):= 'ESQ_MASTER';-- '#ESQUEMA_MASTER#'; -- Configuracion Esquema Master
	ERR_NUM NUMBER;-- Numero de errores
	ERR_MSG VARCHAR2(2048);-- Mensaje de error
	V_MSQL VARCHAR2(4000 CHAR);
	V_REGISTROS VARCHAR2(4000 CHAR);
	TYPE VALCURTYP IS REF CURSOR;
	V_VAL_CURSOR VALCURTYP;
	V_STMT_VAL VARCHAR2(4000 CHAR);
	TABLA VARCHAR2(63 CHAR);
	CLAVE_TABLA VARCHAR(140 CHAR);
	TABLA_REF VARCHAR2(63 CHAR);
	CLAVE_REF VARCHAR(140 CHAR);
	TABLA_EXCEPTION VARCHAR2(63 CHAR);
	CLAVE_EXCEPTION VARCHAR(140 CHAR);
	CANTIDAD_INSERCIONES NUMBER (16);
	SIN_AUDITORIA EXCEPTION;
	PRAGMA EXCEPTION_INIT(SIN_AUDITORIA, -904);
	BORRADO_FK EXCEPTION;
	PRAGMA EXCEPTION_INIT(BORRADO_FK, -1407);
	BORRADO_FK2 EXCEPTION;
	PRAGMA EXCEPTION_INIT(BORRADO_FK2, -2292);
	ACTIVOS NUMBER(6);
	NUMERO_BORRAR NUMBER(6) := 1000;--Numero de activos a borrar en una pasada
	ORDEN NUMBER(2) := 2;

	--PROCEDURE PARA CALCULAR LAS DEPENDENCIAS ENTRE TABLAS
	PROCEDURE BORRADO (ORDEN IN NUMBER, NUMERO_INSERTADO OUT NUMBER) IS
	BEGIN
		V_STMT_VAL := '
		    INSERT INTO '||V_ESQUEMA||'.ACTIVOS_A_BORRAR
		    SELECT '||V_ESQUEMA||'.S_ACTIVOS_A_BORRAR.NEXTVAL, TABLA, CLAVE_TABLA, ORDEN, TABLA_REF, CLAVE_REF, ORDEN_REF 
		    FROM (
		        WITH DEPENDENCIAS AS (
		        SELECT T1.OWNER ESQUEMA, T1.TABLE_NAME TABLE_NAME, T1.CONSTRAINT_NAME, T3.COLUMN_NAME COLUMN_NAME, T3.POSITION POSITION_KEY
		         , T2.OWNER ESQUEMA_REF, T2.TABLE_NAME TABLE_REFERENCED, T2.CONSTRAINT_NAME CONSTRAINT_REFERENCED, T4.COLUMN_NAME COLUMN_REFERENCED, T4.POSITION POSITION_KEY_REFERENCED
		        FROM ALL_CONSTRAINTS T1
		        JOIN ALL_CONSTRAINTS T2 ON T2.CONSTRAINT_NAME = T1.R_CONSTRAINT_NAME
		         AND T2.CONSTRAINT_TYPE IN (''P'', ''U'')
		        JOIN '||V_ESQUEMA||'.ACTIVOS_A_BORRAR T5 ON T5.TABLA = T2.OWNER||''.''||T2.TABLE_NAME
		        JOIN ALL_CONS_COLUMNS T3 ON T1.CONSTRAINT_NAME = T3.CONSTRAINT_NAME
		        JOIN ALL_CONS_COLUMNS T4 ON T2.CONSTRAINT_NAME = T4.CONSTRAINT_NAME
		        WHERE T1.CONSTRAINT_TYPE = ''R'' AND T1.STATUS = ''ENABLED''
		            AND NOT EXISTS (SELECT 1 FROM ACTIVOS_A_BORRAR AUX WHERE AUX.TABLA_REF = T2.OWNER||''.''||T2.TABLE_NAME))
		        SELECT D.ESQUEMA||''.''||D.TABLE_NAME TABLA, ''T1.''||LISTAGG(D.COLUMN_NAME, ''||T1.'') WITHIN GROUP (ORDER BY D.POSITION_KEY) CLAVE_TABLA
		        , '||ORDEN||' + 1 ORDEN
		        , D.ESQUEMA_REF||''.''||D.TABLE_REFERENCED TABLA_REF, ''T2.''||LISTAGG(D.COLUMN_REFERENCED, ''||T2.'') WITHIN GROUP (ORDER BY D.POSITION_KEY_REFERENCED) CLAVE_REF
		        , '||ORDEN||' ORDEN_REF
		        FROM DEPENDENCIAS D
		        GROUP BY D.ESQUEMA, D.TABLE_NAME, D.CONSTRAINT_NAME, D.ESQUEMA_REF, D.TABLE_REFERENCED, D.CONSTRAINT_REFERENCED)';
		EXECUTE IMMEDIATE V_STMT_VAL;
		NUMERO_INSERTADO := SQL%ROWCOUNT;
	END;

BEGIN
	
	--ESTOS SON LOS REGISTROS A BORRAR
	V_REGISTROS := 'MERGE INTO '||V_ESQUEMA||'.'||V_TABLA||' T1
	    USING (SELECT BIE_ID 
	      FROM '||V_ESQUEMA||'.ACT_ACTIVO
	      WHERE ACT_NUM_ACTIVO = 150394) T2
	    ON (T1.BIE_ID = T2.BIE_ID)
	    WHEN MATCHED THEN UPDATE SET
	        T1.USUARIOBORRAR = '''||V_USUARIO||''', T1.BORRADO = 0, T1.FECHABORRAR = SYSDATE
        WHERE T1.BORRADO = 1';

    DBMS_OUTPUT.PUT_LINE('[INICIO] Inicio del proceso de reactivado.');
    --TRUNCAMOS TABLAS AUXILIARES
    EXECUTE IMMEDIATE 'TRUNCATE TABLE '||V_ESQUEMA||'.ACTIVOS_A_BORRAR';
    EXECUTE IMMEDIATE 'TRUNCATE TABLE '||V_ESQUEMA||'.ACTIVOS_A_BORRAR_2';
    
    DBMS_OUTPUT.PUT_LINE('');
    
    --EMPEZAMOS A CALCULAR DEPENDENCIAS DE TABLA PRINCIPAL
    V_MSQL := '
        INSERT INTO '||V_ESQUEMA||'.ACTIVOS_A_BORRAR
        SELECT '||V_ESQUEMA||'.S_ACTIVOS_A_BORRAR.NEXTVAL, TABLA, CLAVE_TABLA, ORDEN, TABLA_REF, CLAVE_REF, ORDEN_REF 
        FROM (
            WITH DEPENDENCIAS AS (
             SELECT T1.OWNER ESQUEMA, T1.TABLE_NAME TABLE_NAME, T1.CONSTRAINT_NAME, T3.COLUMN_NAME COLUMN_NAME, T3.POSITION POSITION_KEY
                 , T2.OWNER ESQUEMA_REF, T2.TABLE_NAME TABLE_REFERENCED, T2.CONSTRAINT_NAME CONSTRAINT_REFERENCED, T4.COLUMN_NAME COLUMN_REFERENCED, T4.POSITION POSITION_KEY_REFERENCED
             FROM ALL_CONSTRAINTS T1
             JOIN ALL_CONSTRAINTS T2 ON T2.CONSTRAINT_NAME = T1.R_CONSTRAINT_NAME
                 AND T2.CONSTRAINT_TYPE IN (''P'', ''U'')
                 AND T2.TABLE_NAME IN ('''||V_TABLA||''')
                 AND T2.OWNER = '''||V_ESQUEMA||'''
             JOIN ALL_CONS_COLUMNS T3 ON T1.CONSTRAINT_NAME = T3.CONSTRAINT_NAME
             JOIN ALL_CONS_COLUMNS T4 ON T2.CONSTRAINT_NAME = T4.CONSTRAINT_NAME
             WHERE T1.CONSTRAINT_TYPE = ''R'' AND T1.STATUS = ''ENABLED'')        
            SELECT D.ESQUEMA||''.''||D.TABLE_NAME TABLA, ''T1.''||LISTAGG(D.COLUMN_NAME, ''||T1.'') WITHIN GROUP (ORDER BY D.POSITION_KEY) CLAVE_TABLA
               , 1 ORDEN
               , D.ESQUEMA_REF||''.''||D.TABLE_REFERENCED TABLA_REF, ''T2.''||LISTAGG(D.COLUMN_REFERENCED, ''||T2.'') WITHIN GROUP (ORDER BY D.POSITION_KEY_REFERENCED) CLAVE_REF
               , 0 ORDEN_REF
            FROM DEPENDENCIAS D
            GROUP BY D.ESQUEMA, D.TABLE_NAME, D.CONSTRAINT_NAME, D.ESQUEMA_REF, D.TABLE_REFERENCED, D.CONSTRAINT_REFERENCED)';
    EXECUTE IMMEDIATE V_MSQL;
    
    --CALCULAMOS EN BUCLE DEPENDENCIAS DE TABLAS EN CASCADA
    BORRADO(ORDEN, CANTIDAD_INSERCIONES);
    WHILE CANTIDAD_INSERCIONES > 0
    LOOP
       ORDEN := ORDEN + 2;
       BORRADO(ORDEN, CANTIDAD_INSERCIONES);
    END LOOP;
    
    --PIVOTAMOS LA TABLA AUXILIAR
    V_MSQL := 'INSERT INTO '||V_ESQUEMA||'.ACTIVOS_A_BORRAR_2
    SELECT DISTINCT TABLA, ORDEN_TABLA FROM '||V_ESQUEMA||'.ACTIVOS_A_BORRAR
    UNION 
    SELECT DISTINCT TABLA_REF, ORDEN_TABLA_REF FROM '||V_ESQUEMA||'.ACTIVOS_A_BORRAR';
    EXECUTE IMMEDIATE V_MSQL;
    
    COMMIT;

    --COMENZAMOS EL BORRADO LÓGICO
    LOOP
        --SE BORRAN LOS REGISTROS QUE SELECCIONEMOS EN ESTA QUERY (ESTÁ DENTRO DEL LOOP POR SI DECIDIMOS BORRAR REGISTROS EN GRUPOS DE 10, 100 O 1000 REGISTROS)
        V_MSQL := V_REGISTROS;
        EXECUTE IMMEDIATE V_MSQL;
        --SALIMOS DEL BUCLE CUANDO NO HAYA MÁS REGISTROS A BORRAR
        EXIT WHEN SQL%ROWCOUNT = 0;
    
        --BUSCAMOS SI EXISTEN REGISTROS BORRADOS DE MANERA LÓGICA
        V_MSQL := 'SELECT COUNT(1) FROM '||V_ESQUEMA||'.'||V_TABLA||' WHERE USUARIOBORRAR = '''||V_USUARIO||''' AND BORRADO = 0';
        EXECUTE IMMEDIATE V_MSQL INTO ACTIVOS;
        DBMS_OUTPUT.PUT_LINE('	[CON_AUDITORIA {REACTIVAMOS}]: TABLA '||V_ESQUEMA||'.'||V_TABLA||' - '||ACTIVOS||' registros reactivados.');
        
        --SELECCIONAMOS LA TABLA/CLAVE Y LA TABLA DEPENDIENTE/CLAVE FORANEA A BORRAR
        V_MSQL := 'SELECT TABLA, CLAVE_TABLA, TABLA_REF, CLAVE_REF FROM '||V_ESQUEMA||'.ACTIVOS_A_BORRAR ORDER BY ID ASC';
        --RECORREMOS EL RESULTADO DE LA QUERY ANTERIOR
        OPEN V_VAL_CURSOR FOR V_MSQL;
            LOOP
            FETCH V_VAL_CURSOR INTO TABLA, CLAVE_TABLA, TABLA_REF, CLAVE_REF;
            --SALDREMOS DEL CURSOR CUANDO NO HAYA MÁS FILAS QUE RECORRER
            EXIT WHEN V_VAL_CURSOR%NOTFOUND;
            
            DECLARE
                SIN_AUDITORIA EXCEPTION;
                PRAGMA EXCEPTION_INIT(SIN_AUDITORIA, -904);
            BEGIN
                --BORRAMOS DE MANERA LÓGICA LOS REGISTROS DE LA TABLA/CLAVE CON DEPENDENCIAS EN TABLA DEPENDIENTE/CLAVE FORANEA
                V_MSQL := 'MERGE INTO '||TABLA||' T1 
                    USING (SELECT '||CLAVE_REF||' 
                        FROM '||TABLA_REF||' T2 
                        WHERE T2.USUARIOBORRAR = '''||V_USUARIO||''' AND T2.BORRADO = 0) T2 
                    ON ('||CLAVE_TABLA||' = '||CLAVE_REF||')
                    WHEN MATCHED THEN UPDATE SET
                        T1.USUARIOBORRAR = '''||V_USUARIO||''', T1.BORRADO = 0, T1.FECHABORRAR = NULL
                    WHERE T1.BORRADO = 1';
                EXECUTE IMMEDIATE V_MSQL;
                DBMS_OUTPUT.PUT_LINE('	[CON_AUDITORIA {REACTIVAMOS}]: TABLA '||TABLA||' - '||SQL%ROWCOUNT||' registros reactivados.');
            EXCEPTION
                --SI LA TABLA O TABLA DEPENDENDIENTE NO TIENE CAMPOS DE AUDITORIA, SE CAPTURA CON LA EXCEPCION DECLARADA ABAJO
                WHEN SIN_AUDITORIA THEN
                DECLARE
                    SIN_AUDITORIA EXCEPTION;
                    PRAGMA EXCEPTION_INIT(SIN_AUDITORIA, -904);
                BEGIN
                    NULL;
                EXCEPTION
                    --SE BORRAN DE MANERA LÓGICA LOS REGISTROS QUE EN SU TABLA DEPENDIENTE NO TENGAN DEPENDENCIA, ES DECIR, REGISTROS HUÉRFANOS
                    WHEN SIN_AUDITORIA THEN
                        NULL;
                END;
            END;
    
            END LOOP;
        CLOSE V_VAL_CURSOR;
        DBMS_OUTPUT.PUT_LINE('[FIN] Borrado lógico.');
        --FINALIZA EL BORRADO LÓGICO
        COMMIT;
    END LOOP;

EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('[ERROR] Se ha producido un error en la ejecución:'||TO_CHAR(SQLCODE));
      DBMS_OUTPUT.PUT_LINE('-----------------------------------------------------------');
      DBMS_OUTPUT.PUT_LINE(SQLERRM);
      DBMS_OUTPUT.PUT_LINE(V_MSQL);
      DBMS_OUTPUT.PUT_LINE(V_STMT_VAL);
      DBMS_OUTPUT.PUT_LINE(TABLA||' '||TABLA_EXCEPTION||' '||CLAVE_TABLA||' '||CLAVE_EXCEPTION);
      ROLLBACK;
      RAISE;
END;
/
EXIT;
