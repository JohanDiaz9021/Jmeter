# Guía técnica v3: JMeter para el taller de Tiquetmania

Esta guía es la referencia de JMeter del taller: qué elementos existen, cómo se anidan y se combinan, qué tipos de escenario vas a construir y cómo leer los resultados. Las instrucciones de tu chat bot configurado como IA tutor se apoyan en esta guía. Cuando una instrucción diga "ver sección X", la sección está aquí.

Versión 3. Reemplaza a la v2. La v1 queda sin cambios.

---

## 1. Cómo usar esta guía

- Úsala como referencia cuando construyas un escenario. No la leas de corrido.
- Lo que está en esta guía es **JMeter** y **el escenario del taller**. El paso a paso de construcción lo hacen contigo tu chat bot configurado como IA tutor.
- El pipeline de GitHub Actions no está aquí: está en las instrucciones del tutor.

---

## 2. Preparación del entorno

- **Java 17 o superior:** `sudo apt install openjdk-17-jre-headless`. Verifica con `java -version`.
- **JMeter 5.6.3:** descomprímelo en tu carpeta de trabajo, por ejemplo `~/apache-jmeter-5.6.3/`. Para abrir la interfaz: `~/apache-jmeter-5.6.3/bin/jmeter`.
- **Carpeta de trabajo local:** `~/pruebas-jmeter/`.
- **Plugins (jpgc Standard Set y jpgc PerfMon Metrics Collector):** instálalos con el Plugins Manager. Están en la presentación de JMeter de la clase.
- **ServerAgent 2.2.1** para PerfMon: `https://github.com/undera/perfmon-agent/releases/download/2.2.1/ServerAgent-2.2.1.zip`. Se inicia con `./startAgent.sh` en Linux o Mac, o `startAgent.bat` en Windows. Usa el puerto 4444.

---

## 3. La API de Tiquetmania

- **Ejecutar:** `python3 api/ticketmania_simple.py`. Queda en `http://127.0.0.1:8080`. Otro puerto: `--puerto 9000`.
- **Verificar:** `GET /api/salud` responde `{"estado": "OK"}`.
- **Tarifas:** `GET /api/tarifas` lista `general`, `occidental`, `preferencial` y `vip`, con su precio.
- **Flujo de compra:** `POST /api/seleccion` crea una reserva con tarifa y cantidad. `POST /api/pago` paga esa reserva y la consume.
- **Datos:** en memoria. Si reinicias la API, se pierden las reservas.
- **Camino feliz:** el taller solo prueba compras válidas.

---

## 4. Elementos de JMeter

### 4.1 Tipos de elemento

Un plan de JMeter es un árbol de elementos. Estos son los tipos que usarás:

| Tipo | Qué hace | Ejemplos en el taller |
|---|---|---|
| **Plan de pruebas** | La raíz del árbol | Plan de Pruebas |
| **Grupo de hilos** | Define cuántos usuarios simulados hay, cómo entran y cuántas veces repiten el flujo | Grupo de Hilos estándar |
| **Muestreador (sampler)** | Envía una petición | Petición HTTP (GET, POST) |
| **Controlador lógico** | Agrupa o repite muestreadores | Controlador simple, Controlador de bucle |
| **Elemento de configuración** | Define valores que usan otros elementos | CSV Data Set Config, Gestor de Cabecera HTTP, Gestor de Cookies HTTP |
| **Preprocesador** | Se ejecuta antes de la petición | Debug Sampler (para depurar) |
| **Postprocesador (extractor)** | Saca datos de la respuesta para usarlos después | Extractor JSON |
| **Aserción** | Verifica la respuesta | Aserción JSON |
| **Temporizador** | Pone una pausa entre peticiones | Temporizador Aleatorio Uniforme, Temporizador Sincronizado |
| **Listener (escucha)** | Muestra o guarda resultados | Reporte resumen, Ver Árbol de Resultados |

Los nombres pueden variar un poco según la versión y el idioma de la interfaz. Busca el elemento por su tipo.

### 4.2 Árbol del plan y anidamiento

Así se anidan los elementos en el taller:

