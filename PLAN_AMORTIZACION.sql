DROP TABLE SCH01.DATOS_INICIALES;
 
CREATE TABLE "SCH01"."DATOS_INICIALES" 
   (  "CNT_ID" NUMBER, 
"FECHA_CONS" DATE, 
"CUOTAS" NUMBER, 
"PAGOS_ANUALES" NUMBER, 
"CAPITAL" NUMBER, 
"TASA" NUMBER, 
"NUM_CUOTA" NUMBER(5,0)
   );

Insert into SCH01.DATOS_INICIALES (CNT_ID,FECHA_CONS,CUOTAS,PAGOS_ANUALES,CAPITAL,TASA,NUM_CUOTA) values ('1',to_date('31/05/19','DD/MM/RR'),'360','12','40000','1,99','1');
Insert into SCH01.DATOS_INICIALES (CNT_ID,FECHA_CONS,CUOTAS,PAGOS_ANUALES,CAPITAL,TASA,NUM_CUOTA) values ('2',to_date('15/01/16','DD/MM/RR'),'120','12','10000','0,99','1');
Insert into SCH01.DATOS_INICIALES (CNT_ID,FECHA_CONS,CUOTAS,PAGOS_ANUALES,CAPITAL,TASA,NUM_CUOTA) values ('3',to_date('31/05/19','DD/MM/RR'),'360','12','39015,28','0,52','13');
Insert into SCH01.DATOS_INICIALES (CNT_ID,FECHA_CONS,CUOTAS,PAGOS_ANUALES,CAPITAL,TASA,NUM_CUOTA) values ('4',to_date('31/05/20','DD/MM/RR'),'348','12','39015,28','0','1');

DROP TABLE SCH01.DANI_PLAN_AMORTIZACION;

CREATE TABLE SCH01.DANI_PLAN_AMORTIZACION (
  PAN_ID NUMBER(16,0) GENERATED ALWAYS AS IDENTITY,
  CNT_ID NUMBER(16,0),
  NUM_CUOTA NUMBER(5,0),
  TIPO NUMBER(22,21),
  CUOTA NUMBER(16,2),
  INTERESES NUMBER(16,2),
  CAPITAL_CUOTA NUMBER(16,2),
  CAPITAL_VIVO NUMBER(16,2),
  CAPITAL_VIVO_POSTERIOR NUMBER(16,2),
  FECHA_CUOTA DATE,
  FECHA_CUOTA_EFECTIVA DATE,
  CUOTAS_RESTANTES NUMBER(5,0),
  NUM_CUOTA_ANTERIOR NUMBER(5,0)
);

DROP TABLE TABLA_PIVOTAJE;

CREATE TABLE TABLA_PIVOTAJE AS (
SELECT ROWNUM NUM_CUOTA
FROM DUAL
CONNECT BY ROWNUM < 10000);

--INSERTAMOS EL NÚMERO DE REGISTROS NECESARIOS
INSERT INTO DANI_PLAN_AMORTIZACION (CNT_ID, TIPO)
SELECT CI.CNT_ID, DECODE(CI.TASA, 0, 0,000000001, CI.TASA/(100*CI.PAGOS_ANUALES)) TIPO
FROM DATOS_INICIALES CI
LEFT JOIN TABLA_PIVOTAJE CI2 ON 1 = 1
WHERE CI2.NUM_CUOTA <= CI.CUOTAS - CI.NUM_CUOTA + 1;

--INCREMENTOS Y DECREMENTOS
MERGE INTO DANI_PLAN_AMORTIZACION T1
USING (
  SELECT DI.PAN_ID, CI.CNT_ID, CI.NUM_CUOTA, CI.CUOTAS, ROW_NUMBER() OVER(PARTITION BY CI.CNT_ID ORDER BY 1) UNIDAD
  FROM DATOS_INICIALES CI
  JOIN DANI_PLAN_AMORTIZACION DI ON DI.CNT_ID = CI.CNT_ID
  ) T2
ON (T1.PAN_ID = T2.PAN_ID)
WHEN MATCHED THEN UPDATE SET
  T1.NUM_CUOTA = T2.NUM_CUOTA + T2.UNIDAD - 1
  , T1.NUM_CUOTA_ANTERIOR = T2.NUM_CUOTA + T2.UNIDAD - 2
  , T1.CUOTAS_RESTANTES = T2.CUOTAS - T2.NUM_CUOTA - T2.UNIDAD + 1;

