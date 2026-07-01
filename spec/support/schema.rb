# Test schema for the dummy host app. Loaded fresh by spec/rails_helper.rb
# before the suite runs, so specs never depend on committed migration state.
#
# Note the tenant-first composite indexes and the unique index that includes
# the tenant column — the conventions TenantKit expects owned tables to follow.
ActiveRecord::Schema.define(version: 1) do
  create_table :accounts, force: true do |t|
    t.string :name, null: false
    t.string :subdomain
    t.string :domain
    t.timestamps
  end

  create_table :projects, force: true do |t|
    t.references :account, null: false, foreign_key: true
    t.string :name, null: false
    t.string :slug
    t.string :status
    t.timestamps
  end
  add_index :projects, [ :account_id, :status ]
  add_index :projects, [ :account_id, :slug ], unique: true

  create_table :invoices, force: true do |t|
    t.references :account, null: false, foreign_key: true
    t.string :number, null: false
    t.integer :amount_cents, default: 0, null: false
    t.timestamps
  end
  add_index :invoices, [ :account_id, :number ], unique: true
end