```
Plan de Pruebas                              (raíz)
├── Configuración del CSV Data Set           (elemento de configuración, aplica a todo el plan)
├── Gestor de Cookies HTTP                   (aplica a todo el plan)
├── Reporte resumen                          (listener, aplica a todo el plan)
└── Grupo de Hilos                           (obligatorio para los muestreadores)
    ├── Petición GET /api/tarifas            (muestreador)
    ├── Petición POST /api/seleccion         (muestreador)
    │   ├── Gestor de Cabecera HTTP          (aplica solo a esta petición)
    │   ├── Extractor JSON: num_reserva      (postprocesador, aplica solo a esta petición)
    │   └── Temporizador Aleatorio Uniforme  (aplica solo a esta petición)
    └── Petición POST /api/pago              (muestreador, usa ${num_reserva})
        ├── Gestor de Cabecera HTTP
        └── Aserción JSON: estado = APROBADO
```

Reglas de anidamiento que debes recordar:

- **Los muestreadores y los controladores van dentro de un Grupo de Hilos.** Sin Grupo de Hilos, JMeter no tiene quién envíe las peticiones.
- **Los listeners y los elementos de configuración pueden ir directamente bajo el Plan de Pruebas.** Entonces aplican a todos los grupos.
- **Los elementos que van dentro de un muestreador solo afectan a ese muestreador.** Un temporizador o un extractor bajo `Petición POST /api/seleccion` no afecta a `Petición POST /api/pago`.
- **Los elementos que van dentro de un controlador afectan a todos los muestreadores que cuelgan de él.** Así, un temporizador bajo un Controlador simple pausa a todos sus hijos.

### 4.3 Alcance (scope)

El alcance responde a la pregunta: ¿qué peticiones se ven afectadas por este elemento?

- Los elementos jerárquicos (listeners, configuración, preprocesadores, postprocesadores, aserciones y temporizadores) se aplican según dónde están en el árbol.
- Un elemento de configuración solo es visible dentro de su rama. Si una rama tiene el mismo tipo de elemento que su padre, la rama usa el suyo.
- Los gestores de cabecera, de cookies y de autorización no se combinan: solo se aplica uno por muestreador, y no puedes elegir cuál.
- Las variables definidas en el Plan de Pruebas se procesan al inicio, sin importar dónde estén.

### 4.4 Orden de ejecución

Para cada muestreador, JMeter ejecuta los elementos en este orden:

1. Elementos de configuración
2. Preprocesadores
3. Temporizadores
4. Muestreador (la petición)
5. Postprocesadores
6. Aserciones
7. Listeners

Consecuencias prácticas:

- El extractor JSON (postprocesador) corre **después** de la petición. Por eso `${num_reserva}` solo tiene valor en la petición siguiente, no en la misma.
- El temporizador corre **antes** de la petición. Pone la pausa, y luego la petición se envía.
- Las aserciones corren **después** de la petición. Si la aserción falla, la muestra queda marcada como fallida en el reporte.

### 4.5 Elementos que usarás en el taller

| Elemento | Para qué sirve | Parámetros clave |
|---|---|---|
| **Grupo de Hilos** | Simula usuarios | Número de hilos, periodo de subida, contador del bucle, duración (opcional) |
| **Temporizador Aleatorio Uniforme** | Pausa aleatoria entre peticiones, como un usuario real | Retardo máximo aleatorio y desplazamiento constante, en milisegundos |
| **Temporizador Sincronizado** | Hace que varios hilos se liberen al mismo tiempo | Número de usuarios a agrupar y tiempo de espera |
| **CSV Data Set Config** | Lee datos de un archivo y los asigna a variables | Nombre de archivo (`datos.csv`), nombres de variables, separador, qué hacer al terminar el archivo |
| **Extractor JSON** | Saca un valor de una respuesta JSON | Nombre de la variable y la ruta JSON |
| **Aserción JSON** | Verifica un valor en una respuesta JSON | Ruta JSON y valor esperado |
| **Gestor de Cabecera HTTP** | Envía cabeceras, como `Content-Type` | Lista de cabeceras |
| **Gestor de Cookies HTTP** | Mantiene las cookies entre peticiones de un mismo hilo | Ninguno importante para el taller |
| **Debug Sampler** | Muestra variables para depurar | Ninguno. Deshabilítalo antes de medir |
| **Reporte resumen** | Muestra estadísticas en tabla | Archivo de salida |

Los parámetros exactos cambian poco entre versiones, pero compruébalos en tu JMeter 5.6.3. La referencia oficial está en la sección 15.

---

## 5. Cómo se combinan los elementos: el flujo de compra

El flujo que simula el taller es el de una compra real. Cada paso depende del anterior:

1. **`GET /api/tarifas`** lee las tarifas. No necesita nada previo.
2. **`POST /api/seleccion`** crea una reserva. Necesita `${tarifa}` y `${cantidad}`, que vienen del CSV. Al responder, devuelve un número de reserva.
3. **Extractor JSON** saca ese número de reserva y lo guarda en `${num_reserva}`.
4. **`POST /api/pago`** paga la reserva. Usa `${num_reserva}`.
5. **Aserción JSON** comprueba que el estado sea `APROBADO`.

