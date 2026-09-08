# Inventario de personalizaciones del fork N7Steve/sure

Este documento identifica la funcionalidad propia de este fork frente al repositorio principal de Sure. Su objetivo es servir como mapa de propiedad durante futuras actualizaciones de `upstream`, especialmente al resolver conflictos: qué comportamiento debemos preservar, dónde vive y qué pruebas o migraciones lo respaldan.

> Este inventario describe diferencias funcionales, no implica que debamos conservar ciegamente cada línea. Si `upstream` incorpora una solución equivalente, se debe comparar el comportamiento y retirar la duplicación de forma consciente.

## Foto de referencia

Inventario generado el **23 de agosto de 2026** y actualizado el **9 de septiembre de 2026** tras la integración de `upstream`, la consolidación de Agenda como producto principal y la mejora de las transiciones de navegación:

| Concepto | Valor |
| --- | --- |
| Fork | `origin` → `https://github.com/N7Steve/sure.git` |
| Repositorio principal | `upstream` → `https://github.com/we-promise/sure.git` |
| Rama inventariada | `main` |
| Referencia de `upstream/main` documentada tras la integración | `9ec28abacc52056b3c5544b7bc5549c6d175d701` |
| HEAD del fork con la integración y la corrección de `IncomeStatement` | `06f247d6b08a1a690fe3085c3a41ebcb4332e9b2` |
| Merge-base | `79c826c0e3391063834887936bbe44dc1d90d0cf` |
| Forma de integración | Contenido de `upstream` integrado mediante commits squash; el SHA de `upstream/main` no es ancestro de `HEAD` |
| Cambios actuales sin commit | Consultar `git status --short`; el árbol incluye la frontera Agenda/Bills y otros ajustes del fork todavía no consolidados |

El alcance histórico inicial de este documento era `upstream/main...a01ed5290`. Después de la integración squash, el triple-dot contra `upstream/main` ya no representa únicamente las personalizaciones del fork: al no compartir el nuevo commit upstream como ancestro, Git muestra también gran parte del código oficial como diferencia. Para futuras auditorías se debe conservar explícitamente el SHA upstream integrado y comparar contra él por contenido o usar una rama temporal con historia real antes de resolver el siguiente merge.

## Resumen de propiedad

| Área | Propiedad | Debe preservarse al actualizar upstream |
| --- | --- | --- |
| Pagos recurrentes / programados | Propia | Modelos, generación, confirmación/rechazo, transferencias recurrentes e integración en transacciones |
| Bills / recurrencias detectadas | Upstream, oculto | Conservar la implementación como referencia reutilizable, pero sin superficies de acceso visibles; Pagos programados es el único producto recurrente expuesto |
| Informes personalizados | Propia | Resumen, desglose, gastos compartidos, exportación y secciones reordenables |
| Exclusión y archivo de cuentas | Propia | Las tres semánticas distintas: excluida, archivada y excluida sólo de informes |
| Roboadvisor e inversiones | Propia | Rendimiento, flujos, liquidez neta estimada y tratamiento fiscal |
| Categorías y transacciones | Propia | Creación/edición de categorías, selectores, búsqueda, formulario y detalle enriquecidos |
| Transferencias y divisiones | Propia o muy modificada | Clasificación con cuentas excluidas, conversión y splitting |
| Exportaciones de familia | Propia | Copia completa y CSV personalizado de transacciones |
| UI/UX | Propia o adaptada | Vistas compactas, cuentas agrupadas, componentes interactivos y mejoras responsive |
| Períodos mensuales del dashboard | Propia | Money In / Out y gasto acumulado deben respetar conjuntamente `family.month_start_day` |
| Sincronización y proveedores | Soporte del fork | Cambios que mantienen la coherencia de cuentas y sincronizaciones con las funciones anteriores |
| Gestión familiar y usuarios | Propia, todavía sin commit | Claridad de roles/alcance y borrado seguro de la última persona de una familia |
| Workflows, scripts y documentos auxiliares | Revisar caso a caso | Están en el diff del fork, pero no todos son funcionalidad de producto |

## 1. Gestión familiar y de usuarios

Este bloque se incorporó después del HEAD usado para el inventario original y ya forma parte de la línea actual del fork.

### Comportamiento propio

- La administración global de usuarios explica que muestra usuarios de toda la instancia, no sólo de la familia activa.
- Cada familia muestra número de miembros, cuentas y transacciones, estado de demo/suscripción, familia actual y el rol del usuario actual.
- Las familias demo se reconocen por la clave de monitorización demo, sin depender del nombre visible.
- Se añade acceso directo a la gestión de la familia actual y contexto sobre qué acciones pertenecen a administración de instancia o de familia.
- El formulario de invitación explica los roles, selecciona `member` por defecto y aclara que `super_admin` no se concede desde una invitación familiar.
- El perfil explica la política de compartir y enlaza a la administración adecuada.
- Al eliminar al último usuario se advierte que también desaparecerá la familia y se muestran las cuentas/transacciones afectadas.
- El borrado del último usuario exige escribir el nombre exacto de la familia.
- El borrado permanente de una familia demo elimina de forma segura la clave demo antes de destruir el resto de claves, evitando la validación que impedía la operación.
- Los fallos de borrado se registran como diagnóstico de soporte mediante `DebugLogEntry`.

### Archivos

