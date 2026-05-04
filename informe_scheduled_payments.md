# Informe Final: Sistema de Pagos Programados (Scheduled Payments)

> **Fecha:** Mayo 2026  
> **Estado:** Implementado y funcional con issues conocidos pendientes de resolver.  
> **Objetivo:** Documentación completa para que un LLM pueda continuar el desarrollo.

---

## 1. Visión General

Los **Pagos Programados** permiten al usuario crear reglas que generan transacciones automáticamente según una frecuencia definida (diaria, semanal, quincenal, mensual, trimestral, anual). El sistema genera **entries pendientes de confirmación** que el usuario puede aceptar (✓) o rechazar (✗) antes de que se materialicen como transacciones reales.

Este sistema es **independiente** del sistema de `RecurringTransaction` (detección automática de patrones). Ambos conviven:
- `RecurringTransaction` → detección pasiva de patrones existentes
- `ScheduledPayment` → creación activa de transacciones programadas por el usuario

---

## 2. Arquitectura

### 2.1 Archivos del sistema

| Componente | Archivo | Descripción |
|---|---|---|
| **Modelo principal** | `app/models/scheduled_payment.rb` | Regla de pago programado |
| **Modelo entries** | `app/models/scheduled_payment_entry.rb` | Entry generada (pending/confirmed/rejected) |
| **Controller** | `app/controllers/scheduled_payments_controller.rb` | CRUD + confirm/reject/toggle + confirm_early/skip |
| **Job** | `app/jobs/generate_scheduled_payments_job.rb` | Cron diario que genera entries pendientes |
| **Cron config** | `config/schedule.yml` (líneas 46-51) | `0 1 * * *` — diario a las 01:00 UTC |
| **Stimulus** | `app/javascript/controllers/scheduled_payment_form_controller.js` | Show/hide campo target_account |
| **Rake tasks** | `lib/tasks/scheduled_payments.rake` | `generate`, `generate_as`, `status`, `revert_future`, `purge_pending` |
| **Migración SP** | `db/migrate/20260503160000_create_scheduled_payments.rb` | Tabla `scheduled_payments` |
| **Migración entries** | `db/migrate/20260503160100_create_scheduled_payment_entries.rb` | Tabla `scheduled_payment_entries` |

### Vistas

| Archivo | Descripción |
|---|---|
| `app/views/scheduled_payments/index.html.erb` | Página Settings — tabla CRUD de pagos programados |
| `app/views/scheduled_payments/_form.html.erb` | Formulario new/edit (2 columnas, DS components) |
| `app/views/scheduled_payments/new.html.erb` | Wrapper para form |
| `app/views/scheduled_payments/edit.html.erb` | Wrapper para form |
| `app/views/transactions/_scheduled.html.erb` | Pestaña "Programados" en página de transacciones |
| `app/views/transactions/_scheduled_entry_row.html.erb` | Fila de entry pending con ✓/✗ |
| `app/views/transactions/_pending_scheduled_entry.html.erb` | Card compacta de entry pending (usada en Settings) |

### Locales

| Archivo | Idioma |
|---|---|
| `config/locales/views/scheduled_payments/en.yml` | Inglés |
| `config/locales/views/scheduled_payments/es.yml` | Español |

### Tests

| Archivo | Tipo |
|---|---|
| `test/models/scheduled_payment_test.rb` | Tests unitarios del modelo |
| `test/models/scheduled_payment_entry_test.rb` | Tests unitarios de entries |
| `test/controllers/scheduled_payments_controller_test.rb` | Tests de controlador |
| `test/jobs/generate_scheduled_payments_job_test.rb` | Tests del job |
| `test/fixtures/scheduled_payments.yml` | Vacío (tests crean inline) |
| `test/fixtures/scheduled_payment_entries.yml` | Vacío |

### Archivos existentes modificados