Este encadenamiento es el corazón del taller. Si el extractor no se ejecuta, `${num_reserva}` queda vacío y el pago falla. Recuerda el orden de ejecución de la sección 4.4.

---

## 6. Tipos de escenario

Un escenario se define con cuatro cosas: **cuántos usuarios**, **cómo entran**, **cuánto dura** y **qué hacen**. Cambiar uno de esos valores cambia el tipo de prueba.

### 6.1 Carga

Mide cómo responde la API con una cantidad de usuarios que se considera normal o esperada.

- Usuarios: el número esperado (por ejemplo, 200).
- Subida: lo suficientemente gradual para no confundir el efecto de la carga con el arranque.
- Duración: suficiente para que el sistema se estabilice (por ejemplo, 5 minutos).

### 6.2 Estrés

Busca el punto en el que el sistema deja de responder bien. Se sube la carga por etapas y se observa cuándo cambia el comportamiento.

- Usuarios: se escalonan, por ejemplo, 50, 100, 250 y 500.
- Cada escalón: suficiente tiempo para estabilizarse.
- Lo que observas: cuándo deja de crecer el throughput, cuándo sube mucho la Media, cuándo aparecen errores.

### 6.3 Concurrencia

Mide qué pasa cuando muchos usuarios hacen la misma operación **al mismo tiempo**.

- Usuarios: un grupo grande que se libera a la vez.
- Herramienta clave: el **Temporizador Sincronizado**, que espera a que se junte el grupo y luego lo libera.
- Lo que observas: si todas las respuestas son exitosas, cuánto tarda la última y si hay conflictos (por ejemplo, reservas que se pisan).

### 6.4 Duración

Mide qué pasa cuando la carga se mantiene durante mucho tiempo.

- Usuarios: un número fijo.
- Duración: larga (por ejemplo, 10 minutos o más).
- Lo que observas: si el tiempo de respuesta sube con el tiempo y si la memoria crece sin bajar.

### 6.5 Parámetros del Grupo de Hilos por tipo

| Parámetro | Carga | Estrés | Concurrencia | Duración |
|---|---|---|---|---|
| Número de hilos | Un valor esperado | Se sube por etapas | Un grupo grande | Un valor fijo |
| Periodo de subida | Gradual | Gradual por etapas | Corto o cero, o sincronizado | Gradual |
| Contador del bucle | 1 o más | 1 | 1 | Infinito o con duración |
| Duración | Suficiente para estabilizarse | Por escalón | Corta | Larga |
| Temporizador | Aleatorio uniforme | Aleatorio uniforme | Sincronizado | Aleatorio uniforme |

Los valores concretos los decides tú según la pregunta que respondes.

### 6.6 Escenario del despliegue (fijo para el ejercicio 1)

Este escenario es el único que se fija para el pipeline:

| Parámetro | Valor |
|---|---|
| Tipo de hilo | Grupo de Hilos estándar |
| Número de hilos | 200 usuarios |
| Periodo de subida | 300 segundos (los 200 usuarios entran en 5 minutos) |
| Contador del bucle | 1 (cada usuario recorre el flujo una vez) |
| Temporizador | Temporizador Aleatorio Uniforme, de 500 a 1500 ms |

---

## 7. Datos y ruta relativa (CSV)

- **Ruta relativa:** en el CSV Data Set Config, el *Nombre de Archivo* debe ser `datos.csv`, no una ruta de tu computador. JMeter busca el archivo en la carpeta desde la que se ejecuta.
- **Regla práctica:** el `.jmx` y el CSV deben estar en la misma carpeta, y debes ejecutar JMeter desde esa carpeta.
- **Variables:** en el plan usa `${tarifa}`, `${cantidad}` y `${num_reserva}`, nunca valores fijos.
- **Depurar:** el Debug Sampler muestra las variables en *Ver Árbol de Resultados → Datos de Respuesta*. Deshabilítalo antes de medir: cuenta como una muestra más y altera el total del reporte.
- **Ver Árbol de Resultados:** solo para depurar con pocos hilos. No lo uses en pruebas largas.

---

## 8. Ejecutar y generar el reporte

### 8.1 En modo no-GUI (para medir)

Las mediciones se hacen sin interfaz gráfica:

```bash
jmeter -n -t <tu-plan>.jmx -l resultados.jtl -e -o reporte
```