- `app/controllers/admin/users_controller.rb`
- `app/models/user.rb`
- `app/views/admin/users/deletion.html.erb`
- `app/views/admin/users/index.html.erb`
- `app/views/invitations/new.html.erb`
- `app/views/settings/profiles/show.html.erb`
- `config/locales/views/admin/users/{en,es}.yml`
- `config/locales/views/invitations/{en,es}.yml`
- `config/locales/views/settings/{en,es}.yml`
- `test/controllers/admin/users_controller_test.rb`
- `test/controllers/invitations_controller_test.rb`
- `test/controllers/settings/profiles_controller_test.rb`

## 2. Pagos recurrentes / programados

Es el bloque funcional propio más grande. No debe reducirse a una simple etiqueta de “transacciones recurrentes” durante un merge.

### Comportamiento propio

- Definición de pagos programados por familia, cuenta, categoría, comercio, importe, moneda, frecuencia, día, fechas de inicio/fin y tipo de pago.
- Tipos de pago de gasto, ingreso y transferencia; las transferencias pueden tener cuenta de destino.
- Estado activo/inactivo, próxima ejecución, recuento de ocurrencias y opción de confirmación automática.
- Generación en segundo plano de ocurrencias pendientes y ejecución manual (`run_now`).
- Confirmar, rechazar, restaurar, omitir, retraer o cambiar la fecha de una ocurrencia.
- Creación de entradas reales al confirmar y enlace entre pago programado, ocurrencia, entrada y entrada de transferencia.
- Agenda independiente para pendientes y próximas ocurrencias, con redirección desde la antigua pestaña de transacciones.
- Bloqueo contextual y enlace al pago de origen desde el detalle de una transacción generada.
- Tarea Rake, programación Sidekiq y documentación operativa.
- Reparación de importes de salida corruptos de transferencias recurrentes mediante migración irreversible.

### Núcleo y puntos de integración

- Modelos: `app/models/scheduled_payment.rb`, `scheduled_payment_entry.rb`, `scheduled_payment_occurrence.rb`.
- Controlador y job: `app/controllers/scheduled_payments_controller.rb`, `app/jobs/generate_scheduled_payments_job.rb`.
- UI: `app/views/scheduled_payments/`, `app/helpers/scheduled_payments_helper.rb` y `scheduled_payment_form_controller.js`. La consulta de resumen/calendario vive en `app/models/scheduled_payment/agenda.rb`.
- Integración: `app/models/account.rb`, `app/models/entry.rb`, `app/models/family.rb`, `app/models/transaction.rb`, `app/controllers/transactions_controller.rb`, `config/routes.rb`, `config/schedule.yml`, `config/initializers/sidekiq.rb`.
- Operación: `lib/tasks/scheduled_payments.rake`, `informe_scheduled_payments.md`.
- Cobertura: pruebas de modelo, controlador y job, más fixtures `scheduled_payment*`.

### Refuerzo de robustez de septiembre de 2026

- La generación y las acciones sobre ocurrencias se serializan por pago programado. La creación de movimientos y el avance de fecha deben ser atómicos; los reintentos no pueden duplicar movimientos ni dejar el job en un bucle.
- Una ocurrencia ya confirmada no puede pasar a omitida/rechazada mediante una solicitud obsoleta. La retracción conserva su comportamiento propio: elimina el movimiento y deja la ocurrencia omitida; restaurar una fecha pasada confirma inmediatamente, y restaurar una futura recupera su próxima ejecución.
- El enlace de históricos conserva las tolerancias de importe y fecha, pero exige transacciones del signo y tipo correctos, comprueba los dos extremos de transferencias y respeta omisiones/rechazos y huecos pendientes.
- Lectura y escritura se distinguen según los permisos de las cuentas. Las transferencias requieren acceso a ambos extremos; editar/retraer también comprueba las cuentas de los movimientos históricos. La ejecución manual desde la UI se limita a la familia y a los pagos que el usuario puede gestionar; el job periódico sigue siendo global.
- Confirmar/retraer solicita la actualización de las cuentas después del commit. Las transferencias entre monedas usan el tipo de cambio de la fecha efectiva y revierten íntegramente si falta; sus etiquetas se conservan en ambos extremos.
- Las ocurrencias persistidas de programaciones completadas siguen apareciendo en Agenda, incluidas las pendientes. Las proyecciones de pagos antiguos saltan al período solicitado sin agotar el límite al recorrer su antigüedad.
- Borrar una cuenta libera antes las programaciones de origen y destino; borrar categoría/comercio opcionales conserva la programación, y reemplazar categoría actualiza su referencia.
- Las tareas Rake de generación y reversión de futuros usan las mismas protecciones del modelo.

Cobertura añadida en `test/models/scheduled_payment_robustness_test.rb` y ampliada en las pruebas de modelo, controlador y job existentes. Esta revisión se valida **sólo estáticamente por petición del usuario**: las pruebas quedan escritas, pendientes de ejecución en un entorno Rails compatible. No se han añadido migraciones ni modificado datos de la instalación.

### Agenda: sección propia de pagos programados