--FECHAS
MERGE INTO DANI_PLAN_AMORTIZACION T1
USING (
  SELECT FECHA.PAN_ID
    , FECHA.CNT_ID
    , FECHA.FECHA_CUOTA
    , CASE 
        WHEN TO_CHAR(FECHA.FECHA_CUOTA, 'MM') = '08' AND TO_CHAR(FECHA.FECHA_CUOTA, 'DD') = '15' AND TO_CHAR(FECHA.FECHA_CUOTA + 1,'D') = 7 THEN
            FECHA.FECHA_CUOTA + 2
        WHEN TO_CHAR(FECHA.FECHA_CUOTA, 'MM') = '08' AND TO_CHAR(FECHA.FECHA_CUOTA, 'DD') = '15' AND TO_CHAR(FECHA.FECHA_CUOTA + 1,'D') <> 7 THEN 
            FECHA.FECHA_CUOTA + 1
        WHEN TO_CHAR(FECHA.FECHA_CUOTA,'D') = 7 THEN
            CASE 
                WHEN FES_DOM.FES_ID IS NOT NULL 
                    THEN TO_DATE(LPAD(TO_CHAR(FES_DOM.FES_DAY_END),2,0)||'/'||LPAD(TO_CHAR(FES_DOM.FES_MONTH),2,0)||'/'||TO_CHAR(FES_DOM.FES_YEAR),'DD/MM/YYYY') + 1 
                ELSE FECHA.FECHA_CUOTA + 1 END
        WHEN FES.FES_ID IS NOT NULL THEN TO_DATE(LPAD(TO_CHAR(FES.FES_DAY_END),2,0)||'/'||LPAD(TO_CHAR(FES.FES_MONTH),2,0)||'/'||TO_CHAR(FES.FES_YEAR),'DD/MM/YYYY') + 1
        ELSE FECHA.FECHA_CUOTA END FECHA_CUOTA_EFECTIVA
  FROM (
    SELECT CI.PAN_ID, CI.CNT_ID
      , ADD_MONTHS(DI.FECHA_CONS,CI.NUM_CUOTA) FECHA_CUOTA
    FROM DATOS_INICIALES DI
    JOIN DANI_PLAN_AMORTIZACION CI ON DI.CNT_ID = CI.CNT_ID
    ) FECHA
  LEFT JOIN FES_FESTIVOS FES_DOM ON TO_NUMBER(TO_CHAR(FECHA.FECHA_CUOTA + 1,'MM')) = FES_DOM.FES_MONTH 
      AND TO_NUMBER(TO_CHAR(FECHA.FECHA_CUOTA + 1,'DD')) BETWEEN FES_DOM.FES_DAY_START AND FES_DOM.FES_DAY_END 
      AND TO_NUMBER(TO_CHAR(FECHA.FECHA_CUOTA + 1,'YYYY')) = FES_DOM.FES_YEAR
      AND FES_DOM.FES_MONTH <> 8
  LEFT JOIN FES_FESTIVOS FES ON TO_NUMBER(TO_CHAR(FECHA.FECHA_CUOTA,'MM')) = FES.FES_MONTH 
      AND TO_NUMBER(TO_CHAR(FECHA.FECHA_CUOTA,'DD')) BETWEEN FES.FES_DAY_START AND FES.FES_DAY_END 
      AND TO_NUMBER(TO_CHAR(FECHA.FECHA_CUOTA,'YYYY')) = FES.FES_YEAR
      AND FES.FES_MONTH <> 8
  ) T2
ON (T1.PAN_ID = T2.PAN_ID)
WHEN MATCHED THEN UPDATE SET
  T1.FECHA_CUOTA_EFECTIVA = T2.FECHA_CUOTA_EFECTIVA;

--INTERESES Y CAPITALES
MERGE INTO DANI_PLAN_AMORTIZACION T1
USING (
  SELECT CI.PAN_ID
      , (1 - POWER(1/(1+CI.TIPO),CI.CUOTAS_RESTANTES + 1))/CI.TIPO FACTOR_AMORTIZACION
      , (DI.CAPITAL - 0) / (CI.TIPO * POWER(1 + CI.TIPO, DI.CUOTAS - DI.NUM_CUOTA + 1)) / ((POWER(1 + CI.TIPO, DI.CUOTAS - DI.NUM_CUOTA + 1) - 1 ) + (0 * CI.TIPO)) CUOTA
  FROM DANI_PLAN_AMORTIZACION CI
  JOIN DATOS_INICIALES DI ON DI.CNT_ID = CI.CNT_ID
  ) T2
