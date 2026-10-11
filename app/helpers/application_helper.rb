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

  def status_badge(label, tone: :neutral)
    content_tag(:span, label, class: "ui-badge ui-badge-#{tone}")
  end

  def budget_proposal_status_badge(proposal, validation: nil)
    status = budget_proposal_status(proposal, validation: validation)
    tone = { "Applied" => :positive, "Ready" => :positive, "Invalid" => :danger }.fetch(status, :warning)

    status_badge(status, tone: tone)
  end

  def navigation_link(label, path, active:)
    classes = "px-2.5 py-2 text-sm font-medium no-underline transition focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-amber-600"
    classes += active ? " border-b-2 border-amber-600 text-stone-950" : " border-b-2 border-transparent text-stone-600 hover:border-stone-300 hover:text-stone-950"

    link_to label, path, class: classes, aria: { current: ("page" if active) }
  end

  def expense_change_class(cents)
    return "text-stone-600" if cents.to_i.zero?

    cents.positive? ? "ui-money-negative" : "ui-money-positive"
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
