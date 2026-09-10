class CreateMerchantCustomizations < ActiveRecord::Migration[8.1]
  def change
    create_table :merchant_customizations, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.references :merchant, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :merchant_customizations,
              [ :family_id, :merchant_id ],
              unique: true,
              name: "index_merchant_customizations_on_family_and_merchant"
  end
end
