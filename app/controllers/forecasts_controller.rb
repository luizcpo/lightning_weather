class ForecastsController < ApplicationController
  def show
    @address = params[:address].to_s.strip
    @unit_system = params[:unit_system].presence_in(%w[imperial metric]) || "imperial"

    if @address.blank?
      respond_to do |format|
        format.html # render the empty search page
      end
      return
    end

    result = ForecastFetcher.call(address: @address, unit_system: @unit_system)

    if result.success?
      @forecast = result.value
    else
      @error = result.error
    end

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end
end
