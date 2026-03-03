# Conventions

`Dex::Form` handles data holding, normalization, and validation. Persistence and record mapping are your responsibility – the form doesn't know (or care) how your data gets saved. These are the recommended patterns.

## .for – loading from a record

Define a class method that maps record attributes to form attributes and binds the record:

```ruby
class ProfileForm < Dex::Form
  model User

  attribute :name, :string
  attribute :email, :string

  def self.for(user)
    new(name: user.name, email: user.email).with_record(user)
  end
end
```

```ruby
@form = ProfileForm.for(current_user)
```

`with_record` sets `persisted?` to true and gives the uniqueness validator a record to exclude.

### Multi-model forms

This is where form objects really shine. When a single form spans multiple models, `.for` maps each model's data into the flat form structure:

```ruby
class OnboardingForm < Dex::Form
  attribute :first_name, :string
  attribute :last_name, :string
  attribute :email, :string
  attribute :department, :string
  attribute :position, :string
  attribute :start_date, :date

  normalizes :email, with: -> { _1&.strip&.downcase.presence }

  validates :email, presence: true, uniqueness: { model: User }
  validates :first_name, :last_name, :department, :position, presence: true

  nested_one :address do
    attribute :street, :string
    attribute :city, :string
    attribute :postal_code, :string
    attribute :country, :string
    validates :street, :city, :country, presence: true
  end

  nested_many :documents do
    attribute :document_type, :string
    attribute :document_number, :string
    validates :document_type, :document_number, presence: true
  end

  def self.for(user)
    employee = user.employee

    new(
      first_name: user.first_name,
      last_name: user.last_name,
      email: user.email,
      department: employee.department,
      position: employee.position,
      start_date: employee.start_date,
      address: {
        street: employee.address.street,
        city: employee.address.city,
        postal_code: employee.address.postal_code,
        country: employee.address.country
      },
      documents: employee.documents.map { |d|
        { document_type: d.document_type, document_number: d.document_number }
      }
    ).with_record(user)
  end
end
```

## #save – persisting with an Operation

The `save` method validates the form and delegates persistence to whatever makes sense for your app. The cleanest pattern uses a `Dex::Operation`:

```ruby
class OnboardingForm < Dex::Form
  include Dex::Match

  # ... attributes, validations, nested forms ...

  def save
    return false unless valid?

    case operation.safe.call
    in Ok then true
    in Err => e then errors.add(:base, e.message) and false
    end
  end

  private

  def operation
    Onboarding::Upsert.new(
      user: record, first_name:, last_name:, email:,
      department:, position:, start_date:,
      address: address.to_h,
      documents: documents.map(&:to_h)
    )
  end
end
```

The Operation handles all the multi-model persistence – creating or updating User, Employee, and Address inside a transaction:

```ruby
class Onboarding::Upsert < Dex::Operation
  prop :user, _Nilable(User)
  prop :first_name, String
  prop :last_name, String
  prop :email, String
  prop :department, String
  prop :position, String
  prop :start_date, Date
  prop :address, Hash
  prop :documents, _Array(Hash)

  def perform
    user = self.user || User.new
    user.update!(first_name:, last_name:, email:)

    employee = user.employee || user.build_employee
    employee.update!(department:, position:, start_date:, **address)

    sync_documents(employee)

    user
  end
end
```

### Simple persistence

For single-model forms, you can skip the Operation:

```ruby
def save
  return false unless valid?

  target = record || User.new
  target.update(name:, email:)
end
```

## Controller pattern

No `permit` needed – the form's attribute declarations are the whitelist. Just `require` the top-level key:

```ruby
class OnboardingController < ApplicationController
  def new
    @form = OnboardingForm.new
  end

  def create
    @form = OnboardingForm.new(params.require(:onboarding))

    if @form.save
      redirect_to dashboard_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @form = OnboardingForm.for(current_user)
  end

  def update
    @form = OnboardingForm.new(params.require(:onboarding)).with_record(current_user)

    if @form.save
      redirect_to dashboard_path
    else
      render :edit, status: :unprocessable_entity
    end
  end
end
```

## Testing

Forms are standard ActiveModel objects. Test them with plain Minitest – no special helpers needed:

```ruby
class OnboardingFormTest < Minitest::Test
  def test_validates_required_fields
    form = OnboardingForm.new
    assert form.invalid?
    assert form.errors[:email].any?
    assert form.errors[:first_name].any?
  end

  def test_normalizes_email
    form = OnboardingForm.new(email: "  ALICE@EXAMPLE.COM  ")
    assert_equal "alice@example.com", form.email
  end

  def test_nested_validation
    form = OnboardingForm.new(
      first_name: "Alice", last_name: "Smith",
      email: "alice@example.com",
      department: "Engineering", position: "Dev",
      start_date: Date.today,
      address: { street: "", city: "", country: "" }
    )
    assert form.invalid?
    assert form.errors[:"address.street"].any?
  end

  def test_serialization
    form = OnboardingForm.new(
      first_name: "Alice", email: "alice@example.com",
      address: { street: "123 Main", city: "NYC" }
    )
    h = form.to_h
    assert_equal "Alice", h[:first_name]
    assert_equal "123 Main", h[:address][:street]
  end
end
```
