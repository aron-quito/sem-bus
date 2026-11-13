# Estrategia de Sueldo Fijo Puro, Control de Aforo y Escalamiento de Flota – BusConectado Tacna

## 1. Tesis Económica: ¿Por qué Sueldo Fijo Puro y NO Pago por Pasajero?

En el transporte público tradicional de Tacna, el esquema de remuneración variable por pasajero (o pago de "cuenta diaria") genera un **incentivo perverso** conocido como la *"guerra del centavo"*:
- El chofer **sobrecarga la unidad** por encima de su capacidad cómoda y segura.
- Compite agresivamente por pasajeros, espera en esquinas y rompe frecuencias.
- Destruye la experiencia de puntualidad y confort que justifica la adopción de **BusConectado**.

Al establecer un **sueldo/tarifa fija mensual todo incluido (`S/ 6,500.00 / mes` base por bus con chofer propietario)**, se alinea el incentivo del conductor con la **calidad del servicio**:
1. **Cero incentivo a sobrecargar:** Como gana lo mismo subiendo 40 o 60 personas simultáneamente, el conductor respeta el **aforo máximo cómodo (40 pasajeros a bordo)** y no hacina usuarios.
2. **El riesgo moral inverso** *(que haga menos vueltas o salga tarde)* **se controla sin dinero variable por pasajero**, atando el pago fijo al **cumplimiento de SLA operativo auditado por la app**:
   - Cumplimiento ≥ 95 % de salidas y vueltas programadas (GPS en vivo).
   - Detención exclusiva en paraderos oficiales.
   - Respeto del horario punta y registro de validación QR en puerta.

---

## 2. Verificación Física Realista: ¿Se puede ser rentable SIN sobrecargar el bus?

Para comprobar que la rentabilidad no depende de hacinar pasajeros, modelamos la **capacidad física real** de un bus/cúster urbano en Tacna (~30 asientos + ~10 de pie cómodos = **40 pasajeros simultáneos máximo**) operando **12 horas/día** (26 días/mes) en rutas troncales (`UNJBG – Centro – Mercado Central – Cono Sur / Ciudad Nueva`):

| Indicador Operativo Realista | Peor Caso (Baja ocupación) | Caso Base (Estándar ordenado) | Mejor Caso (Alta rotación punta) |
| :--- | :---: | :---: | :---: |
| Vueltas completas por día (ida + vuelta) | 5 vueltas | 5.5 vueltas | 6 vueltas |
| Promedio de pasajeros simultáneos a bordo | 15–20 pax *(45 % aforo)* | 24–30 pax *(68 % aforo)* | 30–36 pax *(85 % aforo)* |
| Rotación por vuelta completa *(suben/bajan)* | 35 pax / vuelta | 55 pax / vuelta | 63 pax / vuelta |
| **Total pasajeros validados / día / bus** | **175 pax / día** | **300 pax / día** | **380 pax / día** |
| **Total pasajeros / mes / bus (26 días)** | **4,550 pax / mes** | **7,800 pax / mes** | **9,880 pax / mes** |

> **Conclusión física:** Incluso en el **Mejor Caso (`380 pax/día`)**, el bus nunca supera el **85 % del aforo cómodo** porque los pasajeros rotan entre paraderos (UNJBG, Plaza Vea, Mercado Central, paraderos barriales). **No se necesita sobrecargar el bus para ser rentable.**

---

## 3. Supuestos Financieros Reales (Tarifas, Comisiones y Costos)

| Parámetro | Peor Caso | Caso Base | Mejor Caso | Sustento |
| :--- | :---: | :---: | :---: | :--- |
| **Mix Tarifario (Gen S/1.50 / Med S/0.70 / CONADIS S/0)** | 55 % / 38 % / 7 % | 70 % / 25 % / 5 % | 78 % / 20 % / 2 % | Tarifas reales configuradas en la app. |
| **Tarifa Bruta Ponderada** | S/ 1.091 | S/ 1.225 | S/ 1.310 | Promedio ponderado por mezcla de usuarios. |
| **Comisión Pasarela / QR** | 3.5 % | 2.5 % | 1.8 % | Yape/Plin/Culqi/Niubiz según volumen transaccional. |
| **Ingreso Neto por Pasajero** | **S/ 1.053** | **S/ 1.194** | **S/ 1.286** | Ingreso real depositado tras comisiones. |
| **Pago Fijo Bus + Chofer / Mes** | **S/ 7,000.00** | **S/ 6,500.00** | **S/ 6,000.00** | Sueldo chofer + combustible + mantenimiento + desgaste. |

### Punto de Equilibrio Unitario por Bus (`Breakeven`)
$$\text{Pax/día necesarios por bus} = \frac{\text{Costo Fijo Bus}}{26 \times \text{Ingreso Neto/pax}}$$

