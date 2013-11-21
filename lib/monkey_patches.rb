require 'logger' unless defined? Logger

unless Hash.new.respond_to? :symbolize_keys
  class Hash
    def symbolize_keys
      self.inject({}) do |hsh, arr|
        hsh[arr[0].to_sym] = arr[1]
        hsh
      end
    end
  end
end