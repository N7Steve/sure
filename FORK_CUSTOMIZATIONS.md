# Inventario de personalizaciones del fork N7Steve/sure

Este documento identifica la funcionalidad propia de este fork frente al repositorio principal de Sure. Su objetivo es servir como mapa de propiedad durante futuras actualizaciones de `upstream`, especialmente al resolver conflictos: qué comportamiento debemos preservar, dónde vive y qué pruebas o migraciones lo respaldan.

> Este inventario describe diferencias funcionales, no implica que debamos conservar ciegamente cada línea. Si `upstream` incorpora una solución equivalente, se debe comparar el comportamiento y retirar la duplicación de forma consciente.

## Foto de referencia

Inventario generado el **23 de agosto de 2026** sobre:

| Concepto | Valor |
| --- | --- |
| Fork | `origin` → `https://github.com/N7Steve/sure.git` |
| Repositorio principal | `upstream` → `https://github.com/we-promise/sure.git` |
| Rama inventariada | `main` |
| Base de `upstream/main` | `79c826c0e3391063834887936bbe44dc1d90d0cf` |
| HEAD del fork antes de los cambios actuales | `a01ed52905933a8846427077fccfb56a11303a40` |
| Merge-base | `79c826c0e3391063834887936bbe44dc1d90d0cf` |
| Diferencia comprometida | 205 commits; 230 archivos; +7.710 / -797 líneas |
| Cambios actuales sin commit | 15 archivos; +331 / -26 líneas, además de este inventario |

El alcance histórico de esta versión del documento es `upstream/main...a01ed5290`. Las ramas locales no fusionadas en `main` no forman parte del inventario.

## Resumen de propiedad

| Área | Propiedad | Debe preservarse al actualizar upstream |
| --- | --- | --- |
| Pagos recurrentes / programados | Propia | Modelos, generación, confirmación/rechazo, transferencias recurrentes e integración en transacciones |
| Informes personalizados | Propia | Resumen, desglose, gastos compartidos, exportación y secciones reordenables |
| Exclusión y archivo de cuentas | Propia | Las tres semánticas distintas: excluida, archivada y excluida sólo de informes |
| Roboadvisor e inversiones | Propia | Rendimiento, flujos, liquidez neta estimada y tratamiento fiscal |
| Categorías y transacciones | Propia | Creación/edición de categorías, selectores, búsqueda, formulario y detalle enriquecidos |
| Transferencias y divisiones | Propia o muy modificada | Clasificación con cuentas excluidas, conversión y splitting |
| Exportaciones de familia | Propia | Copia completa y CSV personalizado de transacciones |
| UI/UX | Propia o adaptada | Vistas compactas, cuentas agrupadas, componentes interactivos y mejoras responsive |
| Sincronización y proveedores | Soporte del fork | Cambios que mantienen la coherencia de cuentas y sincronizaciones con las funciones anteriores |
| Gestión familiar y usuarios | Propia, todavía sin commit | Claridad de roles/alcance y borrado seguro de la última persona de una familia |
| Workflows, scripts y documentos auxiliares | Revisar caso a caso | Están en el diff del fork, pero no todos son funcionalidad de producto |

## 1. Gestión familiar y de usuarios (cambios actuales sin commit)

Este bloque es posterior al HEAD de referencia y debe incluirse en el próximo commit junto con este inventario.

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
- Integración de pendientes y próximas ocurrencias en la pantalla de transacciones.
- Bloqueo contextual y enlace al pago de origen desde el detalle de una transacción generada.
- Tarea Rake, programación Sidekiq y documentación operativa.
- Reparación de importes de salida corruptos de transferencias recurrentes mediante migración irreversible.

### Núcleo y puntos de integración