| Archivo | Cambio |
|---|---|
| `app/models/family.rb` | `has_many :scheduled_payments, dependent: :destroy` |
| `app/models/account.rb` | `has_many :scheduled_payments, dependent: :destroy` |
| `config/routes.rb` | Resources + member/collection actions |
| `app/controllers/transactions_controller.rb` | `@pending_scheduled` + `@upcoming_scheduled` en `index` |
| `app/views/transactions/index.html.erb` | Pestaña "Programados" condicional |
| `app/views/settings/_settings_nav.html.erb` | Link "Scheduled Payments" en nav |
| `config/locales/views/settings/en.yml` | `scheduled_payments_label` |
| `config/locales/views/settings/es.yml` | `scheduled_payments_label` |
| `config/locales/views/transactions/en.yml` | `tab_scheduled` |
| `config/locales/views/transactions/es.yml` | `tab_scheduled` |

---

## 3. Esquema de Base de Datos

### Tabla `scheduled_payments`

```
id                  uuid PK
family_id           uuid NOT NULL FK → families
account_id          uuid NOT NULL FK → accounts
category_id         uuid FK → categories (nullable)
merchant_id         uuid FK → merchants (nullable)
target_account_id   uuid FK → accounts (nullable, solo para transfers)
title               string NOT NULL
amount              decimal(19,4) NOT NULL
currency            string NOT NULL
frequency           string NOT NULL (daily|weekly|biweekly|monthly|quarterly|yearly)
frequency_day       integer NOT NULL (auto-calculado desde start_date)
start_date          date NOT NULL
end_date            date (nullable = indefinido)
next_run_date       date NOT NULL
status              string NOT NULL default:"active" (active|paused|completed)
payment_type        string NOT NULL default:"expense" (expense|income|transfer)
auto_confirm        boolean default:false
occurrences_count   integer default:0
created_at, updated_at
```

**Índices:**
- `(family_id, status)`
- `(next_run_date)`
- `(family_id, next_run_date) WHERE status = 'active'`

### Tabla `scheduled_payment_entries`

```
id                      uuid PK
scheduled_payment_id    uuid NOT NULL FK → scheduled_payments
entry_id                uuid FK → entries (nullable, se llena al confirmar)
transfer_entry_id       uuid FK → entries (nullable, solo para transfers)
scheduled_date          date NOT NULL
status                  string NOT NULL default:"pending" (pending|confirmed|rejected|skipped)
rejection_reason        text (nullable)
created_at, updated_at
```

**Índices:**
- `(scheduled_payment_id, scheduled_date)` UNIQUE
- `(status, scheduled_date)`

---

## 4. Rutas

```ruby
resources :scheduled_payments, only: %i[index new create edit update destroy] do
  collection do
    post :run_now          # Ejecutar job manualmente (admin debug)
  end
  member do
    post :toggle_status    # Pausar/reactivar
    post :confirm_entry    # Confirmar entry pending existente
    post :reject_entry     # Rechazar entry pending existente
    post :confirm_early    # Generar + confirmar entry anticipadamente
    post :skip_upcoming    # Generar + rechazar entry anticipadamente
  end
end
```

**Nota sobre `DS::Link` y métodos HTTP:** `DS::Link` genera `<a href>` (GET). Para POST/DELETE se debe usar `link_to` con `data: { turbo_method: :post }` o `button_to method: :post`. Esto ya está implementado correctamente en la tabla de Settings.

---

## 5. Flujo de Ejecución

### 5.1 Creación

```
Usuario → Settings → Scheduled Payments → New
  → Configura: título, cuenta, importe, categoría, merchant, frecuencia, fecha inicio
  → Controller: next_run_date = start_date, frequency_day = auto-derivado de start_date
  → Model: before_validation set_frequency_day_from_start_date
  → Guarda en DB
```

### 5.2 Generación automática (cron job)

```
Diariamente a las 01:00 UTC → GenerateScheduledPaymentsJob
  → ScheduledPayment.due_on_or_before(today)
  → Para cada SP activo con next_run_date <= hoy:
    → generate_pending_entry!
      → Crea ScheduledPaymentEntry(scheduled_date, status: "pending")
      → Si auto_confirm: confirma inmediatamente
      → advance_next_run_date! → mueve next_run_date al siguiente ciclo
```

### 5.3 Confirmación por el usuario