- **Agenda** es el nombre corto de producto. Se accede desde la navegación principal de escritorio y móvil, en `/scheduled_payments`, con el layout de aplicación. El encabezado y el breadcrumb muestran únicamente `Agenda`; `scheduled_payments` se conserva como nombre técnico de rutas y subsistema para reducir conflictos con upstream. Sustituye la pestaña de Transacciones y la entrada de Ajustes.
- **Resumen** reúne en una tarjeta compacta las programaciones activas (y total), los gastos pendientes de pagar en el mes seleccionado y el número de movimientos pendientes. Las tablas mensuales separan, en este orden, gastos, ingresos y transferencias, y conservan fechas, estados y acciones de confirmar, omitir, restaurar, deshacer y editar.
- **Por pagar este mes** sólo suma gastos abiertos, tanto proyectados como pendientes persistidos. Excluye confirmados, omitidos, ingresos y transferencias. Cada moneda se muestra por separado; la consulta no obtiene tipos de cambio. Los importes confirmados muestran el movimiento real, incluyendo ajustes al confirmar.
- **Una sola vez** permite preparar un movimiento futuro puntual. Proyecta una única fecha y la programación queda completada después de generarla, confirmarla u omitirla; restaurar una ocurrencia futura vuelve a activarla.
- Un importe puede marcarse como **estimado**. Agenda lo identifica con `≈` en resumen, calendario y programaciones; el diálogo de confirmación conserva la edición del importe para sustituirlo por el valor real, que deja de mostrarse como estimación una vez confirmado.
- **Planificación** normaliza todos los gastos recurrentes activos a coste mensual y anual, sin incluir movimientos puntuales, ingresos ni transferencias. Los totales mantienen cada moneda separada y ofrecen un desglose por la categoría financiera existente; no se crea una taxonomía paralela para Agenda.
- **Previsiones** proyecta por separado el saldo de cada cuenta de efectivo a 1, 3, 6, 12 o 36 meses. Los movimientos futuros de Agenda son la fuente de verdad; el flujo variable restante se obtiene de hasta 12 meses completos, con ponderación por recencia y reducción de valores atípicos. Se excluyen transferencias internas, pendientes, movimientos puntuales, padres de divisiones y transacciones ya explicadas por Agenda para evitar dobles conteos. La interfaz muestra escenarios pesimista, normal y optimista, y amplía un 15 % la incertidumbre de importes marcados como estimados.
- La **provisión mensual recomendada** divide entre tres los gastos trimestrales y entre doce los anuales. Se muestra de forma secundaria en cada programación aplicable, no como métrica del Resumen; es una referencia informativa y no crea saldos virtuales, presupuestos, transferencias ni movimientos contables.
- **Calendario** adapta la cuadrícula mensual de Bills al dominio `ScheduledPayment*`, con semanas de lunes a domingo y listado por días en móvil. Cada movimiento se reduce a icono de comercio e importe, con el nombre completo al pasar el puntero. Permite abrir la confirmación de movimientos abiertos; los demás enlazan a su fila en el resumen. Los días de meses adyacentes no inflan el resumen mensual.
- Las tablas de resumen y programaciones reutilizan la identidad visual del comercio, con inicial como alternativa cuando no hay logotipo. Programaciones mantiene columnas estables y centra el estado independientemente de la longitud del importe.
- **Nuevo pago** y **Editar programación** se abren en una modal sobre Agenda (también desde el detalle de movimientos y transferencias) y conservan la vista y el mes de Agenda al guardar. Las respuestas de Turbo Frame se renderizan sin el layout completo para evitar duplicar el frame `modal` vacío.
- **Programaciones** conserva la gestión de definiciones, pausa/reanudación, eliminación y ejecución manual. No se incorpora Income Plan, detección automática ni modelos de Bills.
- Consultar Agenda no genera ocurrencias ni movimientos. Se mantienen las reglas originales de recurrencia y confirmación, el aislamiento por familia y los permisos de origen, destino e históricos. Los controles de escritura sólo aparecen cuando el usuario puede gestionar la programación.
- Las acciones y formularios conservan mes/vista mediante parámetros permitidos. Los marcadores antiguos `transactions?tab=scheduled&scheduled_month=...` redirigen al mes correspondiente de Agenda.
- Cobertura específica en `test/models/scheduled_payment/agenda_test.rb`, en las pruebas del controlador y en `test/controllers/agenda_primary_frontend_test.rb`. El diff y el JavaScript se han validado localmente; la ejecución de Ruby/Rails queda pendiente porque el runtime Ruby no está disponible actualmente en el entorno.

### Convivencia con Bills incorporado desde upstream

La integración de septiembre de 2026 añadió el subsistema upstream **Bills**, basado principalmente en `RecurringTransaction` y `RecurringOccurrence`. El código de ambos sistemas puede convivir, pero en este fork sólo Pagos programados se presenta como funcionalidad de producto:

- **Pagos programados** es la función primaria del fork: el usuario define pagos futuros explícitos, se generan ocurrencias pendientes y puede confirmarlas, rechazarlas, omitirlas o ejecutarlas automáticamente.
- **Bills** es una implementación upstream que se conserva oculta: detecta patrones recurrentes en movimientos existentes, permite confirmar series, proyectar vencimientos, registrar pagos y presentar planificación por nóminas.
- Bills no debe tener ninguna superficie de acceso visible en el fork, incluso para usuarios con `Preview Features`: sin entrada en la navegación global, sin pestaña **Upcoming** en Transacciones, sin entrada de **Transacciones recurrentes** en Ajustes y sin enlaces, asignaciones o acciones heredadas de Bills desde transacciones, transferencias, presupuestos o insights.
- Sus modelos, controladores, rutas, jobs, detectores, API, feed de calendario y pruebas se mantienen internamente para facilitar futuras actualizaciones upstream y servir como fuente de funcionalidades. No forman parte del frontend soportado del fork.
- Las rutas HTML directas de Bills y Transacciones recurrentes se conservan para reducir el diff con upstream, pero redirigen a Agenda cuando el frontend de Bills está desactivado. Las acciones directas `mark_as_recurring` de transacciones y transferencias están protegidas de la misma forma; ocultar solamente sus botones no es suficiente.
- Los insights que dependen de Bills (`cash_flow_warning` y `subscription_audit`) pueden seguir generándose y almacenándose como parte del subsistema, pero se excluyen del dashboard, listado, contador, actualizaciones Turbo y notificaciones del producto mientras Bills permanezca oculto.
- No migrar, fusionar ni eliminar modelos de `ScheduledPayment*` en favor de `RecurringTransaction*` sin una decisión funcional y una migración de datos explícitas.
- No sincronizar automáticamente una misma regla entre `ScheduledPayment*` y `RecurringTransaction*`: son dominios independientes y una doble escritura produciría proyecciones y estados contradictorios.
- Las funciones útiles de Bills podrán trasladarse selectivamente a Pagos programados en el futuro. Cada traslado debe adaptarse al dominio `ScheduledPayment*`, conservar su flujo de ocurrencias/confirmación y añadir pruebas propias; no se debe hacer visible Bills como atajo para ofrecer esa función.
- Cuando upstream cambie Bills, revisar especialmente `transactions_controller`, `transaction.rb`, presupuestos, categorías y las vistas de transacciones, porque son los puntos donde ambos subsistemas se solapan.

