module ApplicationHelper
  def sortable_header_link(label, key:, default_direction:, current_sort:, current_direction:)
    selected = current_sort == key
    next_direction = if selected
      current_direction == "asc" ? "desc" : "asc"
    else
      default_direction
    end
    indicator = selected ? (current_direction == "asc" ? " ↑" : " ↓") : ""
    query = request.query_parameters.merge(sort: key, direction: next_direction)

    link_to "#{label}#{indicator}", url_for(query), class: "hover:underline", data: { turbo_action: "advance" }
  end

  def sortable_header_aria_sort(key:, current_sort:, current_direction:)
    return "none" unless current_sort == key

    current_direction == "asc" ? "ascending" : "descending"
  end

  def signed_currency(cents)
    return "—" if cents.nil?

    amount = number_to_currency(cents.abs / 100.0)
    return "+#{amount}" if cents.positive?
    return "−#{amount}" if cents.negative?

    amount
  end

  def budget_proposal_status(proposal, validation: nil)
    return "Applied" if proposal.applied?

    validation ||= BudgetProposals::Validation.call(proposal)
    validation.valid? ? "Ready" : "Invalid"
  end

  def budget_proposal_rationale(row)
    rationale = row["rationale"].to_s
    return "Recurring obligation" if row["recurring_obligation_cents"].to_i == row["proposed_cents"].to_i && row["proposed_cents"].to_i.positive?
    return "Prior budget" if row["previous_budget_cents"].to_i == row["proposed_cents"].to_i && row["proposed_cents"].to_i.positive?
    return "3-month spending average" if rationale.include?("three_month_average")

    rationale.presence&.humanize || "Proposal calculation"
  end

  def budget_proposal_month_label(value)
    Date.iso8601(value.to_s).strftime("%b %Y")
  rescue Date::Error
    value.to_s
  end
end
