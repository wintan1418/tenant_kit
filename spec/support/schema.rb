# Test schema for the dummy host app. Loaded fresh by spec/rails_helper.rb
# before the suite runs, so specs never depend on committed migration state.
#
# Note the tenant-first composite indexes and the unique index that includes
# the tenant column — the conventions TenantKit expects owned tables to follow.
#
# Beyond the basics, the schema deliberately contains every association shape
# the leak suite (spec/leaks) attacks: has_many :through, polymorphic
# belongs_to, STI, counter caches, nested attributes, Active Storage, and a
# global (non-tenant) model joined to tenant-owned rows.
connection = ActiveRecord::Base.connection

connection.disable_referential_integrity do
  ActiveRecord::Schema.define(version: 1) do
    # Drop children before parents so foreign keys never block a re-load.
    %i[
      active_storage_variant_records active_storage_attachments active_storage_blobs
      assignments comments tasks documents notes invoices projects users accounts
    ].each { |table| drop_table table, if_exists: true, force: :cascade }

    create_table :accounts do |t|
      t.string :name, null: false
      t.string :subdomain
      t.string :domain
      t.timestamps
    end

    create_table :projects do |t|
      t.references :account, null: false, foreign_key: true
      t.string :name, null: false
      t.string :slug
      t.string :status
      t.integer :tasks_count, default: 0, null: false
      t.timestamps
    end
    add_index :projects, [ :account_id, :status ]
    add_index :projects, [ :account_id, :slug ], unique: true

    create_table :invoices do |t|
      t.references :account, null: false, foreign_key: true
      t.string :number, null: false
      t.integer :amount_cents, default: 0, null: false
      t.timestamps
    end
    add_index :invoices, [ :account_id, :number ], unique: true

    create_table :tasks do |t|
      t.references :account, null: false, foreign_key: true
      t.references :project, null: false, foreign_key: true
      t.string :title, null: false
      t.timestamps
    end

    # A global (non-tenant) model: one user can work in several tenants.
    create_table :users do |t|
      t.string :email, null: false
      t.timestamps
    end

    create_table :assignments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.references :task, null: false, foreign_key: true
      t.timestamps
    end

    create_table :comments do |t|
      t.references :account, null: false, foreign_key: true
      t.references :commentable, polymorphic: true, null: false
      t.string :body, null: false
      t.timestamps
    end

    # STI: Contract and Proposal inherit from Document.
    create_table :documents do |t|
      t.references :account, null: false, foreign_key: true
      t.string :type
      t.string :title, null: false
      t.timestamps
    end

    # Explicit-scoping-mode model.
    create_table :notes do |t|
      t.references :account, null: false, foreign_key: true
      t.string :body, null: false
      t.timestamps
    end

    # Active Storage (mirrors the engine's own migration).
    create_table :active_storage_blobs do |t|
      t.string :key, null: false
      t.string :filename, null: false
      t.string :content_type
      t.text :metadata
      t.string :service_name, null: false
      t.bigint :byte_size, null: false
      t.string :checksum
      t.datetime :created_at, null: false
      t.index [ :key ], unique: true
    end

    create_table :active_storage_attachments do |t|
      t.string :name, null: false
      t.references :record, null: false, polymorphic: true, index: false
      t.references :blob, null: false
      t.datetime :created_at, null: false
      t.index [ :record_type, :record_id, :name, :blob_id ], name: :index_active_storage_attachments_uniqueness, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end

    create_table :active_storage_variant_records do |t|
      t.belongs_to :blob, null: false, index: false
      t.string :variation_digest, null: false
      t.index [ :blob_id, :variation_digest ], name: :index_active_storage_variant_records_uniqueness, unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end
  end
end