#### Contrato técnico de la frontera Agenda/Bills

- `config/initializers/fork_features.rb` define `Rails.configuration.x.bills_frontend_enabled`. Vale `false` en desarrollo y producción, y `true` en test para conservar ejecutable la cobertura upstream de Bills sin reescribirla ni borrarla.
- `app/controllers/concerns/bills_frontend_guardable.rb` concentra la protección de rutas. `RecurringFeatureGuardable` la aplica a las pantallas HTML upstream y los controladores de transacciones y transferencias la aplican a sus acciones Bills aisladas.
- `bills_frontend_enabled?`, en `ApplicationHelper`, es la única condición que deben usar las vistas para mostrar una superficie Bills. No repartir comprobaciones de entorno o del fork por las plantillas.
- `Insight.for_product_frontend` es la frontera de lectura para cualquier feed, badge o emisión de insights dirigida al usuario. Añadir un nuevo insight respaldado por Bills exige incluirlo en `Insight::BILLS_BACKED_TYPES`.
- `test/controllers/agenda_primary_frontend_test.rb` fuerza el valor de producción (`false`) y cubre redirecciones, ausencia de accesos y bloqueo de mutaciones. El resto de la suite conserva el valor `true` para verificar el código upstream en aislamiento.
- Esta configuración es una decisión de distribución del fork, no una preferencia de usuario ni una preview feature. No exponerla en Ajustes sin revisar antes esta política de producto.

Archivos upstream que forman esta frontera: `app/controllers/bills_controller.rb`, `app/views/bills/`, `app/models/recurring_transaction.rb`, `app/models/recurring_occurrence.rb`, `app/views/recurring_transactions/`, rutas de Bills y sus pruebas. La capa de ocultación del fork incluye además `config/initializers/fork_features.rb`, `app/controllers/concerns/bills_frontend_guardable.rb`, `app/controllers/concerns/recurring_feature_guardable.rb`, los puntos de integración en transacciones, transferencias, presupuestos, ajustes e insights, y `test/controllers/agenda_primary_frontend_test.rb`. No reintroducir `bills_nav_item` ni accesos equivalentes automáticamente durante un merge.

## 3. Visibilidad, exclusión y archivo de cuentas

El fork distingue conceptos que no son intercambiables:

- **Excluida (`excluded`)**: queda fuera de la experiencia financiera habitual y afecta a la clasificación de transferencias y filtros.
- **Archivada (`archived`)**: se oculta de navegación/listados sin borrar sus datos históricos.
- **Excluida de informes (`exclude_from_reports`)**: conserva la cuenta disponible, pero no entra en los cálculos de informes.

### Comportamiento propio

- Acciones para activar/desactivar, excluir/incluir y archivar/restaurar cuentas.
- Scopes diferenciados (`visible`, `data_visible`, `sidebar_visible`, `sync_enabled`, `excluded`, `archived`, etc.).
- Invalidación de cachés familiares cuando cambia la visibilidad.
- Filtro de transacciones capaz de incluir cuentas excluidas de forma explícita.
- Históricos, balance, net worth, sparklines y páginas de cuenta adaptados a estas reglas.
- Transferencias hacia/desde cuentas excluidas reclasificadas para que los informes no las interpreten como gasto/ingreso ordinario.
- Las cuentas excluidas pueden seguir sincronizándose; ocultar datos no equivale a desactivar el proveedor.

### Archivos clave

- `app/models/account.rb`
- `app/controllers/accounts_controller.rb`
- `app/controllers/concerns/accountable_resource.rb`
- `app/models/balance_sheet/{account_group,account_totals,classification_group,historical_account_scope,net_worth_series_builder,sync_status_monitor}.rb`
- `app/controllers/accountable_sparklines_controller.rb`
- `app/views/accounts/` y `app/views/pages/dashboard/_balance_sheet.html.erb`
- `app/views/transactions/_include_excluded_toggle.html.erb`
- `app/views/transactions/searches/filters/_account_filter.html.erb`
- Pruebas de cuenta, búsquedas, balance y transferencias afectadas.

## 4. Informes, gastos compartidos e indicadores personalizados

### Comportamiento propio