- **Peor Caso (`S/ 7,000`, `S/ 1.053`):** `256 pax/día` (`51 pax/vuelta`).
- **Caso Base (`S/ 6,500`, `S/ 1.194`):** **`210 pax/día`** (`38 pax/vuelta`).
- **Mejor Caso (`S/ 6,000`, `S/ 1.286`):** `180 pax/día` (`30 pax/vuelta`).

---

## 4. Estrategia de Flota Escalonada (Blindaje Financiero sin Tocar el Sueldo Fijo)

En lugar de contratar **5 buses desde el Mes 1** (lo que expone la caja a pérdidas altas si la adopción digital es lenta), se implementa un **escalamiento por gatillos de demanda**:

### Fase 1: Arranque Controlado – 2 Buses *(Solo se activa Fase 2 si superan 250 pax/día por bus)*
*Gasto fijo plataforma ajustado a arranque: `S/ 2,200.00 / mes` (cloud `S/ 600` + soporte/monitoreo `S/ 1,200` + contabilidad `S/ 400`).*

| Escenario (2 Buses) | Demanda | Ingreso Neto/Mes | Costo Buses (`2×`) | Gasto Fijo Empresa | **Utilidad / Pérdida Neta** | **Margen Neto %** |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Peor Caso** | 175 pax/día | S/ 9,582.30 | S/ 14,000.00 | S/ 2,200.00 | **- S/ 6,617.70** | -69.1 % *(acotado)* |
| **Caso Base (arranque)** | 280 pax/día | S/ 17,384.64 | S/ 13,000.00 | S/ 2,200.00 | **+ S/ 2,184.64** | **+12.6 %** ✅ |
| **Mejor Caso** | 380 pax/día | S/ 25,411.36 | S/ 12,000.00 | S/ 2,200.00 | **+ S/ 11,211.36** | **+44.1 %** ✅ |

### Fase 2: Consolidación – 5 Buses *(Meta: Superar el 20 % de Margen Neto)*
*Gasto fijo plataforma escalado: `S/ 4,500.00 / mes`.*

| Escenario (5 Buses) | Demanda | Ingreso Neto/Mes | Costo Buses (`5×`) | Gasto Fijo Empresa | **Utilidad / Pérdida Neta** | **Margen Neto %** |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Peor Caso** *(si no se frena)* | 175 pax/día | S/ 23,955.75 | S/ 35,000.00 | S/ 4,500.00 | **- S/ 15,544.25** | *(Evitado por gatillo)* |
| **Caso Base** | 300 pax/día | S/ 46,566.00 | S/ 32,500.00 | S/ 4,500.00 | **+ S/ 9,566.00** | **+20.5 %** ✅ |
| **Mejor Caso** | 380 pax/día | S/ 63,528.40 | S/ 30,000.00 | S/ 4,500.00 | **+ S/ 29,028.40** | **+45.7 %** ✅ |

### Fase 3: Escala Urbana – 10 Buses *(Economía de Escala)*
*Gasto fijo plataforma: `S/ 6,500.00 / mes` (el costo fijo por bus baja de `S/ 1,100` en Fase 1 a `S/ 650/bus`).*

| Escenario (10 Buses) | Demanda | Ingreso Neto/Mes | Costo Buses (`10×`) | Gasto Fijo Empresa | **Utilidad Neta / Mes** | **Margen Neto %** |
| :--- | :---: | :---: | :---: | :---: | :---: | :---: |
| **Caso Base** | 300 pax/día | S/ 93,132.00 | S/ 65,000.00 | S/ 6,500.00 | **+ S/ 21,632.00** | **+23.2 %** ✅ |
| **Mejor Caso** | 380 pax/día | S/ 127,056.80 | S/ 60,000.00 | S/ 6,500.00 | **+ S/ 60,556.80** | **+47.7 %** ✅ |

---

## 5. Reglas de Decisión para la Ejecución
1. **Mantener el Sueldo Fijo Puro (`S/ 6,500/mes`):** Nunca pagar comisión por pasajero al chofer para garantizar cero sobrecarga y cero correteo.
2. **Condicionar el Sueldo Fijo a SLA GPS:** El pago completo exige cumplimiento ≥ 95 % de vueltas, horarios y paradas oficiales en la app de chofer.
3. **Regla de Gatillo de Flota:** Arrancar con **2 buses**; solo incorporar el 3.º, 4.º y 5.º bus cuando los activos superen **250 pax/día** sostenidos durante 3 semanas. Con **5 buses a 300 pax/día**, el proyecto supera el **20 % de margen neto (`+20.5 %`, `S/ 9,566/mes`)** sin sobrecargar ninguna unidad.

