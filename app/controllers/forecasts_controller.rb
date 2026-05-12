class ForecastsController < ApplicationController
  rescue_from ApplicationService::Error, with: :render_service_failure
  rescue_from ArgumentError,             with: :render_service_failure

  def show
    @address = params[:address].to_s.strip
    @unit_system = params[:unit_system].presence_in(%w[imperial metric]) || "imperial"

    if @address.blank?
      respond_to do |format|
        format.html
      end
      return
    end

    @forecast = ForecastFetcher.call(address: @address, unit_system: @unit_system)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  private

  def render_service_failure(exception)
    @error = exception.message
    @address ||= params[:address].to_s.strip
    @unit_system ||= params[:unit_system].presence_in(%w[imperial metric]) || "imperial"

    respond_to do |format|
      format.html         { render :show }
      format.turbo_stream { render :show }
    end
  end
end
