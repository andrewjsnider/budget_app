module FinancialActions
  class ReferenceResolver
    class MissingReference < StandardError; end
    class AmbiguousReference < StandardError; end

    def self.category(reference, kind: nil)
      scope = Category.all
      scope = scope.where(kind: kind) if kind
      scope = if reference.is_a?(Integer) || reference.to_s.match?(/\A\d+\z/)
        scope.where(id: reference.to_i)
      else
        scope.where("LOWER(name) = ?", reference.to_s.strip.downcase)
      end
      records = scope.limit(2).to_a
      raise MissingReference, "Category not found: #{reference}" if records.empty?
      raise AmbiguousReference, "Category is ambiguous: #{reference}" if records.many?

      records.sole
    end

    def self.account(import_key)
      account = Account.find_by(import_key: import_key.to_s)
      raise MissingReference, "Account not found: #{import_key}" unless account
      raise MissingReference, "Account is archived: #{import_key}" if account.archived?

      account
    end
  end
end
