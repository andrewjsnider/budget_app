class CategoriesController < ApplicationController
  def index
    @categories = Category.order(:kind, :group, :name)
  end

  def edit
    @category = Category.find(params[:id])
  end

  def update
    @category = Category.find(params[:id])

    if @category.update(category_params)
      redirect_to categories_path, notice: "Updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def category_params
    params.require(:category).permit(:name, :group, :archived)
  end
end