ON (T1.PAN_ID = T2.PAN_ID)
WHEN MATCHED THEN UPDATE SET
  T1.CUOTA = ROUND(T2.CUOTA,2)
  , T1.INTERESES = ROUND(T2.FACTOR_AMORTIZACION * T2.CUOTA * T1.TIPO, 2)
  , T1.CAPITAL_VIVO = T2.FACTOR_AMORTIZACION * T2.CUOTA
  , T1.CAPITAL_CUOTA = ROUND(T2.CUOTA,2) - ROUND(T2.FACTOR_AMORTIZACION * T2.CUOTA * T1.TIPO, 2);
 
SELECT CI.PAN_ID
      , (1 - POWER(1/(1+CI.TIPO),CI.CUOTAS_RESTANTES + 1))/CI.TIPO FACTOR_AMORTIZACION
      , (DI.CAPITAL - 0) / (CI.TIPO * POWER(1 + CI.TIPO, DI.CUOTAS - DI.NUM_CUOTA + 1)) / ((POWER(1 + CI.TIPO, DI.CUOTAS - DI.NUM_CUOTA + 1) - 1 ) + (0 * CI.TIPO)) CUOTA
  FROM DANI_PLAN_AMORTIZACION CI
  JOIN DATOS_INICIALES DI ON DI.CNT_ID = CI.CNT_ID;

SELECT *
FROM DANI_PLAN_AMORTIZACION CI
ORDER BY CI.CNT_ID, CI.NUM_CUOTA;
 
/*
--PRIMERAS CUOTAS DE CADA CONTRATO
MERGE INTO DANI_PLAN_AMORTIZACION T1
USING (
	SELECT CI.CNT_ID
		, MIN(CI.NUM_CUOTA) NUM_CUOTA
		, DI.CAPITAL * CI.TIPO INTERESES
		, DI.CAPITAL CAPITAL_VIVO
		, CI.CUOTA - DI.CAPITAL * CI.TIPO CAPITAL_CUOTA
		, DI.CAPITAL - (CI.CUOTA - DI.CAPITAL * CI.TIPO) CAPITAL_VIVO_POSTERIOR
	FROM DATOS_INICIALES DI
	JOIN DANI_PLAN_AMORTIZACION CI ON CI.CNT_ID = DI.CNT_ID
	GROUP BY CI.CNT_ID, DI.CAPITAL, CI.CUOTA, CI.TIPO
	) T2
ON (T1.CNT_ID = T2.CNT_ID AND T1.NUM_CUOTA = T2.NUM_CUOTA)
WHEN MATCHED THEN UPDATE SET
	T1.INTERESES = T2.INTERESES
	, T1.CAPITAL_CUOTA = T2.CAPITAL_CUOTA
	, T1.CAPITAL_VIVO = T2.CAPITAL_VIVO
	, T1.CAPITAL_VIVO_POSTERIOR = T2.CAPITAL_VIVO_POSTERIOR;
	
SELECT CI.PAN_ID, CI.CNT_ID, CI.NUM_CUOTA
	, COALESCE(CI.INTERESES, LAG(CI.CAPITAL_VIVO_POSTERIOR,1) OVER (PARTITION BY CI.CNT_ID ORDER BY CI.NUM_CUOTA) * CI.TIPO) INTERESES
	, COALESCE(CI.CAPITAL_CUOTA, CI.CUOTA - COALESCE(CI.INTERESES, LAG(CI.CAPITAL_VIVO_POSTERIOR,1) OVER (PARTITION BY CI.CNT_ID ORDER BY CI.NUM_CUOTA) * CI.TIPO)) CAPITAL_CUOTA
	, CI.CUOTA
	, COALESCE(CI.CAPITAL_VIVO, LAG(CI.CAPITAL_VIVO_POSTERIOR,1) OVER (PARTITION BY CI.CNT_ID ORDER BY CI.NUM_CUOTA)) AS CAPITAL_VIVO
FROM DANI_PLAN_AMORTIZACION CI;*/

SELECT *
FROM RGF_PAN_CONTRATO_PLAN_AMORTIZACION rpcpa 

