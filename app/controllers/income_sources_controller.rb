class IncomeSourcesController < ApplicationController
  def index
    @income_sources = IncomeSource.includes(:account, :category).order(:name)
  end

  def new
    @income_source = IncomeSource.new(active: true)
    load_selects
  end

  def create
    @income_source = IncomeSource.new(income_source_params)
    if @income_source.save
      redirect_to income_sources_path, notice: "Created."
    else
      load_selects
      flash.now[:alert] = @income_source.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @income_source = IncomeSource.find(params[:id])
    load_selects
  end

  def update
    @income_source = IncomeSource.find(params[:id])
    if @income_source.update(income_source_params)
      redirect_to income_sources_path, notice: "Updated."
    else
      load_selects
      flash.now[:alert] = @income_source.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def income_source_params
    params.require(:income_source).permit(:name, :kind, :active, :account_id, :category_id)
  end

  def load_selects
    @accounts = Account.where(archived: [false, nil]).order(:name)
    @income_categories = Category.where(kind: "income", archived: [false, nil]).order(:name)
  end
end