```
Usuario ve entry pending en UI → Click ✓
  → confirm_entry action
    → ScheduledPaymentEntry#confirm!
      → Si expense/income: crea Transaction + Entry en la cuenta
      → Si transfer: crea outflow Entry + inflow Entry + Transfer record
      → status = "confirmed"
```

### 5.4 Rechazo

```
Usuario ve entry pending → Click ✗
  → reject_entry action
    → ScheduledPaymentEntry#reject!(reason)
    → status = "rejected", no se crea ninguna transacción
```

### 5.5 Confirmación anticipada (pagos futuros)

```
Usuario ve pago en "Upcoming this month" → Click ✓ (Confirm now)
  → confirm_early action
    → generate_pending_entry! (crea la entry)
    → entry.confirm! (confirma inmediatamente)
    → advance_next_run_date!
```

---

## 6. UI — Tres ubicaciones

### 6.1 Settings → Scheduled Payments (`scheduled_payments/index.html.erb`)

Tabla HTML compacta (estilo `<table>` como recurring_transactions) con:
- Merchant logo/icono + título + frecuencia + badge pending count
- Importe, cuenta, próxima ejecución, status (Active/Paused/Completed)
- Acciones: ✓ confirm / ✗ reject (si hay pending) + edit + pause/play + delete
- Sección "Pending confirmations" arriba con cards
- Botón "Run job now" (debug) + "New" en page_actions

### 6.2 Transacciones → Pestaña "Programados" (`transactions/_scheduled.html.erb`)

Dos secciones:
- **"Pending confirmations"** — entries generadas pendientes de ✓/✗ (via `_scheduled_entry_row.html.erb`)
- **"Upcoming this month"** — pagos activos cuyo `next_run_date` cae este mes pero aún no generados, con botones "Confirm now" / "Skip"

### 6.3 Formulario (`scheduled_payments/_form.html.erb`)

Grid 2 columnas usando `StyledFormBuilder`:
- `collection_select` con `variant: :logo` para accounts/merchants
- `collection_select` con `variant: :badge, searchable: true` para categories (`.alphabetically_by_hierarchy`)
- `f.select` con `label:` para currency, payment_type, frequency
- Campo `target_account` visible solo si `payment_type == "transfer"` (Stimulus controller)
- `frequency_day` eliminado del formulario — se auto-calcula desde `start_date`

---

## 7. Lógica del Modelo

### 7.1 `frequency_day` — auto-derivado de `start_date`

`frequency_day` NO se muestra en el formulario. Se calcula automáticamente via `before_validation :set_frequency_day_from_start_date`:

| Frecuencia | `frequency_day` = |
|---|---|
| daily | 0 |
| weekly / biweekly | `start_date.wday` (0=Sunday...6=Saturday) |
| monthly / quarterly / yearly | `start_date.day` (1-31) |

### 7.2 `next_run_date` — sincronización con `start_date`

`before_validation :sync_next_run_date_with_start_date` se ejecuta si `start_date` cambia. Resetea `next_run_date = start_date`.

### 7.3 `generate_pending_entry!` — idempotente

```ruby
def generate_pending_entry!
  return if end_date.present? && next_run_date > end_date
  existing = scheduled_payment_entries.find_by(scheduled_date: next_run_date)
  return existing if existing  # Idempotente: no duplica si ya existe
  entry_record = scheduled_payment_entries.create!(scheduled_date: next_run_date, status: "pending")
  entry_record.confirm! if auto_confirm
  advance_next_run_date!
  entry_record
end
```

### 7.4 Transfers multi-divisa

`create_transfer_entries!` usa `sp.target_account.currency` para la entry de inflow (no `sp.currency`). Esto maneja correctamente transfers entre cuentas con divisas diferentes.

---

## 8. Tabs condicionales en la página de transacciones

```ruby
# transactions/index.html.erb
show_upcoming_tab = !Current.family.recurring_transactions_disabled?
show_scheduled_tab = Current.family.scheduled_payments.accessible_by(Current.user).any?
show_tabs = show_upcoming_tab || show_scheduled_tab
```