- Dashboard de informes con secciones configurables, colapsables y reordenables.
- Resumen financiero y desglose de transacciones/categorías con enlaces a las transacciones subyacentes.
- En los bloques de gasto e ingreso, cada subcategoría es un desplegable que muestra dentro sus 10 movimientos de mayor importe, ordenados de mayor a menor. Si existen más de 10, los restantes se omiten de la vista, pero siguen formando parte del recuento, el total y el porcentaje de la subcategoría.
- Cada movimiento del desplegable muestra nombre, merchant, cuenta e importe, utiliza el logo del merchant cuando está disponible y permite abrir su detalle en el drawer. La fecha se omite por no ser relevante para este análisis. La selección de los 10 primeros se realiza después de convertir los importes a la moneda de la familia, por lo que el orden es coherente entre cuentas con distintas monedas.
- Exportación CSV del desglose y ayuda para llevarlo a Google Sheets.
- `IncomeStatement` y totales adaptados a las reglas del fork, incluidas cuentas excluidas, movimientos internos e inversiones.
- `IncomeStatement::Totals::TotalsRow` conserva obligatoriamente los campos `is_transfer_to_excluded` e `is_transfer_from_excluded`. Deben estar presentes de extremo a extremo en el constructor, `Data.define`, todos los `SELECT`/`UNION` y los `GROUP BY`. La refactorización upstream mediante `IncomeStatement::ScopedTransactionsQuery` se conserva, pero no puede eliminar estas extensiones del fork.
- Los resultados de `IncomeStatement::Totals` se serializan en la caché compartida. Si cambia el número o significado de los miembros de `TotalsRow`, se debe incrementar la versión de la clave `income_statement/totals_query` (actualmente `v5`). De lo contrario, un despliegue puede fallar en producción con `TypeError: struct IncomeStatement::Totals::TotalsRow not compatible (struct size differs)`. No usar `Rails.cache.clear` ni `FLUSHDB` como solución, porque Redis también sirve a Sidekiq.
- `SharedExpensesCalculator` para distribuir gastos compartidos y calcular métricas personalizadas de gasto e ingreso.
- Búsqueda de transacciones y series de patrimonio usadas como soporte de los informes.
- Caché/invalidez ajustadas para que los cambios de cuenta se reflejen inmediatamente.

### Archivos clave

- `app/controllers/reports_controller.rb`
- `app/services/shared_expenses_calculator.rb`
- `app/models/income_statement.rb`
- `app/models/income_statement/totals.rb`
- `app/models/transaction/search.rb`
- `app/models/balance_sheet/net_worth_series_builder.rb`
- `app/views/reports/index.html.erb`
- `app/views/reports/_summary_dashboard.html.erb`
- `app/views/reports/_breakdown_table.html.erb`
- `app/views/reports/_category_row.html.erb`
- `app/views/reports/_subcategory_row.html.erb`
- `app/views/reports/_transactions_breakdown.html.erb`
- Locales de informes en inglés y español y pruebas de controladores/modelos relacionadas, incluida la regresión que verifica el orden descendente y el límite de 10 movimientos por subcategoría en `test/controllers/reports_controller_test.rb`.

## 5. Roboadvisor e inversiones en informes

### Comportamiento propio

- `InvestmentStatement` extendido para rendimiento de cartera, posiciones, flujos y métricas de roboadvisor.
- Sección de rendimiento roboadvisor dentro del dashboard de informes.
- Cálculo de liquidez neta estimada con tramos fiscales progresivos mediante `PortfoliosHelper`.
- Tratamiento regional/fiscal de inversiones y etiquetas de actividad de inversión.
- Flujos de inversión y aportaciones diferenciados de ingresos/gastos ordinarios.
- Formulario de inversiones con subtipo y pestaña de visión general de la cuenta.
- Soporte para convertir transacciones en operaciones de inversión y conservar su etiqueta de actividad.

### Archivos clave

- `app/models/investment_statement.rb`
- `app/models/investment_flow_statement.rb`
- `app/models/investment.rb`
- `app/helpers/portfolios_helper.rb`
- `app/views/reports/_roboadvisor_performance.html.erb`
- `app/views/reports/_investment_flows.html.erb`
- `app/views/investments/_form.html.erb`
- `app/views/investments/tabs/_overview.html.erb`
- Cambios asociados en `reports_controller`, `transactions_controller`, `income_statement` y locales.

## 6. Categorías y transacciones

### Categorías

- Posibilidad de crear y editar categorías desde la aplicación.
- Categorías jerárquicas padre/hija, nombres de presentación, iconos y colores.
- Selector visual con búsqueda de iconos/color y herencia/control para subcategorías.
- Selectores de categoría mejorados en formulario, detalle, actualización rápida, división y operaciones masivas.
- Registro de uso de categoría y soporte para sugerir/crear reglas al categorizar.

Archivos principales: `categories_controller.rb`, `category/dropdowns_controller.rb`, `category.rb`, vistas `categories/` y `category/`, `color_icon_picker_controller.js`, `DS/category_select/` y pruebas relacionadas.

### Transacciones

