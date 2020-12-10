--/*
--#########################################
--## AUTOR=DAP
--## FECHA_CREACION=20180718
--## ARTEFACTO=batch
--## VERSION_ARTEFACTO=?
--## INCIDENCIA_LINK=SCHVIP-1364
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

	V_TABLA VARCHAR2(30 CHAR) := 'ACT_ICO_INFO_COMERCIAL'; -- Variable para tabla de salida para el borrado
	V_USUARIO VARCHAR2(50 CHAR) := 'DAP';
	V_BORRADO_FISICO VARCHAR2(2 CHAR) := 'SI';--SI o NO, no vale ningún otro valor ni minúsculas, ni acentos.

	V_ESQUEMA VARCHAR2(25 CHAR):= 'SCH01';-- '#ESQUEMA#'; -- Configuracion Esquema
	V_ESQUEMA_M VARCHAR2(25 CHAR):= 'SCHMASTER';-- '#ESQUEMA_MASTER#'; -- Configuracion Esquema Master
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
                        AND NOT EXISTS (SELECT 1 FROM ACTIVOS_A_BORRAR AUX WHERE AUX.TABLA_REF = T2.OWNER||''.''||T2.TABLE_NAME)
                    )        
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
	    USING (SELECT ICO_ID 
	      FROM '||V_ESQUEMA||'.'||V_TABLA||'
	      WHERE ICO_ID = 68418) T2
	    ON (T1.ICO_ID = T2.ICO_ID)
	    WHEN MATCHED THEN UPDATE SET
	        T1.USUARIOBORRAR = '''||V_USUARIO||''', T1.BORRADO = 1, T1.FECHABORRAR = SYSDATE
        WHERE T1.BORRADO = 0';

	IF V_BORRADO_FISICO <> 'SI' AND V_BORRADO_FISICO <> 'NO' THEN
		DBMS_OUTPUT.PUT_LINE('[ERROR] No se ha configurado correctamente la variable de borrado físico.');
	ELSE
	    DBMS_OUTPUT.PUT_LINE('[INICIO] Inicio del proceso de borrado.');
	    --TRUNCAMOS TABLAS AUXILIARES
	    EXECUTE IMMEDIATE 'TRUNCATE TABLE '||V_ESQUEMA||'.ACTIVOS_A_BORRAR';
	    EXECUTE IMMEDIATE 'TRUNCATE TABLE '||V_ESQUEMA||'.ACTIVOS_A_BORRAR_2';
	    
	    DBMS_OUTPUT.PUT_LINE('');

	    --EMPEZAMOS A CALCULAR DEPENDENCIAS DE TABLA PRINCIPAL
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
	    EXECUTE IMMEDIATE V_STMT_VAL;

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
	    UNION SELECT DISTINCT TABLA_REF, ORDEN_TABLA_REF FROM '||V_ESQUEMA||'.ACTIVOS_A_BORRAR';
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
	        V_MSQL := 'SELECT COUNT(1) FROM '||V_ESQUEMA||'.'||V_TABLA||' WHERE USUARIOBORRAR = '''||V_USUARIO||''' AND BORRADO = 1';
	        EXECUTE IMMEDIATE V_MSQL INTO ACTIVOS;
	        DBMS_OUTPUT.PUT_LINE('	[CON_AUDITORIA {A   BORRAR}]: TABLA '||V_ESQUEMA||'.'||V_TABLA||' - '||ACTIVOS||' registros marcados para posterior borrado.');
	    	
	    	--SELECCIONAMOS LA TABLA/CLAVE Y LA TABLA DEPENDIENTE/CLAVE FORANEA A BORRAR
	        V_MSQL := 'SELECT TABLA, CLAVE_TABLA, TABLA_REF, CLAVE_REF FROM '||V_ESQUEMA||'.ACTIVOS_A_BORRAR ORDER BY ID ASC';
	        --RECORSCHOS EL RESULTADO DE LA QUERY ANTERIOR
	        OPEN V_VAL_CURSOR FOR V_MSQL;
	            LOOP
	            FETCH V_VAL_CURSOR INTO TABLA, CLAVE_TABLA, TABLA_REF, CLAVE_REF;
	            --SALDSCHOS DEL CURSOR CUANDO NO HAYA MÁS FILAS QUE RECORRER
	            EXIT WHEN V_VAL_CURSOR%NOTFOUND;
	            
	            DECLARE
	                SIN_AUDITORIA EXCEPTION;
	                PRAGMA EXCEPTION_INIT(SIN_AUDITORIA, -904);
	            BEGIN
	            	--BORRAMOS DE MANERA LÓGICA LOS REGISTROS DE LA TABLA/CLAVE CON DEPENDENCIAS EN TABLA DEPENDIENTE/CLAVE FORANEA
	                V_MSQL := 'MERGE INTO '||TABLA||' T1 
					    USING (SELECT '||CLAVE_REF||' 
					        FROM '||TABLA_REF||' T2 
					        WHERE T2.USUARIOBORRAR = '''||V_USUARIO||''' AND T2.BORRADO = 1) T2 
					    ON ('||CLAVE_TABLA||' = '||CLAVE_REF||')
					    WHEN MATCHED THEN UPDATE SET
					        T1.USUARIOBORRAR = '''||V_USUARIO||''', T1.BORRADO = 1, T1.FECHABORRAR = SYSDATE';
	                EXECUTE IMMEDIATE V_MSQL;
	                DBMS_OUTPUT.PUT_LINE('	[CON_AUDITORIA {A   BORRAR}]: TABLA '||TABLA||' - '||SQL%ROWCOUNT||' registros marcados para posterior borrado.');
	            EXCEPTION
	            	--SI LA TABLA O TABLA DEPENDENDIENTE NO TIENE CAMPOS DE AUDITORIA, SE CAPTURA CON LA EXCEPCION DECLARADA ABAJO
	                WHEN SIN_AUDITORIA THEN
	                DECLARE
	                    SIN_AUDITORIA EXCEPTION;
	                    PRAGMA EXCEPTION_INIT(SIN_AUDITORIA, -904);
	                BEGIN
	                	--SE BORRAN FÍSICAMENTE LOS REGISTROS DE TABLAS QUE NO TENGAN AUDITORÍA, SIEMPRE Y CUANDO EL BORRADO SEA FÍSICO
	                	IF V_BORRADO_FISICO = 'SI' THEN
		                    V_MSQL := 'DELETE FROM '||TABLA||' T1 WHERE EXISTS (SELECT 1 FROM '||TABLA_REF||' T2 WHERE '||CLAVE_REF||' = '||CLAVE_TABLA||' AND T2.USUARIOBORRAR = '''||V_USUARIO||''' AND T2.BORRADO = 1)';
		                    EXECUTE IMMEDIATE V_MSQL;
		                    DBMS_OUTPUT.PUT_LINE('	[SIN_AUDITORIA {A   BORRAR}]: TABLA '||TABLA||' - '||SQL%ROWCOUNT||' registros borrados directamente');
		                ELSE
		                	NULL;
                        END IF;
	                EXCEPTION
	                	--SE BORRAN DE MANERA LÓGICA LOS REGISTROS QUE EN SU TABLA DEPENDIENTE NO TENGAN DEPENDENCIA, ES DECIR, REGISTROS HUÉRFANOS
	                    WHEN SIN_AUDITORIA THEN
	                    V_MSQL := 'MERGE INTO '||TABLA||' T1
	                        USING (SELECT '||CLAVE_TABLA||'
	                            FROM '||TABLA||' T1
	                            LEFT JOIN '||TABLA_REF||' T2 ON '||CLAVE_REF||' = '||CLAVE_TABLA||'
	                            WHERE '||CLAVE_REF||' IS NULL) T2
	                        ON ('||CLAVE_TABLA||' = ''T2.''||SUBSTR('||CLAVE_TABLA||',4) )
	                        WHEN MATCHED THEN UPDATE SET
	                            T1.USUARIOBORRAR = '''||V_USUARIO||''', T1.BORRADO = 1, T1.FECHABORRAR = SYSDATE';
	                    EXECUTE IMMEDIATE V_MSQL;
	                    DBMS_OUTPUT.PUT_LINE('	[SIN_AUDITORIA {REFERENCIA}]: TABLA '||TABLA_REF||' - '||SQL%ROWCOUNT||' registros huérfanos borrados directamente.');
	                END;
	            END;
	    
	            END LOOP;
	        CLOSE V_VAL_CURSOR;
	        DBMS_OUTPUT.PUT_LINE('[FIN] Borrado lógico.');
	        --FINALIZA EL BORRADO LÓGICO
	        COMMIT;

	        --SI HEMOS MARCADO PARA REALIZAR BORRADO FISICO, COMIENZA AQUÍ, SINO TERMINA EL SCRIPT
	        IF V_BORRADO_FISICO = 'SI' THEN
                DBMS_OUTPUT.PUT_LINE('');
                DBMS_OUTPUT.PUT_LINE('[INICIO] Borrado físico.');
	        	--SELECCIONAMOS DE LA TABLA PIVOTADA LA TABLA A BORRAR DE MANERA DESCENDENTE, ES DECIR
	        		--, DESDE LA ÚLTIMA DE LAS TABLAS HASTA LA TABLA PRINCIPAL QUE QUESCHOS BORRAR
		        V_MSQL := 'SELECT TABLA, SUBSTR(CLAVE,4) CLAVE
		            FROM (
		                SELECT T1.TABLA TABLA, T2.CLAVE_TABLA CLAVE, T1.ORDEN_TABLA ORDEN
		                FROM '||V_ESQUEMA||'.ACTIVOS_A_BORRAR_2 T1
		                JOIN '||V_ESQUEMA||'.ACTIVOS_A_BORRAR T2 ON T1.TABLA = T2.TABLA AND T1.ORDEN_TABLA = T2.ORDEN_TABLA
		                UNION
		                SELECT T1.TABLA, T2.CLAVE_REF CLAVE, T1.ORDEN_TABLA ORDEN
		                FROM '||V_ESQUEMA||'.ACTIVOS_A_BORRAR_2 T1
		                JOIN '||V_ESQUEMA||'.ACTIVOS_A_BORRAR T2 ON T1.TABLA = T2.TABLA_REF AND T1.ORDEN_TABLA = T2.ORDEN_TABLA_REF)
		            ORDER BY ORDEN DESC';
		        OPEN V_VAL_CURSOR FOR V_MSQL;
		            LOOP
		            FETCH V_VAL_CURSOR INTO TABLA_EXCEPTION, CLAVE_EXCEPTION;
		            --SALIMOS DEL CURSOR CUANDO NO HAYA MÁS FILAS DE LA TABLA PIVOTADA QUE RECORRER
		            EXIT WHEN V_VAL_CURSOR%NOTFOUND;
		            BEGIN
		            	--SE BORRAN LOS REGISTROS CON BORRADO LÓGICO
						V_MSQL := 'DELETE FROM '||TABLA_EXCEPTION||' WHERE USUARIOBORRAR = '''||V_USUARIO||''' AND BORRADO = 1';
						EXECUTE IMMEDIATE V_MSQL;
						DBMS_OUTPUT.PUT_LINE('	[BORRADA]: TABLA '||TABLA_EXCEPTION||' - '||SQL%ROWCOUNT||' registros eliminados.');
		            EXCEPTION
		            	--SI NO SE PUEDE BORRAR POR PROBLEMAS DE DEPENDENCIAS CRUZADAS SE PONE A NULO EL CAMPO CLAVE
		                WHEN BORRADO_FK THEN
		                    BEGIN
		                        DBMS_OUTPUT.PUT_LINE('	[NO BORRADA - PROBLEMA FK]: TABLA '||TABLA_EXCEPTION||'.');
		                        V_MSQL := 'UPDATE '||TABLA_EXCEPTION||' SET '||CLAVE_EXCEPTION||' = NULL WHERE USUARIOBORRAR = '''||V_USUARIO||''' AND BORRADO = 1';
		                        EXECUTE IMMEDIATE V_MSQL;
		                    END;
		                --SI NO TIENE AUDITORIA, COMO YA SE HA BORRADO EN LA FASE LOGICA NO HACEMOS NADA
		                WHEN SIN_AUDITORIA THEN
		                    NULL;
		                --SI NO SE PUEDE BORRAR POR PROBLEMAS DE DEPENDENCIA, SE PONE A NULO LA CLAVE
		                WHEN BORRADO_FK2 THEN
		                    BEGIN
		                        DBMS_OUTPUT.PUT_LINE('	[NO BORRADA - PROBLEMA FK]: TABLA '||TABLA_EXCEPTION||'.');
		                        V_MSQL := 'UPDATE '||TABLA_EXCEPTION||' SET '||CLAVE_EXCEPTION||' = NULL WHERE USUARIOBORRAR = '''||V_USUARIO||''' AND BORRADO = 1';
		                        EXECUTE IMMEDIATE V_MSQL;
		                    END;
		            END;
		        END LOOP;
		        CLOSE V_VAL_CURSOR;
		        
		        COMMIT;
		        DBMS_OUTPUT.PUT_LINE('[FIN] Borrado físico.');

		    END IF;
	        
	    END LOOP;
	END IF;

EXCEPTION
    WHEN OTHERS THEN
      DBMS_OUTPUT.PUT_LINE('[ERROR] Se ha producido un error en la ejecución:'||TO_CHAR(SQLCODE));
      DBMS_OUTPUT.PUT_LINE('-----------------------------------------------------------');
      DBMS_OUTPUT.PUT_LINE(SQLERRM);
      DBMS_OUTPUT.PUT_LINE(V_MSQL);
      DBMS_OUTPUT.PUT_LINE(TABLA||' '||TABLA_EXCEPTION||' '||CLAVE_TABLA||' '||CLAVE_EXCEPTION);
      ROLLBACK;
      RAISE;
END;
/
EXIT;
