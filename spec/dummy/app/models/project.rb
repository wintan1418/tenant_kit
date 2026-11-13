# An owned model in the dummy host app. Uses the default tenant association.
class Project < ApplicationRecord
  belongs_to_tenant
  validates_uniqueness_to_tenant :slug, allow_nil: true

  has_many :tasks, dependent: :destroy
  has_many :assignments, through: :tasks
  has_many :comments, as: :commentable
  has_one_attached :brief

  accepts_nested_attributes_for :tasks
end
