class IncomeEstimatesController < ApplicationController
  def index
    @income_source = IncomeSource.find(params[:income_source_id])
    @income_estimates = @income_source.income_estimates.order(:start_on)
  end

  def new
    @income_source = IncomeSource.find(params[:income_source_id])
    @income_estimate = @income_source.income_estimates.new(active: true, cadence: "biweekly", interval: 1, weekday: 5, start_on: Date.current.beginning_of_month)
    @cadences = %w[weekly biweekly monthly]
  end

  def create
    @income_source = IncomeSource.find(params[:income_source_id])
    @income_estimate = @income_source.income_estimates.new(income_estimate_params)
    @cadences = %w[weekly biweekly monthly]

    if @income_estimate.save
      redirect_to income_source_income_estimates_path(@income_source), notice: "Created."
    else
      flash.now[:alert] = @income_estimate.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @income_source = IncomeSource.find(params[:income_source_id])
    @income_estimate = @income_source.income_estimates.find(params[:id])
    @cadences = %w[weekly biweekly monthly]
  end

  def update
    @income_source = IncomeSource.find(params[:income_source_id])
    @income_estimate = @income_source.income_estimates.find(params[:id])
    @cadences = %w[weekly biweekly monthly]

    if @income_estimate.update(income_estimate_params)
      redirect_to income_source_income_estimates_path(@income_source), notice: "Updated."
    else
      flash.now[:alert] = @income_estimate.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def income_estimate_params
    params.require(:income_estimate).permit(:cadence, :interval, :weekday, :day_of_month, :estimated_amount_cents, :start_on, :end_on, :active)
  end
end