- Índice y controlador ampliados para CRUD, filtros, preferencias de vista y conversión a operaciones de inversión.
- Vista compacta persistente y alternador compacta/detallada. El estado pertenece al usuario y se guarda como el booleano `preferences["transactions_compact_view"]`; `User#transactions_compact_view?` lo lee y `User#update_transactions_preferences` debe conservar las demás claves del JSON al actualizarlo. El alternador usa `PATCH /transactions/toggle_compact_view`. Estos puntos forman parte de la feature y no deben eliminarse como preferencias de secciones obsoletas durante una integración con upstream.
- Creación manual y formulario reorganizado con descripción, cuenta, categoría, comercio, etiquetas, notas, naturaleza y datos de inversión. En la modal de nueva transacción, comercio y etiquetas permanecen siempre visibles inmediatamente debajo de categoría; no deben moverse al disclosure de detalles.
- En creación y edición, **importe y fecha comparten una única fila de dos columnas** para reducir la altura del formulario. En el detalle editable, naturaleza permanece en su propia fila; las transferencias conservan la fecha en una fila independiente porque no muestran el campo de importe ordinario.
- Autocompletado de descripciones por cuenta mediante `Transactions::DescriptionsController` y Stimulus.
- Búsqueda por comercio y filtros por cuentas, categorías, comercios, tipos, etiquetas, estado, fechas e importe.
- Los filtros se conservan exclusivamente en la URL: el historial del navegador puede restaurarlos, pero una nueva entrada a Transacciones comienza sin filtros. Los chips incluyen una acción «Borrar todo» y el tamaño inicial de página es de 20 movimientos.
- Detalle enriquecido con edición automática, indicadores, posibles duplicados, protección, contexto de transferencias/pagos programados y permisos de anotación.
- Actualización rápida de categoría, etiquetas y actividad de inversión.
- Borrado masivo y vistas Turbo actualizadas.

Archivos principales: `transactions_controller.rb`, `transactions/bulk_deletions_controller.rb`, `transactions/categorizes_controller.rb`, `transactions/descriptions_controller.rb`, `user.rb`, `transaction.rb`, `transaction/search.rb`, `entry_search.rb`, `config/routes.rb`, vistas `transactions/` —en especial `_compact_view_toggle.html.erb` y `_list.html.erb`—, helpers, controladores Stimulus relacionados y `test/controllers/transactions_controller_test.rb`.

## 7. Transferencias, matching y división de transacciones

- Gestión y presentación de transferencias desde formularios y detalle.
- El formulario de transferencias oculta por completo la sección de comisiones bancarias; el soporte de comisiones existente en el modelo, la API y los datos históricos se conserva.
- Creación, validación y reclasificación de ambos lados de una transferencia.
- Matching corregido para cuentas excluidas.
- Clases especiales para transferencias a/desde cuentas excluidas y aportaciones a inversiones.
- Conversión de transacciones a trades y restauración/retracción donde aplica.
- División (`splitting`) de transacciones con selector de categoría, bloqueo de hijos/padres y vistas coherentes.
- Migración correctiva bidireccional para transferencias ya existentes.

Puntos principales: `transfer.rb`, `transfer/creator.rb`, `transaction/transferable.rb`, `transfers_controller.rb`, `transfer_matches_controller.rb`, `splits_controller.rb`, vistas `transfers/` y `splits/`, y pruebas de transferencia/división.

## 8. Exportaciones y copias de la familia

Funcionalidad propia incorporada en agosto de 2026:

- Dos tipos de exportación: copia completa y CSV personalizado de transacciones.
- Rango de fechas, filtros JSON, usuario solicitante, tipo y número de registros.
- Generación asíncrona y descarga desde la UI.
- Endpoint API adaptado a las nuevas opciones.
- `Family::TransactionCsvExporter` dedicado y probado.

Archivos principales: `family_exports_controller.rb`, `api/v1/family_exports_controller.rb`, `family_export.rb`, `family/transaction_csv_exporter.rb`, `family_data_export_job.rb`, vistas/locales de `family_exports` y sus pruebas.

## 9. UI y experiencia de uso

Estos cambios son propios aunque muchos estén entrelazados con las funciones anteriores:

- Sidebar de cuentas con pestañas, grupos de activos/pasivos y disclosures expandibles.
- `UI::AccountPage` y feed de actividad modular para las páginas de cuenta.
- Tabla compacta reutilizable de entradas y modo compacto de transacciones.
- Selectores buscables, multiselect con chips, selector de tags, tooltips, menús, diálogos y popovers posicionados con Floating UI.
- Controlador de select accesible con teclado.
- Mejoras responsive de sidebar, navegación, menú de usuario y formularios.
- Las navegaciones Turbo entre páginas aplican un fundido nativo breve únicamente al contenido principal, sin desplazar, escalar ni desvanecer la navegación o las barras laterales, y lo desactivan cuando el sistema solicita movimiento reducido. Las barras laterales limitan su transición a anchura, opacidad y borde para evitar el antiguo efecto de rebote. Los grupos de cuentas (efectivo, inversiones, etc.) conservan por usuario y dispositivo su estado abierto/cerrado entre páginas y animan suavemente altura, contenido y chevrón al desplegarse.
- Las modales `DS::Dialog` funden coordinadamente panel y overlay al abrir y cerrar, incluido el cierre con Escape. Los desplegables de subcategorías del desglose de Informes y las cards plegables de Inicio e Informes animan altura, contenido y chevrón con la misma duración breve; todos estos movimientos respetan la preferencia de movimiento reducido.
- Toast para deshacer el descarte de insights.
- Ajustes visuales en presupuestos, operaciones, cuentas, informes y dashboard.
- El widget **Money In / Out** respeta el `month_start_day` configurado por la familia: cada barra y el resumen usan periodos mensuales personalizados (por ejemplo, del día 25 al 24 del mes siguiente), el periodo activo se limita a la fecha actual y los enlaces de desglose conservan exactamente ese rango. Los periodos que empiezan entre los días 1 y 15 conservan el nombre de ese mes; los que empiezan después del 15 se muestran como el mes siguiente (25 de agosto–24 de septiembre se presenta como “septiembre”). El selector mensual utiliza la misma regla para mantener coherentes la etiqueta, la barra resaltada y los totales.
- El widget upstream de **gasto acumulado / Spending Trend** sigue exactamente la misma semántica de mes configurado que Money In / Out. Su curva actual, curva comparativa, selector, etiquetas del eje y totales se construyen con períodos personalizados; por ejemplo, septiembre comienza el 25 de agosto cuando `month_start_day = 25`. El período activo se limita a hoy, mientras que la comparación usa el período personalizado anterior completo.
- Traducciones propias, principalmente en `en` y `es`; el diff contiene además arreglos puntuales en otros idiomas.