- `-n`: sin interfaz. Es el modo para mediciones.
- `-t`: el plan.
- `-l`: resultados crudos en formato `.jtl`.
- `-e -o`: genera el reporte HTML en la carpeta indicada.

Abre `reporte/index.html` en el navegador.

### 8.2 En la interfaz gráfica (para construir y depurar)

Usa la GUI para armar el escenario y revisar que funciona. No la uses para medir, porque consume recursos.

Para generar el reporte desde la GUI:

1. Abre el plan: `~/apache-jmeter-5.6.3/bin/jmeter`.
2. Agrega un listener que escriba a archivo, por ejemplo *Reporte resumen* o *Simple Data Writer*. En su campo de archivo de salida escribe una ruta con extensión `.jtl`, como `resultados.jtl`, y marca la opción de escribir en archivo.
3. Ejecuta el plan con el botón verde. Espera a que termine.
4. Ve al menú **Herramientas** y busca la opción para generar el informe HTML. Selecciona el `.jtl` y una carpeta de salida **vacía**, como `reporte`.
5. Abre `reporte/index.html`.

Si la carpeta de salida ya tiene archivos, JMeter no genera el informe. Usa una carpeta nueva. Los nombres de los menús pueden variar según la versión: confírmalos en la documentación oficial de tu versión.

---

## 9. Leer resultados

### 9.1 Throughput (Rendimiento)

- **Qué es:** peticiones completadas por segundo.
- **Cálculo:** muestras ÷ segundos de la prueba. Ejemplo: 120 peticiones en 60 segundos = 2 por segundo.
- **Cómo se lee:** si sube al aumentar usuarios, el sistema responde más. Si se queda igual mientras suben los usuarios, el sistema está saturado.
- **En el reporte:** columna *Rendimiento*.

### 9.2 Costo (Media)

- **Qué es:** el tiempo que tarda una petición en responder. No es dinero.
- **Dónde se mide:** columna *Media*, en milisegundos, para cada petición.
- **Cómo se compara:** la petición con mayor Media es la más costosa.
- **Diferencia con throughput:** el costo dice cuánto tarda una petición; el throughput dice cuántas se completan por segundo.

### 9.3 Columnas del reporte

- **Muestras:** total de peticiones.
- **Media:** tiempo promedio de respuesta, en milisegundos.
- **Máx:** el tiempo más alto.
- **% Error:** porcentaje de respuestas fallidas.
- **Rendimiento:** throughput, en peticiones por segundo.

### 9.4 Hardware y rendimiento

Son dos mediciones distintas que se leen juntas:

| Tipo | Qué mide | Con qué se mide | Ejemplos |
|---|---|---|---|
| **Hardware** | Cuánto consume el equipo durante la prueba | PerfMon con ServerAgent | CPU y memoria |
| **Rendimiento** | Qué tan bien responde el sistema a la carga | Reporte de JMeter | Throughput, tiempos, errores |

El hardware explica por qué el rendimiento cambió. No separes una lectura de la otra: si el rendimiento cambia y la CPU está al 100 %, el hardware es parte de la respuesta.

### 9.5 PerfMon: CPU y memoria

Requiere el plugin jpgc PerfMon y el ServerAgent corriendo en el puerto 4444 antes de iniciar la prueba.

| Métrica | Qué es | Cómo se lee |
|---|---|---|
| **CPU** | Porcentaje de uso del procesador | Si se mantiene cerca de 100 %, el equipo está saturado |
| **Memoria** | Memoria en uso | Si sube sin bajar durante toda la prueba, algo se está acumulando |

PerfMon mide el equipo completo: JMeter y la API juntos, en este taller.

---

## 10. Criterios de aceptación

En un proyecto real, las pruebas de rendimiento se evalúan contra criterios medibles. Estos son ejemplos del tipo de criterio:

- **Throughput:** el sistema debe procesar al menos 50 peticiones por segundo con 200 usuarios.
- **Usuarios en 30 minutos:** 200 usuarios activos durante 30 minutos, sin errores.
- **Concurrencia:** 50 usuarios que llegan en el mismo segundo, con todas sus respuestas en menos de 1 segundo.

Un criterio es **medible** cuando dice:

1. Qué métrica se mide (throughput, Media, Máx, % Error, CPU, memoria).
2. Qué valor de referencia se espera.
3. Con cuántos usuarios y durante cuánto tiempo.

En este taller **no son obligatorios**. Si los propones, deben cumplir esas tres condiciones.

---

