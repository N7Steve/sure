# Rollback Instructions

En caso de que los cambios implementados para arreglar el widget de Balance de Situación y la vista compacta de transacciones/actividad necesiten ser revertidos, sigue estas instrucciones copiando los contenidos antiguos.

## 1. `app/models/balance_sheet/classification_group.rb`
Elimina los métodos `display_total` y `display_total_money` que se añadieron:

```ruby
# Vuelve a dejar la clase así (borrando `display_total` y `display_total_money`):
class BalanceSheet::ClassificationGroup
  # ...
  def total
    accounts.reject(&:excluded?).select { |a| a.respond_to?(:included_in_finances?) ? a.included_in_finances? : true }.sum(&:converted_balance)
  end

  def syncing?
    accounts.any?(&:syncing?)
  end
  # ...
end
```

## 2. `app/models/balance_sheet/account_group.rb`
Revierte el método `weight`:

```ruby
  def weight
    return 0 if classification_group.total.zero?

    total / classification_group.total.to_d * 100
  end
```

## 3. `app/views/pages/dashboard/_balance_sheet.html.erb`
Reemplaza `display_total_money` por `total_money` en las dos ubicaciones editadas:

```erb
# Alrededor de la línea 14:
<span class="text-secondary font-medium text-lg privacy-sensitive"><%= classification_group.total_money.format(precision: 0) %></span>

# Alrededor de la línea 88:
<%
    # Calculate weight as percentage of classification total
    classification_total = classification_group.total_money.amount
    account_weight = classification_total.zero? ? 0 : account.converted_balance / classification_total * 100
%>
```

## 4. `config/routes.rb`
Elimina `patch :toggle_compact_view` de la colección de `transactions`:

```ruby
    collection do
      delete :clear_filter
      patch :update_preferences
      get :descriptions, to: "transactions/descriptions#index"
    end
```

## 5. `app/controllers/transactions_controller.rb`
Elimina el método `toggle_compact_view`:

```ruby
# Borrar estas líneas:
  def toggle_compact_view
    current_view = Current.user.transactions_compact_view?
    Current.user.update_transactions_preferences(compact_view: !current_view)
    redirect_back_or_to request.referer || transactions_path
  end
```

## 6. `app/views/transactions/_list.html.erb`
Restaura la estructura anterior sin los bloques `<% if Current.user.transactions_compact_view? %>`:
Quita la llamada al partial de compact table y el botón `toggle_compact_view_transactions_path`.

## 7. `app/views/accounts/show/_activity.html.erb`
Restaura la estructura anterior igual que en transacciones, eliminando los bloques if/else que controlan la vista compacta.

## 8. `app/views/entries/_compact_table.html.erb`
Puedes borrar este archivo completamente: `rm app/views/entries/_compact_table.html.erb`
