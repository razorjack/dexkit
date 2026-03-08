# frozen_string_literal: true

module Dex
  class Railtie < Rails::Railtie
    rake_tasks do
      namespace :dex do
        desc "Export operation/event/handler contracts (FORMAT=hash|json_schema SECTION=operations|events|handlers FILE=path)"
        task export: :environment do
          Rails.application.eager_load!

          format = (ENV["FORMAT"] || "hash").to_sym
          section = ENV["SECTION"] || "operations"
          file = ENV["FILE"]

          data = case section
          when "operations" then Dex::Operation.export(format: format)
          when "events" then Dex::Event.export(format: format)
          when "handlers"
            if format != :hash
              raise "Handlers only support FORMAT=hash (got #{format})"
            end

            Dex::Event::Handler.export(format: format)
          else
            raise "Unknown SECTION=#{section}. Known: operations, events, handlers"
          end

          json = JSON.pretty_generate(data)

          if file
            File.write(file, json)
            puts "Wrote #{data.size} #{section} to #{file}"
          else
            puts json
          end
        end
      end
    end
  end
end