## 11. Ejercicio de experimentación (individual)

Cada estudiante responde las 10 preguntas. Es individual, local y separado del pipeline.

### 11.1 Archivo y carpeta

- Usa un `.jmx` distinto del despliegue, en `pruebas/experimentacion/`.
- No modifiques `Ticketmania.jmx`.
- El pipeline no ejecuta esta carpeta.

### 11.2 Método

Cada pregunta empieza con "¿Qué pasaría si...?". Diseña un escenario para validarla, ejecútalo, observa el reporte y responde con tus propias palabras. Tu chat bot configurado como IA tutor te guía en cada etapa.

### 11.3 Las 10 preguntas

*Carga*
1. ¿Qué pasaría si subo de 20 a 500 usuarios? ¿Cambia el throughput, el tiempo de respuesta o ambos?
2. ¿Qué pasaría si el ramp-up pasa de 1 segundo a 60 segundos? ¿Cambia el pico inicial del reporte?
3. ¿Qué pasaría si quito los temporizadores? ¿Cuánto sube el throughput y qué significa eso para la prueba?

*Estrés*
4. ¿Qué pasaría si escalono de 50 a 100, 250 y 500 usuarios? ¿En qué punto deja de crecer el throughput?
5. ¿Qué pasaría si la prueba dura 10 minutos en lugar de 1? ¿El tiempo de respuesta se mantiene o sube con el tiempo?
6. ¿Qué pasaría si mido `/api/tarifas` (solo lectura) y `/api/seleccion` (crea reservas) con la misma carga? ¿Cuál cuesta más?

*Concurrencia*
7. ¿Qué pasaría si 500 usuarios crean reservas al mismo tiempo? ¿Todas las respuestas son exitosas?
8. ¿Qué pasaría si los usuarios disparan a la vez con el Temporizador Sincronizado, frente a cuando llegan distribuidos?
9. ¿Qué pasaría si el total cobrado no coincide con precio × cantidad bajo carga? ¿Cómo lo validarías con el CSV?

*Recursos*
10. ¿Qué pasaría si subo a 500 usuarios? ¿Cómo se comportan la memoria y la CPU durante la prueba? ¿Llegan a saturarse? ¿Cuánto cambia el tiempo de respuesta cuando eso pasa?

### 11.4 Entregable

Un documento de Word o una presentación de PowerPoint, con:

- Las 10 preguntas, respondidas en tus palabras.
- El escenario que diseñaste con tu chat bot configurado como IA tutor: hilos, subida, duración y temporizadores.
- Screenshots del escenario configurado y de los reportes que sustentan tus argumentos.
- Los resultados que observaste en el reporte y en PerfMon, si los usaste.
- Una limitación por pregunta: qué no pudiste medir o qué cambió el resultado.

---

## 12. Buenas prácticas

- **Cambia una sola variable por ejecución** (usuarios, duración, subida o endpoint). Si cambias varias, no sabrás qué causó el efecto.
- **Repite cada escenario** al menos dos veces y compara.
- **Registra el entorno:** equipo, RAM, versión de Java, hora de inicio y si la API corre en el mismo equipo.
- **No uses Ver Árbol de Resultados en pruebas largas.**
- **Deshabilita el Debug Sampler antes de medir.**
- **Mide en modo no-GUI.**

---

## 13. Límites

- **JMeter no ejecuta JavaScript.** Mide la respuesta HTTP, no lo que tarda el navegador en pintar la página.
- **Un solo equipo genera la carga.** Si ese equipo se queda sin CPU o memoria, los resultados reflejan al generador, no a la API. Vigila el consumo con PerfMon.
- **La API y JMeter comparten computador en este taller.** En una prueba real, la API debe correr en un equipo dedicado. Anótalo como limitación en tu entrega.
- **Los datos de la API están en memoria.** Reiniciarla borra las reservas.

---

## 14. Pendientes de clase

- Configuración detallada de los escenarios de estrés y concurrencia del taller. Se define en clase.
- Criterios de aceptación del taller. Se definen en clase, si el grupo los necesita.

---

## 15. Fuentes

- Apache JMeter, User's Manual: Elements of a Test Plan. https://jmeter.apache.org/usermanual/test_plan.html
- Apache JMeter, User's Manual: Building a Test Plan. https://jmeter.apache.org/usermanual/build-test-plan.html
- Apache JMeter, User's Manual: Component Reference. https://jmeter.apache.org/usermanual/component_reference.html
- Apache JMeter, Best Practices. https://jmeter.apache.org/usermanual/best-practices.html
