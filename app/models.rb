class DMFollow < ActiveRecord::Base
  self.table_name = 'dmfollow'

  validates :lft, length: {minimum: 2}
  validates :rgt, length: {minimum: 2}

  def to_s
    "<#{self.class.name}: #{self.lft} -> #{self.rgt}>"
  end
end

