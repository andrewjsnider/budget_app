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
end
