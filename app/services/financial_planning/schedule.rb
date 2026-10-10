module FinancialPlanning
  class Schedule
    def self.dates(rule, from:, to:)
      new(rule, from:, to:).dates
    end

    def initialize(rule, from:, to:)
      @rule = rule
      @from = from
      @to = to
    end

    def dates
      start_on = [ @rule.start_on, @from ].max
      end_on = @rule.end_on.present? ? [ @rule.end_on, @to ].min : @to
      return [] if start_on > end_on

      case @rule.cadence
      when "weekly", "biweekly"
        step = (@rule.cadence == "weekly" ? 7 : 14) * (@rule.interval || 1)
        build_by_days(next_weekday(start_on), end_on, step)
      when "monthly", "quarterly", "yearly"
        base = { "monthly" => 1, "quarterly" => 3, "yearly" => 12 }.fetch(@rule.cadence)
        day = @rule.day_of_month || 1
        build_by_months(next_month_day(start_on, day), end_on, base * (@rule.interval || 1), day)
      else
        []
      end
    end

    private

    def next_weekday(date)
      return nil if @rule.weekday.nil?

      date + ((@rule.weekday - date.wday) % 7).days
    end

    def next_month_day(date, day)
      candidate = safe_month_day(date, day)
      candidate < date ? safe_month_day(date.next_month, day) : candidate
    end

    def build_by_days(first, last, step)
      return [] unless first

      dates = []
      date = first
      while date <= last
        dates << date
        date += step.days
      end
      dates
    end

    def build_by_months(first, last, step, day)
      dates = []
      date = first
      while date <= last
        dates << date
        date = safe_month_day(date.next_month(step), day)
      end
      dates
    end

    def safe_month_day(date, day)
      Date.new(date.year, date.month, [ day, date.end_of_month.day ].min)
    end
  end
end
