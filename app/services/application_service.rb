class ApplicationService
  Result = Struct.new(:success?, :value, :error, keyword_init: true) do
    def failure?
      !success?
    end

    def self.success(value)
      new(success?: true, value: value, error: nil)
    end

    def self.failure(error)
      new(success?: false, value: nil, error: error)
    end
  end

  def self.call(...)
    new(...).call
  end
end