Componentes/controladores especialmente sensibles a conflictos: `app/components/DS/`, `app/components/UI/`, `app/javascript/controllers/{select,multi_select,tag_select,tooltip,auto_submit_form,autocomplete,color_icon_picker,persisted_disclosure,dashboard_section,reports_section}.js`, `app/javascript/utils/{collapsible_animation,dialog}.js`, `app/views/accounts/_accountable_group.html.erb`, `app/views/layouts/shared/_head.html.erb`, `app/views/layouts/application.html.erb`, `app/assets/tailwind/application.css`, layout principal y vistas de cuentas/transacciones.

Los ajustes de **Money In / Out** y **Spending Trend** comparten `dashboard_display_month` y `dashboard_period_start_for` en `app/controllers/pages_controller.rb`. Sus vistas son `app/views/pages/dashboard/_money_flow.html.erb` y `_spending_trend.html.erb`; la regresión está cubierta en `test/controllers/pages_controller_test.rb`, incluido el caso 25 de agosto–24 de septiembre.

## 10. Funcionalidad upstream incorporada en septiembre de 2026

Estas áreas proceden principalmente del repositorio oficial y se aceptaron en el fork. No son personalizaciones que deban divergir sin motivo, pero deben revisarse en futuros merges por sus puntos de contacto con las funciones propias:

- Bills, recurrencias detectadas y planificación por nóminas, conservadas internamente pero ocultas según la decisión descrita anteriormente.
- Integraciones de Trade Republic y Wise con SCA, además de mejoras de refresco de Plaid.
- Ciclo de vida ampliado de Goals y cambios de presupuestos como rollover y movimientos entre categorías.
- Idempotencia al crear transacciones, divisiones durante importación QIF y mejoras de jerarquía de categorías.
- Diagnósticos de salud de IA/worker, administración de usuarios y familias, localización `pt-PT` y ajustes de hosting.

En conflictos futuros, conservar preferentemente la evolución upstream dentro de estas áreas, salvo donde choque con una regla explícita de este inventario: Pagos programados como sistema primario, semántica de cuentas excluidas/archivadas, períodos mensuales personalizados, formularios compactos y permisos/tenancy del fork.

## 11. Sincronización, proveedores y soporte técnico

Este bloque aparece en el diff del fork y soporta las personalizaciones, aunque parte llegó en commits squash y debe revisarse con más cuidado al compararlo con nuevas versiones de upstream.

- Concern `Syncable` y pruebas de interfaz para normalizar el ciclo de sincronización.
- Ajustes en importadores/syncers de Coinbase, CoinStats, Enable Banking, Lunchflow y Mercury.
- Ajustes del proveedor Indexa Capital ligados a inversiones/roboadvisor.
- Cambios en `Family`, transfer matching y cuentas para mantener caché y sincronización coherentes.
- Configuración Sidekiq/schedule para pagos programados.
- Locales de proveedores y pequeños ajustes de presentación/configuración.

Rutas afectadas: `app/models/concerns/syncable.rb`, modelos/importers/syncers de los proveedores anteriores, `app/models/indexa_capital_item.rb`, `app/models/family.rb`, `config/initializers/sidekiq.rb` y `config/schedule.yml`.

## 12. Otros cambios propios o auxiliares

- Eliminación de presupuestos desde la UI/controlador.
- Ajustes menores en insights, usuario, sesiones, assistant functions, tags y budgets.
- Cambios en `Gemfile` para soporte de UI y documentación añadida al `README.md`.
- Workflows propios: `.github/workflows/gittensor-impact.yml` y cambios en `pipelock.yml`.
- Documentación/operación: `rollback-instructions.md` e `informe_scheduled_payments.md`.
- Scripts de diagnóstico: `script/debug_subtypes.rb` y `script.rb`.
- `conflicts.txt` es un artefacto binario presente en el fork: **revisar antes de conservar o resolver en un merge**; no asumir que es funcionalidad necesaria.

## Migraciones propias

El orden y el efecto sobre datos deben preservarse:

| Migración | Propósito |
| --- | --- |
| `20260225112333_add_excluded_to_accounts.rb` | Añade `accounts.excluded` |
| `20260417132700_remove_loaned_from_entries.rb` | Retira la columna obsoleta `entries.loaned` |
| `20260430114500_migrate_transfers_to_excluded_accounts.rb` | Reclasifica transferencias hacia cuentas excluidas |
| `20260430122000_migrate_bidirectional_excluded_transfers.rb` | Recalcula ambos lados de transferencias con cuentas excluidas |
| `20260503152000_add_archived_to_accounts.rb` | Añade `accounts.archived` |
| `20260503160000_create_scheduled_payments.rb` | Crea definiciones de pagos programados |
| `20260503160100_create_scheduled_payment_entries.rb` | Crea ocurrencias/enlaces con entradas generadas |
| `20260508160000_fix_corrupted_transfer_outflow_amounts.rb` | Corrige importes de salida de transferencias programadas; irreversible |
| `20260817000000_add_custom_options_to_family_exports.rb` | Añade tipo, solicitante, rango, filtros y conteo a exportaciones |
| `20260908120000_add_amount_estimated_to_scheduled_payments.rb` | Identifica importes variables usados como estimación en Agenda |

