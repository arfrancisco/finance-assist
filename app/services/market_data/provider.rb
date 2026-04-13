module MarketData
  # Abstract interface for market data providers.
  # Concrete implementations (EodhdClient, future PseFtpClient) must implement all methods.
  class Provider
    def fetch_symbols(exchange:)
      raise NotImplementedError, "#{self.class}#fetch_symbols is not implemented"
    end

    def fetch_eod_prices(symbol:, from:, to:)
      raise NotImplementedError, "#{self.class}#fetch_eod_prices is not implemented"
    end

    def fetch_corporate_actions(symbol:)
      raise NotImplementedError, "#{self.class}#fetch_corporate_actions is not implemented"
    end

    def fetch_fundamentals(symbol:)
      raise NotImplementedError, "#{self.class}#fetch_fundamentals is not implemented"
    end

    def fetch_index_data(symbol:, from:, to:)
      raise NotImplementedError, "#{self.class}#fetch_index_data is not implemented"
    end
  end
end
