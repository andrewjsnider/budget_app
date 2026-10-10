module StatementEntries
  class CategoryResolver
    Result = Data.define(:category, :payee_rule_id)

    def self.call(description:, amount_cents:)
      rule = PayeeRule.where(active: true).includes(:category).order(:id).find do |candidate|
        candidate.matches?(description)
      end
      return Result.new(category: rule.category, payee_rule_id: rule.id) if rule

      name, kind = amount_cents.negative? ? [ "Uncategorized", "expense" ] : [ "Imported Income", "income" ]
      category = Category.find_or_initialize_by(name: name)
      if category.persisted? && category.kind != kind
        category.errors.add(:kind, "must be #{kind} for statement-created transactions")
        raise ActiveRecord::RecordInvalid.new(category)
      end
      unless category.persisted?
        category.assign_attributes(kind: kind, group: "Imported", archived: false)
        category.save!
      end

      Result.new(category: category, payee_rule_id: nil)
    end
  end
end