- **Sin tabs** (recurring deshabilitado Y sin scheduled payments) → solo lista de transacciones
- **"Upcoming"** solo si recurring habilitado
- **"Programados"** solo si hay algún scheduled payment

---

## 9. Rake Tasks (Debug/Testing)

```bash
# Ver estado de todos los pagos y sus entries
bin/rails scheduled_payments:status

# Ejecutar el job como haría el cron
bin/rails scheduled_payments:generate

# Simular ejecución para una fecha futura
bin/rails "scheduled_payments:generate_as[2026-05-10]"

# Revertir entries futuras generadas por error
bin/rails scheduled_payments:revert_future

# Borrar TODAS las entries pending (con confirmación)
bin/rails scheduled_payments:purge_pending
```

---

## 10. Issues Conocidos y Pendientes

### 10.1 Bugs del sistema de RecurringTransaction (NO de Scheduled Payments)

Estos bugs están documentados en `informe_recurring.md` y NO han sido corregidos:

1. **Recurrentes eliminados se re-crean** — El `Identifier` usa `find_or_initialize_by` sin mecanismo de "dismiss". Solución propuesta: crear modelo `DismissedRecurringPattern`.
2. **Transferencias se detectan como recurrentes** — El `Identifier` no filtra por `transaction.kind`, detectando ambos lados de transfers. Solución: excluir `Transaction::TRANSFER_KINDS`.

### 10.2 Posibles mejoras futuras de Scheduled Payments

- **Exchange rate para transfers multi-divisa** — Actualmente usa el mismo importe nominal. Podría añadirse un campo `exchange_rate` al modelo.
- **Notificaciones** — Enviar email/push cuando hay entries pending sin confirmar.
- **Historial** — Vista detallada de un scheduled payment con todas sus entries pasadas.
- **Migración de recurrentes manuales** — Opción para convertir un `RecurringTransaction` manual en un `ScheduledPayment`.

---

## 11. Convenciones Técnicas Importantes

### 11.1 `StyledFormBuilder`

El formulario usa `styled_form_with` que provee `StyledFormBuilder`. Las reglas clave:

- **NO usar `class: "input"` ni `class: "label"`** — El builder genera las clases automáticamente via `form-field__input` y `form-field__label` cuando se usa `label: "..."`.
- **`collection_select`** se renderiza como `DS::Select`. Signature:
  ```ruby
  f.collection_select :method, collection, :value_method, :text_method,
    { label: "...", variant: :badge/:logo/:simple, searchable: true/false, prompt: "..." },
    { data: {...}, required: true }
  ```
- **`include_blank`** debe ser un string (ej: `"None"`), nunca `true` (se renderiza como texto literal "true").
- **`variant: :badge`** para categorías → badges con color e icono Lucide
- **`variant: :logo`** para accounts y merchants → logo/avatar
- **`f.submit`** renderiza `DS::Button` automáticamente

### 11.2 `DS::Link` no soporta `method:`

`DS::Link` genera `<a href>` (siempre GET). Para acciones POST/DELETE:
- Usar `link_to` con `data: { turbo_method: :delete }` 
- O `button_to` con `method: :post` (genera `<form>`)

### 11.3 Categorías — orden jerárquico

Usar `.alphabetically_by_hierarchy` (NO `.alphabetically`) para que subcategorías aparezcan debajo de su padre:
```
padre1, hijo1a, hijo1b, padre2, hijo2a...
```

### 11.4 Importes — convención de signos

- Expense: `amount` se almacena positivo, se muestra negado: `format_money(-sp.amount_money)`
- Income: `amount` se almacena positivo, se muestra positivo con clase `text-success`
- En `create_transaction_entry!`: `expense? ? sp.amount.abs : -sp.amount.abs`

---

## 12. Estructura del Cron (Sidekiq)

```yaml
# config/schedule.yml
generate_scheduled_payments:
  cron: "0 1 * * *"
  class: "GenerateScheduledPaymentsJob"
  queue: "scheduled"
  description: "Generates pending scheduled payments due up to today"
```

Se carga en `config/initializers/sidekiq.rb` via `Sidekiq::Cron::Job.load_from_hash(schedule)`.