- Modelos: `app/models/scheduled_payment.rb`, `scheduled_payment_entry.rb`, `scheduled_payment_occurrence.rb`.
- Controlador y job: `app/controllers/scheduled_payments_controller.rb`, `app/jobs/generate_scheduled_payments_job.rb`.
- UI: `app/views/scheduled_payments/`, parciales `_scheduled*` y `_pending_scheduled_entry` de transacciones, y `scheduled_payment_form_controller.js`.
- Integración: `app/models/account.rb`, `app/models/entry.rb`, `app/models/family.rb`, `app/models/transaction.rb`, `app/controllers/transactions_controller.rb`, `config/routes.rb`, `config/schedule.yml`, `config/initializers/sidekiq.rb`.
- Operación: `lib/tasks/scheduled_payments.rake`, `informe_scheduled_payments.md`.
- Cobertura: pruebas de modelo, controlador y job, más fixtures `scheduled_payment*`.

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
- Vista compacta persistente y alternador compacta/detallada.
- Creación manual y formulario reorganizado con descripción, cuenta, categoría, comercio, etiquetas, notas, naturaleza y datos de inversión.
- Autocompletado de descripciones por cuenta mediante `Transactions::DescriptionsController` y Stimulus.
- Búsqueda por comercio y filtros por cuentas, categorías, comercios, tipos, etiquetas, estado, fechas e importe.
- Detalle enriquecido con edición automática, indicadores, posibles duplicados, protección, contexto de transferencias/pagos programados y permisos de anotación.
- Actualización rápida de categoría, etiquetas y actividad de inversión.
- Borrado masivo y vistas Turbo actualizadas.

Archivos principales: `transactions_controller.rb`, `transactions/bulk_deletions_controller.rb`, `transactions/categorizes_controller.rb`, `transactions/descriptions_controller.rb`, `transaction.rb`, `transaction/search.rb`, `entry_search.rb`, vistas `transactions/`, helpers y controladores Stimulus relacionados.

## 7. Transferencias, matching y división de transacciones

- Gestión y presentación de transferencias desde formularios y detalle.
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
- Toast para deshacer el descarte de insights.
- Ajustes visuales en presupuestos, operaciones, cuentas, informes y dashboard.
- Traducciones propias, principalmente en `en` y `es`; el diff contiene además arreglos puntuales en otros idiomas.

Componentes/controladores especialmente sensibles a conflictos: `app/components/DS/`, `app/components/UI/`, `app/javascript/controllers/{select,multi_select,tag_select,tooltip,auto_submit_form,autocomplete,color_icon_picker}.js`, layout principal y vistas de cuentas/transacciones.

## 10. Sincronización, proveedores y soporte técnico

Este bloque aparece en el diff del fork y soporta las personalizaciones, aunque parte llegó en commits squash y debe revisarse con más cuidado al compararlo con nuevas versiones de upstream.

- Concern `Syncable` y pruebas de interfaz para normalizar el ciclo de sincronización.
- Ajustes en importadores/syncers de Coinbase, CoinStats, Enable Banking, Lunchflow y Mercury.
- Ajustes del proveedor Indexa Capital ligados a inversiones/roboadvisor.
- Cambios en `Family`, transfer matching y cuentas para mantener caché y sincronización coherentes.
- Configuración Sidekiq/schedule para pagos programados.
- Locales de proveedores y pequeños ajustes de presentación/configuración.

Rutas afectadas: `app/models/concerns/syncable.rb`, modelos/importers/syncers de los proveedores anteriores, `app/models/indexa_capital_item.rb`, `app/models/family.rb`, `config/initializers/sidekiq.rb` y `config/schedule.yml`.

## 11. Otros cambios propios o auxiliares

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

`db/schema.rb` debe reflejar el resultado acumulado; no resolver sus conflictos de forma aislada sin comprobar estas migraciones.

## Manifiesto de rutas afectadas

Las 230 rutas comprometidas se agrupan así. Esta lista de áreas es más estable y útil que copiar un `--name-status` que quedaría obsoleto en el siguiente commit:

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
- `db/migrate/` y `db/schema.rb`: las nueve migraciones enumeradas y su esquema resultante.
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
5. No aceptar automáticamente el `db/schema.rb`: validar primero las nueve migraciones propias.
6. Si upstream incorpora una función equivalente, decidir expresamente si migrar a ella y añadir pruebas de regresión antes de retirar la implementación del fork.
7. Ejecutar, como mínimo, las pruebas enfocadas de cada bloque afectado; después ejecutar `bin/rails test`, `bin/rubocop`, `npm run lint` y `npm run format` según corresponda.
8. Actualizar este archivo en el mismo commit que añada, retire o sustituya una personalización del fork.

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
