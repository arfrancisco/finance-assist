module Types
  class DisclosureType < Types::BaseObject
    field :id, ID, null: false
    field :disclosure_type, String, null: true
    field :title, String, null: true
    field :body_text, String, null: true
    field :disclosure_date, String, null: true
    field :source_url, String, null: true

    def disclosure_date
      object.disclosure_date&.iso8601
    end
  end
end
