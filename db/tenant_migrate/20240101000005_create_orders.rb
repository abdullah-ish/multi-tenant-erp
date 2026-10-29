class CreateOrders < ActiveRecord::Migration[7.2]
  def change
    create_table :orders do |t|
      t.references :shop, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string  :status, null: false, default: "pending"
      t.decimal :total,  precision: 10, scale: 2, null: false, default: 0
      t.datetime :reported_at

      t.timestamps
    end

    add_index :orders, [ :shop_id, :user_id ]
    add_index :orders, :reported_at
  end
end
