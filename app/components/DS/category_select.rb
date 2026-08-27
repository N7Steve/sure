class DS::CategorySelect < DesignSystemComponent
  attr_reader :form, :categories, :selected_id, :disabled, :auto_submit, :blank_label

  def initialize(
    form:,
    categories:,
    selected_id: nil,
    disabled: false,
    auto_submit: false,
    blank_label: nil
  )
    @form = form
    @categories = categories.to_a
    @selected_id = selected_id&.to_s
    @disabled = disabled
    @auto_submit = auto_submit
    @blank_label = blank_label
  end

  def field_name
    "#{form.object_name}[category_id]"
  end

  def field_id
    form.field_id(:category_id)
  end

  def trigger_id
    "category_id_trigger"
  end

  def menu_id
    "#{field_id}_menu"
  end

  def search_name_for(category)
    return category.display_name if category.parent_id.blank?

    parent = categories_by_id[category.parent_id.to_s]
    return category.display_name unless parent

    "#{parent.display_name} > #{category.display_name}"
  end

  private
    def categories_by_id
      @categories_by_id ||= categories.index_by { |category| category.id.to_s }
    end
end