`db/schema.rb` debe reflejar el resultado acumulado; no resolver sus conflictos de forma aislada sin comprobar estas migraciones.

## Manifiesto de rutas afectadas

Las 230 rutas del inventario original se agrupaban así. Tras la integración squash de septiembre el recuento bruto dejó de ser representativo, pero esta lista de áreas sigue siendo más estable y útil que copiar un `--name-status` que quedaría obsoleto en el siguiente commit:

- `.github/workflows/`: automatización propia del fork.
- `app/components/DS/`, `app/components/UI/`: componentes e interacciones personalizadas.
- `app/controllers/`: cuentas, informes, categorías, transacciones, transferencias, divisiones, pagos programados, presupuestos y exportaciones.
- `app/helpers/`: carteras, ajustes y transacciones.
- `app/javascript/controllers/`: selectores, multiselect, autocompletado, formularios, tags, tooltips y pagos programados.
- `app/jobs/`: generación de pagos y exportaciones.
- `app/models/`: cuentas, balances, informes, inversiones, transacciones, transferencias, sincronización, proveedores, exportaciones y pagos programados.
- `app/services/shared_expenses_calculator.rb`: cálculo propio de gastos compartidos.
- `app/views/`: cuentas, informes, inversiones, transacciones, transferencias, pagos programados, exportaciones y ajustes generales de UI.
- `config/locales/`: traducciones de todas las áreas anteriores.
- `config/routes.rb`, `config/schedule.yml`, `config/initializers/sidekiq.rb`: rutas y ejecución periódica.
- `db/migrate/` y `db/schema.rb`: las diez migraciones enumeradas y su esquema resultante.
- `test/`: cobertura de pagos programados, cuentas, transferencias, transacciones, exportaciones, Syncable y componentes DS.
- Raíz/scripts/docs: `Gemfile`, `README.md`, `informe_scheduled_payments.md`, `rollback-instructions.md`, `conflicts.txt`, `script.rb` y `script/debug_subtypes.rb`.

Para obtener el manifiesto exacto y actualizado de archivos en cualquier momento:

```powershell
git fetch upstream
$forkBase = git merge-base upstream/main HEAD
git diff --name-status "$forkBase...HEAD"
git diff --stat "$forkBase...HEAD"
```

Para ver sólo lo todavía no comprometido (incluido un bloque nuevo que aún no figure en este documento):

```powershell
git status --short
git diff --stat
git diff
```

## Protocolo para futuros merges desde upstream

1. Antes de actualizar, guardar los SHA de `upstream/main`, `HEAD` y el merge-base en la sección “Foto de referencia”.
2. Revisar este inventario por área funcional, no sólo por archivo: upstream puede mover o renombrar el código.
3. En conflictos de cuentas, preservar la separación entre `excluded`, `archived` y `exclude_from_reports`.
4. En conflictos de transacciones/transferencias, comprobar también pagos programados, informes y exportaciones; comparten modelos y controladores.
5. No aceptar automáticamente el `db/schema.rb`: validar primero las diez migraciones propias.
6. Si upstream incorpora una función equivalente, decidir expresamente si migrar a ella y añadir pruebas de regresión antes de retirar la implementación del fork.
7. Mantener Bills oculto en toda la interfaz, también con Preview Features. Conservar su implementación únicamente como referencia interna y portar funciones útiles hacia Pagos programados de forma selectiva y probada. Al resolver conflictos, integrar primero la evolución upstream del subsistema y reaplicar después la frontera pequeña formada por `bills_frontend_enabled?`, los guards de controlador y `Insight.for_product_frontend`; no resolverlos eliminando código Bills ni conectando ambos modelos.
8. En cambios de `IncomeStatement::Totals`, verificar los dos indicadores de transferencias con cuentas excluidas y versionar la clave de caché si cambia cualquier `Data.define` cacheado.
9. Probar Money In / Out y Spending Trend con `month_start_day = 25`, incluyendo selector, etiquetas, fechas inicial/final y corte del período activo en hoy.
10. Ejecutar, como mínimo, las pruebas enfocadas de cada bloque afectado; después ejecutar `bin/rails test`, `bin/rubocop`, `npm run lint` y `npm run format` según corresponda.
11. Actualizar este archivo en el mismo commit que añada, retire o sustituya una personalización del fork.

## Comandos de auditoría

```powershell
# Commits exclusivos del fork desde el ancestro común actual
git log --no-merges --oneline upstream/main..HEAD

# Diferencia comprometida completa
git diff --name-status upstream/main...HEAD
git diff --shortstat upstream/main...HEAD

# Migraciones propias
git diff --name-status upstream/main...HEAD -- db/migrate db/schema.rb

# Detectar si upstream ya tocó las mismas rutas después de una actualización
$oldBase = "79c826c0e3391063834887936bbe44dc1d90d0cf"
git diff --name-only "$oldBase..upstream/main"
git diff --name-only "$oldBase..HEAD"
```

## Criterio de mantenimiento

Una modificación se considera “nuestra” si añade comportamiento requerido por N7Home/N7Steve, adapta datos existentes a dicho comportamiento o es necesaria para operarlo/probarlo. Correcciones que ya estén resueltas de forma equivalente en upstream pueden eliminarse, pero la decisión debe quedar registrada actualizando este inventario.
