DECLARE
	V_MSQL VARCHAR2(4000 CHAR);
	V_COUNT NUMBER(16);
BEGIN
    V_MSQL := 'SELECT COUNT(1) FROM USER_CONSTRAINTS WHERE CONSTRAINT_TYPE = ''R'' AND STATUS = ''ENABLED''';
    EXECUTE IMMEDIATE V_MSQL INTO V_COUNT;
    DBMS_OUTPUT.PUT_LINE('[INFO] Hay '||V_COUNT||' claves foráneas para desactivar');
    
    IF V_COUNT > 0 THEN
        FOR I IN (SELECT TABLE_NAME, CONSTRAINT_NAME --disable first the foreign key
            FROM USER_CONSTRAINTS
            WHERE CONSTRAINT_TYPE = 'R' AND STATUS = 'ENABLED')
        LOOP
            IF I.TABLE_NAME LIKE 'BIN%' THEN
                DBMS_OUTPUT.PUT_LINE('   [INFO] No se desactiva para tabla '||I.TABLE_NAME);
            ELSE
            	V_MSQL := 'ALTER TABLE ' ||I.TABLE_NAME|| ' DISABLE CONSTRAINT ' ||I.CONSTRAINT_NAME;
                EXECUTE IMMEDIATE V_MSQL;
            END IF;
        END LOOP I;
    END IF;
    
    V_MSQL := 'SELECT COUNT(1) FROM USER_CONSTRAINTS WHERE STATUS = ''ENABLED''';
    EXECUTE IMMEDIATE V_MSQL INTO V_COUNT;
    DBMS_OUTPUT.PUT_LINE('[INFO] Hay '||V_COUNT||' claves para desactivar');
    
    IF V_COUNT > 0 THEN
        FOR I IN (SELECT TABLE_NAME, CONSTRAINT_NAME, CONSTRAINT_TYPE -- then disable all constraints
            FROM USER_CONSTRAINTS
            WHERE STATUS = 'ENABLED')
        LOOP
            IF I.TABLE_NAME LIKE 'BIN%' THEN
                DBMS_OUTPUT.PUT_LINE('   [INFO] No se desactiva para tabla '||I.TABLE_NAME);
            ELSE
                V_MSQL := 'ALTER TABLE ' ||I.TABLE_NAME|| ' DISABLE CONSTRAINT ' ||I.CONSTRAINT_NAME;
                EXECUTE IMMEDIATE V_MSQL;
            END IF;
        END LOOP I;
    END IF;
END;
/
EXIT